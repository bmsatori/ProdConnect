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

function csvEscape(value) {
  const stringValue = value == null ? "" : String(value);
  return `"${stringValue.replace(/"/g, "\"\"")}"`;
}

async function listAllAuthUsers(auth) {
  const users = [];
  let nextPageToken;

  do {
    const result = await auth.listUsers(1000, nextPageToken);
    users.push(...result.users);
    nextPageToken = result.pageToken;
  } while (nextPageToken);

  return users;
}

async function main() {
  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id || "prodconnect-1ea3a";

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  const auth = admin.auth();
  const db = admin.firestore();

  const [authUsers, firestoreSnapshot] = await Promise.all([
    listAllAuthUsers(auth),
    db.collection("users").get(),
  ]);

  const profileById = new Map();
  const profileByEmail = new Map();

  firestoreSnapshot.forEach((doc) => {
    const data = doc.data() || {};
    profileById.set(doc.id, data);

    const email = (data.email || "").trim().toLowerCase();
    if (email) {
      profileByEmail.set(email, data);
    }
  });

  const header = [
    "auth_uid",
    "auth_email",
    "auth_display_name",
    "auth_disabled",
    "auth_created_at",
    "auth_last_sign_in_at",
    "firestore_profile_exists",
    "firestore_doc_id",
    "profile_email",
    "profile_display_name",
    "team_code",
    "subscription_tier",
    "is_admin",
    "is_owner",
    "assigned_campus",
  ];

  const rows = authUsers.map((user) => {
    const normalizedEmail = (user.email || "").trim().toLowerCase();
    const profile = profileById.get(user.uid) || profileByEmail.get(normalizedEmail) || {};

    return [
      user.uid,
      user.email || "",
      user.displayName || "",
      user.disabled ? "true" : "false",
      user.metadata.creationTime || "",
      user.metadata.lastSignInTime || "",
      Object.keys(profile).length ? "true" : "false",
      profileById.has(user.uid) ? user.uid : "",
      profile.email || "",
      profile.displayName || "",
      profile.teamCode || "",
      profile.subscriptionTier || "",
      profile.isAdmin ? "true" : "false",
      profile.isOwner ? "true" : "false",
      profile.assignedCampus || "",
    ];
  });

  rows.sort((lhs, rhs) => {
    const leftEmail = lhs[1].toLowerCase();
    const rightEmail = rhs[1].toLowerCase();
    return leftEmail.localeCompare(rightEmail);
  });

  const outputDir = path.resolve(process.cwd(), "exports");
  fs.mkdirSync(outputDir, {recursive: true});

  const stamp = new Date().toISOString().replace(/[:]/g, "-");
  const outputPath = path.join(outputDir, `firebase-users-${stamp}.csv`);
  const csv = "\uFEFF" + [header, ...rows].map((row) => row.map(csvEscape).join(",")).join("\n");

  fs.writeFileSync(outputPath, csv, "utf8");

  console.log(`Exported ${rows.length} users to ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
