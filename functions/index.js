const {
  onDocumentUpdated,
  onDocumentCreated,
} = require("firebase-functions/v2/firestore");
const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {SecretManagerServiceClient} = require("@google-cloud/secret-manager");
const {GoogleAuth} = require("google-auth-library");
const sgMail = require("@sendgrid/mail");
const crypto = require("crypto");
const Busboy = require("busboy");

let adminInitialized = false;

/**
 * Ensure Firebase Admin is initialized with service account credentials.
 */
async function ensureAdminInitialized() {
  if (adminInitialized) return;

  try {
    const saJson = await getSecret(
        "projects/prodconnect-1ea3a/secrets/firebase-sa-key/versions/latest",
    );
    const sa = JSON.parse(saJson);

    admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: "prodconnect-1ea3a",
      storageBucket: "prodconnect-1ea3a.firebasestorage.app",
    });

    // Probe token acquisition so we know auth is working
    const auth = new GoogleAuth({
      credentials: sa,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const client = await auth.getClient();
    const tokenInfo = await client.getAccessToken();
    const tokenValue = (tokenInfo &&
      (tokenInfo.access_token || tokenInfo.token)) || "";
    const tokenPreview = tokenValue.slice(0, 20);
    console.log(
        "Admin initialized with service account; token acquired (preview):",
        tokenPreview,
    );

    adminInitialized = true;
    return;
  } catch (err) {
    console.error("Failed to initialize admin:", err.message);
    throw err;
  }
}

/**
 * Retrieve a secret from Secret Manager.
 * @param {string} name Full resource name of the secret version.
 * @return {Promise<string>} Secret payload as UTF-8 string.
 */
async function getSecret(name) {
  const client = new SecretManagerServiceClient();
  const [version] = await client.accessSecretVersion({name});
  return version.payload.data.toString("utf8");
}

/**
 * Apply CORS headers for the public ticket endpoint.
 * @param {!Object} response Express response object.
 */
function setCorsHeaders(response) {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type");
}

/**
 * Normalize a value into a trimmed string.
 * @param {*} value Value to normalize.
 * @return {string} Trimmed string or empty string.
 */
