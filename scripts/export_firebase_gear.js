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

function formatDate(value) {
  if (!value) return "";
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  return String(value);
}

async function main() {
  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id || "prodconnect-1ea3a";

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  const db = admin.firestore();
  const snapshot = await db.collection("gear").get();

  const header = [
    "gear_id",
    "name",
    "category",
    "status",
    "team_code",
    "campus",
    "room",
    "serial_number",
    "asset_id",
    "purchase_date",
    "purchased_from",
    "cost",
    "install_date",
    "maintenance_issue",
    "maintenance_cost",
    "maintenance_repair_date",
    "maintenance_notes",
    "image_url",
    "created_by",
    "active_ticket_count",
    "active_ticket_ids",
    "ticket_history_count",
  ];

  const rows = snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    const activeTicketIDs = Array.isArray(data.activeTicketIDs) ? data.activeTicketIDs : [];
    const ticketHistory = Array.isArray(data.ticketHistory) ? data.ticketHistory : [];

    return [
      doc.id,
      data.name || "",
      data.category || "",
      data.status || "",
      data.teamCode || "",
      data.campus || "",
      data.location || "",
      data.serialNumber || "",
      data.assetId || "",
      formatDate(data.purchaseDate),
      data.purchasedFrom || "",
      data.cost ?? "",
      formatDate(data.installDate),
      data.maintenanceIssue || "",
      data.maintenanceCost ?? "",
      formatDate(data.maintenanceRepairDate),
      data.maintenanceNotes || "",
      data.imageURL || "",
      data.createdBy || "",
      activeTicketIDs.length,
      activeTicketIDs.join(" | "),
      ticketHistory.length,
    ];
  });

  rows.sort((lhs, rhs) => {
    const leftTeam = String(lhs[4]).toLowerCase();
    const rightTeam = String(rhs[4]).toLowerCase();
    if (leftTeam !== rightTeam) return leftTeam.localeCompare(rightTeam);

    const leftName = String(lhs[1]).toLowerCase();
    const rightName = String(rhs[1]).toLowerCase();
    return leftName.localeCompare(rightName);
  });

  const outputDir = path.resolve(process.cwd(), "exports");
  fs.mkdirSync(outputDir, {recursive: true});

  const stamp = new Date().toISOString().replace(/[:]/g, "-");
  const outputPath = path.join(outputDir, `firebase-gear-${stamp}.csv`);
  const csv = "\uFEFF" + [header, ...rows].map((row) => row.map(csvEscape).join(",")).join("\n");

  fs.writeFileSync(outputPath, csv, "utf8");

  console.log(`Exported ${rows.length} gear items to ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
