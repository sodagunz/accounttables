const fs = require("node:fs/promises");
const path = require("node:path");
const { GoogleAuth } = require("google-auth-library");

const args = process.argv.slice(2);
const projectId = args[0];

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("GOOGLE_APPLICATION_CREDENTIALS must point to a service-account JSON file.");
  process.exit(1);
}

if (!projectId) {
  printUsage();
  process.exit(1);
}

const parsedCommand = parseCommand(args.slice(1));
if (!parsedCommand) {
  printUsage();
  process.exit(1);
}

const databaseRoot = `projects/${projectId}/databases/(default)/documents`;
const baseUrl = "https://firestore.googleapis.com/v1";

async function main() {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/datastore"],
  });
  const client = await auth.getClient();

  if (parsedCommand.action === "export") {
    const exportData =
      parsedCommand.mode === "all"
        ? await exportAllCollections(client)
        : await exportLedger(client, parsedCommand.ledgerId);

    const filePath =
      parsedCommand.filePath ||
      (parsedCommand.mode === "all"
        ? timestampedPath("firestore-backup")
        : timestampedPath(`ledger-${parsedCommand.ledgerId}`));

    await writeJsonFile(filePath, exportData);
    console.log(`Wrote ${filePath}`);
    return;
  }

  const importData = await readJsonFile(parsedCommand.filePath);
  await importBackup(client, importData, parsedCommand);
}

function parseCommand(commandArgs) {
  const [first, second, third, fourth] = commandArgs;

  if (!first) {
    return null;
  }

  if (first === "export") {
    if (second === "all") {
      return {
        action: "export",
        mode: "all",
        filePath: third || null,
      };
    }

    if (second === "ledger" && third) {
      return {
        action: "export",
        mode: "ledger",
        ledgerId: third,
        filePath: fourth || null,
      };
    }

    return null;
  }

  if (first === "import") {
    if (!second) {
      return null;
    }

    return {
      action: "import",
      filePath: second,
      targetLedgerId: third || null,
    };
  }

  if (first === "all") {
    return {
      action: "export",
      mode: "all",
      filePath: second || null,
    };
  }

  if (first === "ledger" && second) {
    return {
      action: "export",
      mode: "ledger",
      ledgerId: second,
      filePath: third || null,
    };
  }

  return null;
}

function printUsage() {
  console.error(`Usage:
  node scripts/export-firestore.cjs <project-id> export all [output-file]
  node scripts/export-firestore.cjs <project-id> export ledger <ledger-id> [output-file]
  node scripts/export-firestore.cjs <project-id> import <input-file> [target-ledger-id]

Backward-compatible export forms:
  node scripts/export-firestore.cjs <project-id> all [output-file]
  node scripts/export-firestore.cjs <project-id> ledger <ledger-id> [output-file]

Notes:
  - import performs upserts only; it does not delete remote documents missing from the backup.
  - [target-ledger-id] is only valid for ledger backups and lets you restore into a different ledger id.`);
}

async function writeJsonFile(filePath, value) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(value, null, 2));
}