function trimString(value) {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * Normalize a team code.
 * @param {*} value Input team code.
 * @return {string} Uppercased team code.
 */
function normalizeTeamCode(value) {
  return trimString(value).toUpperCase();
}

/**
 * Determine the caller IP address.
 * @param {!Object} request Express request object.
 * @return {string} Best-effort caller address.
 */
function clientAddress(request) {
  const forwardedFor = trimString(request.headers["x-forwarded-for"]);
  if (forwardedFor) {
    return forwardedFor.split(",")[0].trim();
  }
  return trimString(request.ip);
}

/**
 * Build a stable document ID for rate limiting.
 * @param {string} teamCode Normalized team code.
 * @param {string} address Caller address.
 * @return {string} Hashed document ID.
 */
function rateLimitDocumentID(teamCode, address) {
  return crypto.createHash("sha256")
      .update(`${teamCode}:${address}`)
      .digest("hex");
}

/**
 * Enforce a small cooldown for public ticket submissions.
 * @param {string} teamCode Normalized team code.
 * @param {string} address Caller address.
 * @return {Promise<void>}
 */
async function enforceExternalTicketRateLimit(teamCode, address) {
  if (!address) return;

  const db = admin.firestore();
  const docID = rateLimitDocumentID(teamCode, address);
  const docRef = db.collection("externalTicketRateLimits").doc(docID);
  const now = Date.now();
  const cooldownMs = 30 * 1000;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);
    const lastSubmittedAt = snapshot.exists ?
      (snapshot.data().lastSubmittedAtMs || 0) : 0;

    if (now - lastSubmittedAt < cooldownMs) {
      throw new Error(
          "Please wait a moment before submitting another ticket.",
      );
    }

    transaction.set(docRef, {
      teamCode,
      lastSubmittedAtMs: now,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

/**
 * Get the default storage bucket.
 * @return {*} Default storage bucket.
 */
function storageBucket() {
  return admin.storage().bucket(
      admin.app().options.storageBucket ||
      "prodconnect-1ea3a.firebasestorage.app",
  );
}

/**
 * Validate an external ticket form configuration.
 * @param {string} teamCode Normalized team code.
 * @param {string} accessKey Public form access key.
 * @return {Promise<!Object>} Stored integration settings.
 */
async function validateExternalTicketForm(teamCode, accessKey) {
  const db = admin.firestore();
  const settingsRef = db.collection("teams")
      .doc(teamCode)
      .collection("integrations")
      .doc("externalTicketForm");
  const settingsSnapshot = await settingsRef.get();

  if (!settingsSnapshot.exists) {
    throw new Error("This external ticket form is not configured.");
  }

  const settings = settingsSnapshot.data() || {};
  if (settings.isEnabled !== true) {
    throw new Error("This external ticket form is currently disabled.");
  }

  if (trimString(settings.accessKey) !== accessKey) {
    throw new Error("This external ticket form link is no longer valid.");
  }

  return settings;
}

/**
 * Build a Firebase Storage download URL from a tokenized object path.
 * @param {string} bucketName Storage bucket name.
 * @param {string} objectPath Storage object path.
 * @param {string} downloadToken Firebase download token.
 * @return {string} Public download URL.
 */
function storageDownloadURL(bucketName, objectPath, downloadToken) {
  const encodedPath = encodeURIComponent(objectPath);
  const encodedToken = encodeURIComponent(downloadToken);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media&token=${encodedToken}`;
}

/**
 * Map a MIME type into a ticket attachment kind.
 * @param {string} contentType MIME type.
 * @return {string} Attachment kind.
 */
function attachmentKindForContentType(contentType) {
  if ((contentType || "").startsWith("image/")) {
    return "image";
  }
  if ((contentType || "").startsWith("video/")) {
    return "video";
  }
  return "document";
}

exports.sendChatNotification = onDocumentUpdated(
    {
      document: "channels/{channelId}",
    },
    async (event) => {
      try {
        await ensureAdminInitialized();
        const before = event.data.before.data();
        const after = event.data.after.data();

        // Only proceed if a new message was added
        if (!after.messages ||
        after.messages.length <= (before.messages || []).length) {
          return;
        }

        const newMessage = after.messages[after.messages.length - 1];
        const channelName = after.name || "Chat";
        const teamCode = after.teamCode || "";
        const channelId = event.params.channelId;
        const channelKind = after.kind || "group";
        const participantEmails = Array.isArray(after.participantEmails) ?
          after.participantEmails : [];

        console.log("Processing message for channel:", channelId);
        console.log("Full message object:", JSON.stringify(newMessage));

        // Get users in the same team
        const usersSnapshot = await admin
            .firestore()
            .collection("users")
            .where("teamCode", "==", teamCode)
            .get();

        // Get sender email (try both author and senderName fields)
        const senderEmail = newMessage.author || newMessage.senderEmail;
        console.log("Sender email:", senderEmail);
        const senderEmailLower = (senderEmail || "").toLowerCase();
        const participantEmailSet = new Set(participantEmails
            .map((email) => (email || "").toLowerCase())
            .filter(Boolean));

        // Get external user IDs (email addresses), excluding sender.
        // Direct messages should only notify the users in that DM.
        const externalUserIds = usersSnapshot.docs
            .map((doc) => doc.data().email)
            .filter((email) => {
              if (!email) return false;
              const normalizedEmail = email.toLowerCase();
              if (normalizedEmail === senderEmailLower) return false;
              if (channelKind === "direct" && participantEmailSet.size > 0) {
                return participantEmailSet.has(normalizedEmail);
              }
              return true;
            });

        console.log("Message sender:", senderEmail,
            "(lowercase:", senderEmailLower, ")");
        const allEmails = usersSnapshot.docs
            .map((doc) => doc.data().email);
        console.log("All team emails:", allEmails);
        console.log("Filtered recipients:", externalUserIds);

        if (externalUserIds.length === 0) {
          console.log("No other users to notify");
          return;
        }

        // Resolve sender display name
        const senderSnapshot = await admin
            .firestore()
            .collection("users")
            .where("email", "==", senderEmail)
            .limit(1)
            .get();

        const senderName = senderSnapshot.empty ?
        (senderEmail || "").split("@")[0] :
        (senderSnapshot.docs[0].data().displayName ||
            senderEmail);

        const msgCount = externalUserIds.length;
        console.log("Sending to", msgCount, "users via OneSignal");

        // Send OneSignal notification
        const oneSignalAppId = "6495d27c-74bd-4f3d-9843-9d59aa4d0c7b";
        const part1 = "projects/prodconnect-1ea3a/secrets/";
        const part2 = "onesignal-api-key/versions/latest";
        const secretName = part1 + part2;
        const oneSignalApiKey = await getSecret(secretName);

        const notificationUrl = "https://onesignal.com/api/v1/notifications";
        const response = await fetch(notificationUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Basic ${oneSignalApiKey}`,
          },
          body: JSON.stringify({
            app_id: oneSignalAppId,
            include_aliases: {
              external_id: externalUserIds,
            },
            include_external_user_ids: externalUserIds,
            target_channel: "push",
            headings: {en: channelName},
            contents: {en: `${senderName}: ${newMessage.text || ""}`},
            data: {
              channelId,
              channelName,
            },
            ios_interruption_level: "active",
            // iOS notification settings
            ios_badgeType: "Increase",
            ios_badgeCount: 1,
            big_picture: null,
            large_icon: null,
            // Make notification more prominent
            priority: 10,
            apns_alert: {
              title: channelName,
              body: `${senderName}: ${newMessage.text || ""}`,
            },
          }),
        });

        const result = await response.json();
        console.log("OneSignal response:", JSON.stringify(result));

        if (result.errors) {
          console.error("OneSignal errors:", result.errors);
        } else {
          const recipients = result.recipients || 0;
          console.log("Successfully sent to", recipients, "recipients");
        }
      } catch (err) {
        console.error("Error in sendChatNotification:", err.message);
        console.error("Stack:", err.stack);
      }
    },
);

