const fs = require("fs");
const path = require("path");

function loadFirebaseAdmin() {
  const candidatePaths = [
    "firebase-admin",
    path.resolve(__dirname, "../functions/node_modules/firebase-admin"),
  ];

  for (const candidate of candidatePaths) {
    try {
      return require(candidate);
    } catch (error) {
      if (error.code !== "MODULE_NOT_FOUND") {
        throw error;
      }
    }
  }

  throw new Error("Unable to load firebase-admin.");
}

const admin = loadFirebaseAdmin();

function loadServiceAccount() {
  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inlineJson) {
    return JSON.parse(inlineJson);
  }

  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialsPath) {
    throw new Error(
      "Set FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS before running this script.",
    );
  }

  return JSON.parse(fs.readFileSync(credentialsPath, "utf8"));
}

async function main() {
  const teamCode = (process.argv[2] || "").trim();
  const shouldDelete = process.argv.includes("--confirm");

  if (!teamCode) {
    throw new Error("Usage: node ProdConnect/scripts/delete_team_gear.js <TEAM_CODE> [--confirm]");
  }

  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id || "prodconnect-1ea3a";

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  const db = admin.firestore();
  const snapshot = await db.collection("gear").where("teamCode", "==", teamCode).get();
  const docs = snapshot.docs;

  console.log(`Found ${docs.length} gear docs for team ${teamCode}.`);

  if (!shouldDelete) {
    console.log("Dry run only. Re-run with --confirm to delete.");
    return;
  }

  const chunkSize = 400;
  for (let index = 0; index < docs.length; index += chunkSize) {
    const chunk = docs.slice(index, index + chunkSize);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    console.log(`Deleted ${Math.min(index + chunk.length, docs.length)} / ${docs.length}`);
  }

  console.log(`Deleted all gear docs for team ${teamCode}.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