async function readJsonFile(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

async function exportAllCollections(client) {
  const collections = await listCollectionIds(client, databaseRoot);
  const data = {};

  for (const collectionId of collections) {
    console.log(`Exporting collection ${collectionId}`);
    data[collectionId] = await exportCollection(client, databaseRoot, collectionId);
  }

  return {
    projectId,
    exportedAt: new Date().toISOString(),
    mode: "all",
    collections: data,
  };
}

async function exportLedger(client, ledgerId) {
  const ledgerPath = `${databaseRoot}/ledgers/${ledgerId}`;
  const ledger = await exportDocumentTree(client, ledgerPath);

  if (!ledger) {
    throw new Error(`Ledger ${ledgerId} not found`);
  }

  return {
    projectId,
    exportedAt: new Date().toISOString(),
    mode: "ledger",
    ledger,
  };
}

async function exportCollection(client, parentPath, collectionId) {
  const documents = await listDocuments(client, parentPath, collectionId);
  const exported = {};

  for (const document of documents) {
    const relativeName = document.name.slice(`${databaseRoot}/`.length);
    const documentId = lastSegment(document.name);
    console.log(`  Exporting ${relativeName}`);
    exported[documentId] = await exportDocumentTree(client, document.name, document);
  }

  return exported;
}

async function exportDocumentTree(client, documentPath, knownDocument) {
  const document = knownDocument || (await getDocument(client, documentPath));

  if (!document) {
    return null;
  }

  const collectionIds = await listCollectionIds(client, documentPath);
  const subcollections = {};

  for (const collectionId of collectionIds) {
    subcollections[collectionId] = await exportCollection(client, documentPath, collectionId);
  }

  return {
    id: lastSegment(document.name),
    path: document.name.slice(`${databaseRoot}/`.length),
    createTime: document.createTime,
    updateTime: document.updateTime,
    fields: decodeFields(document.fields || {}),
    raw: document,
    subcollections,
  };
}

async function getDocument(client, documentPath) {
  try {
    const response = await request(client, {
      method: "GET",
      url: `${baseUrl}/${documentPath}`,
    });

    return response;
  } catch (error) {
    if (error.response?.status === 404) {
      return null;
    }

    throw error;
  }
}

async function listCollectionIds(client, parentPath) {
  const collectionIds = [];
  let pageToken = null;

  do {
    const response = await request(client, {
      method: "POST",
      url: `${baseUrl}/${parentPath}:listCollectionIds`,
      data: pageToken ? { pageToken, pageSize: 100 } : { pageSize: 100 },
    });

    collectionIds.push(...(response.collectionIds || []));
    pageToken = response.nextPageToken || null;
  } while (pageToken);

  return collectionIds.sort();
}

async function listDocuments(client, parentPath, collectionId) {
  const documents = [];
  let pageToken = null;

  do {
    const query = new URLSearchParams({ pageSize: "1000" });
    if (pageToken) {
      query.set("pageToken", pageToken);
    }

    const response = await request(client, {
      method: "GET",
      url: `${baseUrl}/${parentPath}/${collectionId}?${query.toString()}`,
    });

    documents.push(...(response.documents || []));
    pageToken = response.nextPageToken || null;
  } while (pageToken);

  return documents.sort((left, right) => left.name.localeCompare(right.name));
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]),
  );
}

function decodeValue(value) {
  if (value.nullValue !== undefined) {
    return null;
  }

  if (value.booleanValue !== undefined) {
    return value.booleanValue;
  }

  if (value.integerValue !== undefined) {
    return Number(value.integerValue);
  }

  if (value.doubleValue !== undefined) {
    return value.doubleValue;
  }

  if (value.timestampValue !== undefined) {
    return value.timestampValue;
  }

  if (value.stringValue !== undefined) {
    return value.stringValue;
  }

  if (value.bytesValue !== undefined) {
    return value.bytesValue;
  }

  if (value.referenceValue !== undefined) {
    return value.referenceValue;
  }

  if (value.geoPointValue !== undefined) {
    return value.geoPointValue;
  }

  if (value.arrayValue !== undefined) {
    return (value.arrayValue.values || []).map(decodeValue);
  }

  if (value.mapValue !== undefined) {
    return decodeFields(value.mapValue.fields || {});
  }

  return value;
}

async function importBackup(client, backup, options) {
  if (backup?.mode === "all") {
    if (options.targetLedgerId) {
      throw new Error("target-ledger-id can only be used with ledger backups");
    }

    await importAllCollections(client, backup.collections || {});
    console.log(`Imported full backup from ${options.filePath}`);
    return;
  }

  if (backup?.mode === "ledger") {
    const ledger = backup.ledger;
    if (!ledger) {
      throw new Error("Ledger backup is missing the ledger payload");
    }

    const targetLedgerId = options.targetLedgerId || ledger.id;
    await importLedger(client, ledger, targetLedgerId);
    console.log(`Imported ledger ${ledger.id} into ${targetLedgerId} from ${options.filePath}`);
    return;
  }

  throw new Error("Unsupported backup format: expected mode 'all' or 'ledger'");
}

async function importAllCollections(client, collections) {
  for (const [collectionId, documents] of Object.entries(collections)) {
    console.log(`Importing collection ${collectionId}`);
    await importCollection(client, databaseRoot, collectionId, documents || {});
  }
}

async function importLedger(client, ledgerDocument, targetLedgerId) {
  const ledgerPath = `${databaseRoot}/ledgers/${targetLedgerId}`;
  await importDocumentTree(
    client,
    ledgerPath,
    rewriteLedgerDocument(ledgerDocument, targetLedgerId),
  );
}