exports.sendInviteEmail = onDocumentCreated(
    {
      document: "invites/{inviteId}",
    },
    async (event) => {
      try {
        await ensureAdminInitialized();
        const data = event.data.data();

        const inviteEmail = data.email;
        const teamCode = data.teamCode;
        const displayName = data.displayName || "";
        const invitedBy = data.invitedBy || "";

        if (!inviteEmail || !teamCode) {
          console.log("Invite missing email or team code.");
          return;
        }

        const sendgridSecret =
          "projects/prodconnect-1ea3a/secrets/sendgrid-api-key/versions/latest";
        const sendgridApiKey = await getSecret(sendgridSecret);
        sgMail.setApiKey(sendgridApiKey);

        const fromEmail = "prodconnectapp@gmail.com";
        const subject = "You're invited to ProdConnect";
        const greeting = displayName ? `Hi ${displayName},` : "Hi there,";
        const inviterLine = invitedBy ? `Invited by: ${invitedBy}` : "";
        const bodyLines = [
          greeting,
          "",
          "You've been invited to join a ProdConnect team.",
          `Team code: ${teamCode}`,
          inviterLine,
          "",
          "Open the app and sign up with this team code.",
          "",
          "If you already have an account, join the team in",
          "Account > Join Team.",
          "",
          "Thanks,",
          "ProdConnect",
        ].filter(Boolean);

        const msg = {
          to: inviteEmail,
          from: fromEmail,
          subject,
          text: bodyLines.join("\n"),
        };

        await sgMail.send(msg);

        await admin.firestore().collection("invites")
            .doc(event.params.inviteId)
            .set({
              status: "sent",
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
      } catch (err) {
        console.error("Invite email send failed:", err.message);
        await admin.firestore().collection("invites")
            .doc(event.params.inviteId)
            .set({
              status: "error",
              errorMessage: err.message,
              errorAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
      }
    },
);

exports.getExternalTicketFormConfig = onRequest(async (request, response) => {
  setCorsHeaders(response);

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "GET") {
    response.status(405).json({error: "Method not allowed."});
    return;
  }

  try {
    await ensureAdminInitialized();
    const teamCode = normalizeTeamCode(request.query.teamCode);
    const accessKey = trimString(request.query.accessKey);

    if (!teamCode || !accessKey) {
      response.status(400).json({error: "Missing form credentials."});
      return;
    }

    await validateExternalTicketForm(teamCode, accessKey);

    const db = admin.firestore();
    const [teamSnapshot, locationsSnapshot, roomsSnapshot] = await Promise.all([
      db.collection("teams").doc(teamCode).get(),
      db.collection("teams").doc(teamCode).collection("locations").get(),
      db.collection("teams").doc(teamCode).collection("rooms").get(),
    ]);

    response.status(200).json({
      ok: true,
      organizationName: trimString(teamSnapshot.data()?.organizationName),
      locations: locationsSnapshot.docs.map((doc) => doc.id).sort(),
      rooms: roomsSnapshot.docs.map((doc) => doc.id).sort(),
    });
  } catch (error) {
    console.error("External ticket config failed:", error.message);
    response.status(400).json({
      error: error.message || "Unable to load ticket form options.",
    });
  }
});

exports.uploadExternalTicketAttachment = onRequest(
    async (request, response) => {
      setCorsHeaders(response);

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).json({error: "Method not allowed."});
        return;
      }

      try {
        await ensureAdminInitialized();

        const fields = {};
        let fileBuffer = Buffer.alloc(0);
        let uploadedFileName = "";
        let uploadedContentType = "application/octet-stream";
        let fileFound = false;
        let fileTooLarge = false;

        await new Promise((resolve, reject) => {
          const busboy = new Busboy({
            headers: request.headers,
            limits: {
              files: 1,
              fileSize: 15 * 1024 * 1024,
            },
          });

          busboy.on("field", (name, value) => {
            fields[name] = value;
          });

          busboy.on("file", (name, file, info) => {
            if (name !== "attachment") {
              file.resume();
              return;
            }

            fileFound = true;
            uploadedFileName = trimString(info.filename) || "attachment";
            uploadedContentType = trimString(info.mimeType) ||
          "application/octet-stream";

            const chunks = [];
            file.on("data", (chunk) => chunks.push(chunk));
            file.on("limit", () => {
              fileTooLarge = true;
            });
            file.on("end", () => {
              fileBuffer = Buffer.concat(chunks);
            });
          });

          busboy.on("finish", resolve);
          busboy.on("error", reject);
          busboy.end(request.rawBody);
        });

        const teamCode = normalizeTeamCode(fields.teamCode);
        const accessKey = trimString(fields.accessKey);
        if (!teamCode || !accessKey) {
          response.status(400).json({error: "Missing form credentials."});
          return;
        }

        await validateExternalTicketForm(teamCode, accessKey);

        if (!fileFound || !fileBuffer.length) {
          response.status(400).json({error: "Choose a file to upload."});
          return;
        }

        if (fileTooLarge) {
          response.status(400).json({
            error: "File is too large. Limit is 15 MB.",
          });
          return;
        }

        const safeFileName = uploadedFileName
            .replace(/[^\w.\- ]+/g, "_")
            .trim()
            .slice(0, 120) || "attachment";
        const objectPath = "external-ticket-uploads/" +
          `${teamCode}/${Date.now()}-${crypto.randomUUID()}-${safeFileName}`;
        const downloadToken = crypto.randomUUID();
        const bucket = storageBucket();
        const file = bucket.file(objectPath);

        await file.save(fileBuffer, {
          metadata: {
            contentType: uploadedContentType,
            metadata: {
              firebaseStorageDownloadTokens: downloadToken,
              teamCode,
              source: "externalTicketForm",
            },
          },
          resumable: false,
        });

        response.status(200).json({
          ok: true,
          attachmentURL: storageDownloadURL(
              bucket.name,
              objectPath,
              downloadToken,
          ),
          attachmentName: safeFileName,
          attachmentKind: attachmentKindForContentType(uploadedContentType),
        });
      } catch (error) {
        console.error("External ticket upload failed:", error.message);
        response.status(400).json({
          error: error.message || "Attachment upload failed.",
        });
      }
    },
);

exports.submitExternalTicket = onRequest(async (request, response) => {
  setCorsHeaders(response);

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).json({error: "Method not allowed."});
    return;
  }

  try {
    await ensureAdminInitialized();

    const teamCode = normalizeTeamCode(request.body.teamCode);
    const accessKey = trimString(request.body.accessKey);
    const requesterName = trimString(request.body.requesterName);
    const requesterEmail = trimString(request.body.requesterEmail)
        .toLowerCase();
    const title = trimString(request.body.title);
    const detail = trimString(request.body.detail);
    const campus = trimString(request.body.campus);
    const room = trimString(request.body.room);
    const attachmentURL = trimString(request.body.attachmentURL);
    const attachmentName = trimString(request.body.attachmentName);
    const attachmentKind = trimString(request.body.attachmentKind);
    const honeypotValue = trimString(request.body.company);

    if (honeypotValue) {
      response.status(200).json({ok: true});
      return;
    }

    if (!teamCode || !accessKey) {
      response.status(400).json({error: "Missing form credentials."});
      return;
    }

    if (!requesterName || !requesterEmail || !title || !detail) {
      response.status(400).json({
        error: "Name, email, title, and description are required.",
      });
      return;
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(requesterEmail)) {
      response.status(400).json({error: "Enter a valid email address."});
      return;
    }

    const db = admin.firestore();
    await validateExternalTicketForm(teamCode, accessKey);

    await enforceExternalTicketRateLimit(teamCode, clientAddress(request));

    const now = admin.firestore.Timestamp.now();
    const ticketRef = db.collection("tickets").doc();
    const activityEntry = {
      id: crypto.randomUUID(),
      message: "Ticket submitted from external form",
      createdAt: now,
      author: requesterName,
    };

    const ticketData = {
      id: ticketRef.id,
      title,
      detail,
      teamCode,
      campus,
      room,
      status: "New",
      createdBy: requesterEmail,
      createdByUserID: null,
      assignedAgentID: null,
      assignedAgentName: null,
      linkedGearID: null,
      linkedGearName: null,
      dueDate: null,
      createdAt: now,
      updatedAt: now,
      resolvedAt: null,
      lastUpdatedBy: requesterName,
      attachmentURL: attachmentURL || null,
      attachmentName: attachmentName || null,
      attachmentKind: attachmentKind || null,
      activity: [activityEntry],
      externalSubmission: true,
      externalRequesterName: requesterName,
      externalRequesterEmail: requesterEmail,
      source: "externalTicketForm",
    };

    await ticketRef.set(ticketData, {merge: true});

    if (campus) {
      await db.collection("teams")
          .doc(teamCode)
          .collection("locations")
          .doc(campus)
          .set({}, {merge: true});
    }

    if (room) {
      await db.collection("teams")
          .doc(teamCode)
          .collection("rooms")
          .doc(room)
          .set({}, {merge: true});
    }

    response.status(200).json({
      ok: true,
      ticketID: ticketRef.id,
    });
  } catch (error) {
    console.error("External ticket submission failed:", error.message);
    response.status(500).json({
      error: error.message || "Ticket submission failed.",
    });
  }
});
