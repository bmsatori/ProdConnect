const {onDocumentUpdated, onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const {SecretManagerServiceClient} = require("@google-cloud/secret-manager");
const {GoogleAuth} = require("google-auth-library");
const sgMail = require("@sendgrid/mail");

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
          "If you already have an account, join the team in Account > Join Team.",
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