async function importCollection(client, parentPath, collectionId, documents) {
  for (const [documentId, documentNode] of Object.entries(documents)) {
    const documentPath = `${parentPath}/${collectionId}/${documentId}`;
    console.log(`  Importing ${documentPath.slice(`${databaseRoot}/`.length)}`);
    await importDocumentTree(client, documentPath, documentNode);
  }
}

async function importDocumentTree(client, documentPath, documentNode) {
  if (!documentNode) {
    return;
  }

  const fields = encodeDocumentFields(documentNode);
  await request(client, {
    method: "PATCH",
    url: `${baseUrl}/${documentPath}`,
    data: { fields },
  });

  for (const [collectionId, documents] of Object.entries(documentNode.subcollections || {})) {
    await importCollection(client, documentPath, collectionId, documents || {});
  }
}

function rewriteLedgerDocument(ledgerDocument, targetLedgerId) {
  const cloned = deepClone(ledgerDocument);
  const originalLedgerId = ledgerDocument.id;

  cloned.id = targetLedgerId;
  cloned.path = `ledgers/${targetLedgerId}`;

  if (cloned.fields && typeof cloned.fields === "object") {
    cloned.fields.id = targetLedgerId;
  }

  rewriteNestedPaths(cloned.subcollections || {}, ["userLedgers"], (documentNode) => {
    if (documentNode.fields?.ledgerId === originalLedgerId) {
      documentNode.fields.ledgerId = targetLedgerId;
    }
  });

  rewriteNestedPaths(cloned.subcollections || {}, ["emailInvites"], (documentNode) => {
    if (documentNode.fields?.ledgerId === originalLedgerId) {
      documentNode.fields.ledgerId = targetLedgerId;
    }
  });

  return cloned;
}

function rewriteNestedPaths(subcollections, collectionPath, visitor) {
  if (collectionPath.length === 0) {
    return;
  }

  const [collectionId, ...remainingPath] = collectionPath;
  const documents = subcollections[collectionId] || {};

  for (const documentNode of Object.values(documents)) {
    if (remainingPath.length === 0) {
      visitor(documentNode);
      continue;
    }

    rewriteNestedPaths(documentNode.subcollections || {}, remainingPath, visitor);
  }
}

function encodeDocumentFields(documentNode) {
  if (documentNode.raw?.fields) {
    return documentNode.raw.fields;
  }

  return encodeFields(documentNode.fields || {});
}

function encodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, encodeValue(value)]),
  );
}

function encodeValue(value) {
  if (value === null) {
    return { nullValue: null };
  }

  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map(encodeValue),
      },
    };
  }

  if (typeof value === "boolean") {
    return { booleanValue: value };
  }

  if (typeof value === "number") {
    if (Number.isInteger(value)) {
      return { integerValue: String(value) };
    }

    return { doubleValue: value };
  }

  if (typeof value === "string") {
    if (looksLikeTimestamp(value)) {
      return { timestampValue: value };
    }

    return { stringValue: value };
  }

  if (isGeoPoint(value)) {
    return {
      geoPointValue: {
        latitude: value.latitude,
        longitude: value.longitude,
      },
    };
  }

  if (value && typeof value === "object") {
    return {
      mapValue: {
        fields: encodeFields(value),
      },
    };
  }

  throw new Error(`Unsupported Firestore value: ${String(value)}`);
}

function looksLikeTimestamp(value) {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value);
}

function isGeoPoint(value) {
  return (
    value &&
    typeof value === "object" &&
    typeof value.latitude === "number" &&
    typeof value.longitude === "number" &&
    Object.keys(value).length === 2
  );
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function timestampedPath(prefix) {
  const stamp = new Date().toISOString().replaceAll(":", "-");
  return path.join("backups", `${prefix}-${stamp}.json`);
}

function lastSegment(value) {
  const segments = value.split("/");
  return segments[segments.length - 1];
}

async function request(client, options) {
  try {
    const response = await client.request(options);
    return response.data;
  } catch (error) {
    const status = error.response?.status;
    const data = error.response?.data;

    if (status || data) {
      console.error(JSON.stringify({ status, data }, null, 2));
    }

    throw error;
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
