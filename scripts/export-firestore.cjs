const fs = require("node:fs/promises");
const path = require("node:path");
const { GoogleAuth } = require("google-auth-library");

const projectId = process.argv[2];
const mode = process.argv[3];
const targetId = mode === "ledger" ? process.argv[4] || null : null;
const outputPath = mode === "ledger" ? process.argv[5] || null : process.argv[4] || null;

if (!projectId || !mode || !["all", "ledger"].includes(mode)) {
  console.error(
    "Usage: node scripts/export-firestore.cjs <project-id> <all|ledger> [ledger-id] [output-file]",
  );
  process.exit(1);
}

if (mode === "ledger" && !targetId) {
  console.error(
    "Usage for ledger export: node scripts/export-firestore.cjs <project-id> ledger <ledger-id> [output-file]",
  );
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("GOOGLE_APPLICATION_CREDENTIALS must point to a service-account JSON file.");
  process.exit(1);
}

const databaseRoot = `projects/${projectId}/databases/(default)/documents`;
const baseUrl = "https://firestore.googleapis.com/v1";

async function main() {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/datastore"],
  });
  const client = await auth.getClient();

  const exportData =
    mode === "all" ? await exportAllCollections(client) : await exportLedger(client, targetId);

  const filePath =
    outputPath ||
    (mode === "all" ? timestampedPath("firestore-backup") : timestampedPath(`ledger-${targetId}`));

  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(exportData, null, 2));
  console.log(`Wrote ${filePath}`);
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
