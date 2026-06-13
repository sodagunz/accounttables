const fs = require("node:fs/promises");
const { GoogleAuth } = require("google-auth-library");

const projectId = process.argv[2];
const rulesPath = process.argv[3] || "firestore.rules";

if (!projectId) {
  console.error("Usage: node scripts/deploy-firestore-rules.cjs <project-id> [rules-file]");
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("GOOGLE_APPLICATION_CREDENTIALS must point to a service-account JSON file.");
  process.exit(1);
}

const baseUrl = "https://firebaserules.googleapis.com/v1";
const releaseName = `projects/${projectId}/releases/cloud.firestore`;

async function main() {
  const rules = await fs.readFile(rulesPath, "utf8");
  const auth = new GoogleAuth({
    scopes: [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/firebase",
    ],
  });
  const client = await auth.getClient();

  const ruleset = await request(client, {
    method: "POST",
    url: `${baseUrl}/projects/${projectId}/rulesets`,
    data: {
      source: {
        files: [
          {
            name: rulesPath,
            content: rules,
          },
        ],
      },
    },
  });

  await updateRelease(client, ruleset.name);
  console.log(`Deployed ${rulesPath} to ${releaseName} with ${ruleset.name}`);
}

async function updateRelease(client, rulesetName) {
  const release = {
    name: releaseName,
    rulesetName,
  };

  try {
    await request(client, {
      method: "PATCH",
      url: `${baseUrl}/${releaseName}`,
      data: { release },
    });
  } catch (error) {
    if (error.response?.status !== 404) {
      throw error;
    }

    await request(client, {
      method: "POST",
      url: `${baseUrl}/projects/${projectId}/releases`,
      data: release,
    });
  }
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
