import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class ProdConnectStore: ObservableObject {
    private func pushLogin(_ externalID: String) {
        #if canImport(OneSignalFramework)
        OneSignal.login(externalID)
        #endif
    }

    private func pushLogout() {
        #if canImport(OneSignalFramework)
        OneSignal.logout()
        #endif
    }

    private var isApplicationActive: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.applicationState == .active
        #elseif canImport(AppKit)
        return NSApplication.shared.isActive
        #else
        return true
        #endif
    }

    private func deleteStorageObject(forDownloadURL urlString: String?) {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        guard raw.hasPrefix("gs://") || raw.contains("firebasestorage.googleapis.com") || raw.contains("storage.googleapis.com") else {
            return
        }
        Storage.storage().reference(forURL: raw).delete { error in
            if let error {
                print("Storage delete error:", error.localizedDescription)
            }
        }
    }

        // Add deleteGear method for compatibility
        func deleteGear(items: [GearItem]) {
            for item in items {
                deleteStorageObject(forDownloadURL: item.imageURL)
                db.collection("gear").document(item.id).delete()
            }
            gear.removeAll { g in items.contains(where: { $0.id == g.id }) }
        }
    static let shared = ProdConnectStore()

    let db = Firestore.firestore()
    private var teamMembersListener: ListenerRegistration?
    private var checklistsListener: ListenerRegistration?
    private var ideasListener: ListenerRegistration?
    private var ticketsListener: ListenerRegistration?
    private var channelsListener: ListenerRegistration?
    private var lessonsListener: ListenerRegistration?
    private var gearListener: ListenerRegistration?
    private var locationsListener: ListenerRegistration?
    private var roomsListener: ListenerRegistration?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var hasInitializedChannelsSnapshot = false
    private var activeChatChannelID: String?
    private var hasPrimedTicketAssignmentState = false
    private var ticketAssignedToCurrentUserIDs: Set<String> = []

    @Published var gear: [GearItem] = []
    @Published var patchsheet: [PatchRow] = []
    @Published var user: UserProfile?
    @Published var lessons: [TrainingLesson] = []
    @Published var checklists: [ChecklistTemplate] = []
    @Published var ideas: [IdeaCard] = []
    @Published var tickets: [SupportTicket] = []
    @Published var channels: [ChatChannel] = []
    @Published var teamMembers: [UserProfile] = []
    @Published var locations: [String] = []
    @Published var rooms: [String] = []
    var canEditPatchsheet: Bool {
        guard let user else { return false }
        return user.isAdmin || user.isOwner || user.canEditPatchsheet
    }
    var canSeeChat: Bool {
        guard let user else { return false }
        return user.hasChatAndTrainingFeatures && (user.isAdmin || user.isOwner || user.canSeeChat)
    }
    var canSeeTrainingTab: Bool {
        guard let user else { return false }
        return user.hasChatAndTrainingFeatures && (user.isAdmin || user.isOwner || user.canSeeTraining)
    }
    var canEditGear: Bool {
        guard let user else { return false }
        return user.isAdmin || user.isOwner || user.canEditGear
    }
    var canEditIdeas: Bool {
        guard let user else { return false }
        return user.isAdmin || user.isOwner || user.canEditIdeas
    }
    var canEditChecklists: Bool {
        guard let user else { return false }
        return user.isAdmin || user.isOwner || user.canEditChecklists
    }
    var teamHasTicketing: Bool {
        if user?.hasTicketingFeatures == true { return true }
        return teamMembers.contains { $0.hasTicketingFeatures }
    }
    var canUseTickets: Bool {
        guard let user else { return false }
        return teamHasTicketing && (user.isAdmin || user.isOwner || user.canSeeTickets)
    }
    var canSeeAllTickets: Bool {
        guard let user else { return false }
        if user.isAdmin || user.isOwner {
            return true
        }
        let assignedCampus = user.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assignedCampus.isEmpty {
            return false
        }
        return user.isTicketAgent
    }
    var visibleTickets: [SupportTicket] {
        guard canUseTickets, let user else { return [] }

        let scopedTickets: [SupportTicket]
        if canSeeAllTickets {
            scopedTickets = tickets
        } else {
            let assignedCampus = user.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines)
            if !assignedCampus.isEmpty {
                scopedTickets = tickets.filter {
                    $0.campus.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(assignedCampus) == .orderedSame
                }
            } else {
                let userID = user.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                scopedTickets = tickets.filter { ticket in
                    let ticketCreatorEmail = ticket.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    let ticketCreatorID = ticket.createdByUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let assignedAgentID = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return (!userID.isEmpty && (ticketCreatorID == userID || assignedAgentID == userID))
                        || (!email.isEmpty && ticketCreatorEmail == email)
                }
            }
        }

        return scopedTickets.sorted { $0.updatedAt > $1.updatedAt }
    }
    @Published var isAdmin = false
    @Published var teamCode: String?

    private init() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, authUser in
            guard let self else { return }

            guard let authUser else {
                Task { @MainActor in
                    self.user = nil
                }
                return
            }

            self.restoreSession(for: authUser)
        }

        if let authUser = Auth.auth().currentUser {
            restoreSession(for: authUser)
        }
    }

    deinit {
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    private func jsonSafeValue(_ value: Any) -> Any {
        switch value {
        case let timestamp as Timestamp:
            // Match JSONEncoder's default Date encoding (.deferredToDate).
            return timestamp.dateValue().timeIntervalSinceReferenceDate
        case let date as Date:
            return date.timeIntervalSinceReferenceDate
        case let dict as [String: Any]:
            return dict.mapValues { jsonSafeValue($0) }
        case let array as [Any]:
            return array.map { jsonSafeValue($0) }
        default:
            return value
        }
    }

    private func decodeDocument<T: Decodable>(_ data: [String: Any], as type: T.Type) -> T? {
        do {
            let safeData = jsonSafeValue(data)
            guard JSONSerialization.isValidJSONObject(safeData) else { return nil }
            let json = try JSONSerialization.data(withJSONObject: safeData, options: [])
            return try JSONDecoder().decode(type, from: json)
        } catch {
            return nil
        }
    }

    private func save<T: Encodable>(_ item: T, collection: String, id: String?) {
        let docID = id ?? UUID().uuidString
        do {
            let data = try JSONEncoder().encode(item)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = json as? [String: Any] else { return }
            db.collection(collection).document(docID).setData(dict, merge: true)
        } catch {
            print("Save error (\(collection)):", error)
        }
    }

    private func teamCodeVariants(for rawCode: String) -> [String] {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var variants: [String] = [trimmed]
        let upper = trimmed.uppercased()
        let lower = trimmed.lowercased()
        if !variants.contains(upper) { variants.append(upper) }
        if !variants.contains(lower) { variants.append(lower) }
        return variants
    }

    private func queryForUsersTeamCode(collection: String, code: String) -> Query {
        let variants = teamCodeVariants(for: code)
        guard let first = variants.first else {
            return db.collection(collection).whereField("teamCode", isEqualTo: code)
        }
        if variants.count == 1 {
            return db.collection(collection).whereField("teamCode", isEqualTo: first)
        }
        return db.collection(collection).whereField("teamCode", in: variants)
    }

    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let authUser = result?.user else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing authenticated user."])))
                }
                return
            }

            let uid = authUser.uid
            let signedInEmail = authUser.email ?? email
            let fallbackProfile = UserProfile(
                id: uid,
                displayName: signedInEmail.components(separatedBy: "@").first ?? "User",
                email: signedInEmail
            )

            Task { @MainActor in
                self.user = fallbackProfile
                self.teamCode = fallbackProfile.teamCode
                self.isAdmin = fallbackProfile.isAdmin
                self.pushLogin(fallbackProfile.email)
                self.listenToTeamData()
                completion(.success(()))
            }

            self.db.collection("users").document(uid).getDocument { snapshot, fetchError in
                if let fetchError {
                    print("Sign-in profile fetch failed:", fetchError.localizedDescription)
                    return
                }

                let profile: UserProfile
                if let data = snapshot?.data() {
                    profile = UserProfile(
                        id: uid,
                        displayName: (data["displayName"] as? String) ?? signedInEmail.components(separatedBy: "@").first ?? "User",
                        email: (data["email"] as? String) ?? signedInEmail,
                        teamCode: data["teamCode"] as? String,
                        isAdmin: data["isAdmin"] as? Bool ?? false,
                        isOwner: data["isOwner"] as? Bool ?? false,
                        subscriptionTier: data["subscriptionTier"] as? String ?? "free",
                        assignedCampus: data["assignedCampus"] as? String ?? "",
                        canEditPatchsheet: data["canEditPatchsheet"] as? Bool ?? false,
                        canEditTraining: data["canEditTraining"] as? Bool ?? false,
                        canEditGear: data["canEditGear"] as? Bool ?? false,
                        canEditIdeas: data["canEditIdeas"] as? Bool ?? false,
                        canEditChecklists: data["canEditChecklists"] as? Bool ?? false,
                        isTicketAgent: data["isTicketAgent"] as? Bool ?? false,
                        canSeeChat: data["canSeeChat"] as? Bool ?? true,
                        canSeePatchsheet: data["canSeePatchsheet"] as? Bool ?? true,
                        canSeeTraining: data["canSeeTraining"] as? Bool ?? true,
                        canSeeGear: data["canSeeGear"] as? Bool ?? true,
                        canSeeIdeas: data["canSeeIdeas"] as? Bool ?? true,
                        canSeeChecklists: data["canSeeChecklists"] as? Bool ?? true,
                        canSeeTickets: data["canSeeTickets"] as? Bool ?? true
                    )
                } else {
                    // Backfill a profile doc for existing auth users missing Firestore user data.
                    profile = fallbackProfile
                    self.save(profile, collection: "users", id: uid)
                }

                Task { @MainActor in
                    self.user = profile
                    self.teamCode = profile.teamCode
                    self.isAdmin = profile.isAdmin
                    self.listenToTeamData()
                }
            }
        }
    }

    func signUp(email: String, password: String, teamCode: String? = nil, isAdmin: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error {
                completion(.failure(error))
                return
            }

            let uid = result?.user.uid ?? UUID().uuidString
            let normalizedTeamCode = teamCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTeamCode = normalizedTeamCode?.isEmpty == false
            let subscriptionTier = (hasTeamCode || isAdmin) ? "basic" : "free"
            let canUseChatAndTraining = subscriptionTier != "free"
            let profile = UserProfile(
                id: uid,
                displayName: email.components(separatedBy: "@").first ?? "User",
                email: email,
                teamCode: normalizedTeamCode,
                isAdmin: isAdmin,
                subscriptionTier: subscriptionTier,
                canEditPatchsheet: subscriptionTier != "free",
                canEditTraining: subscriptionTier != "free",
                canEditGear: subscriptionTier != "free",
                canEditIdeas: subscriptionTier != "free",
                canEditChecklists: subscriptionTier != "free",
                canSeeChat: canUseChatAndTraining,
                canSeeTraining: canUseChatAndTraining,
                canSeeTickets: false
            )
            self.user = profile
            self.teamCode = normalizedTeamCode
            self.isAdmin = isAdmin
            self.save(profile, collection: "users", id: uid)
            self.pushLogin(email)
            self.listenToTeamData()
            completion(.success(()))
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        pushLogout()
        KeychainHelper.shared.delete(for: "prodconnect_email")
        KeychainHelper.shared.delete(for: "prodconnect_password")
        teamMembersListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
        ticketsListener?.remove()
        channelsListener?.remove()
        lessonsListener?.remove()
        gearListener?.remove()
        locationsListener?.remove()
        roomsListener?.remove()
        user = nil
        gear = []
        patchsheet = []
        lessons = []
        checklists = []
        ideas = []
        tickets = []
        channels = []
        teamMembers = []
        locations = []
        rooms = []
        teamCode = nil
        isAdmin = false
        activeChatChannelID = nil
        hasInitializedChannelsSnapshot = false
        hasPrimedTicketAssignmentState = false
        ticketAssignedToCurrentUserIDs = []
    }

    private func restoreSession(for authUser: FirebaseAuth.User) {
        let fallbackProfile = UserProfile(
            id: authUser.uid,
            displayName: authUser.email?.components(separatedBy: "@").first ?? "User",
            email: authUser.email ?? ""
        )

        Task { @MainActor in
            self.user = fallbackProfile
            self.teamCode = fallbackProfile.teamCode
            self.isAdmin = fallbackProfile.isAdmin
            if !fallbackProfile.email.isEmpty {
                self.pushLogin(fallbackProfile.email)
            }
            self.listenToTeamData()
        }

        db.collection("users").document(authUser.uid).getDocument { snapshot, fetchError in
            if let fetchError {
                print("Session restore profile fetch failed:", fetchError.localizedDescription)
                return
            }

            let profile: UserProfile
            if let data = snapshot?.data() {
                profile = UserProfile(
                    id: authUser.uid,
                    displayName: (data["displayName"] as? String) ?? authUser.email?.components(separatedBy: "@").first ?? "User",
                    email: (data["email"] as? String) ?? authUser.email ?? "",
                    teamCode: data["teamCode"] as? String,
                    isAdmin: data["isAdmin"] as? Bool ?? false,
                    isOwner: data["isOwner"] as? Bool ?? false,
                    subscriptionTier: data["subscriptionTier"] as? String ?? "free",
                    assignedCampus: data["assignedCampus"] as? String ?? "",
                    canEditPatchsheet: data["canEditPatchsheet"] as? Bool ?? false,
                    canEditTraining: data["canEditTraining"] as? Bool ?? false,
                    canEditGear: data["canEditGear"] as? Bool ?? false,
                    canEditIdeas: data["canEditIdeas"] as? Bool ?? false,
                    canEditChecklists: data["canEditChecklists"] as? Bool ?? false,
                    isTicketAgent: data["isTicketAgent"] as? Bool ?? false,
                    canSeeChat: data["canSeeChat"] as? Bool ?? true,
                    canSeePatchsheet: data["canSeePatchsheet"] as? Bool ?? true,
                    canSeeTraining: data["canSeeTraining"] as? Bool ?? true,
                    canSeeGear: data["canSeeGear"] as? Bool ?? true,
                    canSeeIdeas: data["canSeeIdeas"] as? Bool ?? true,
                    canSeeChecklists: data["canSeeChecklists"] as? Bool ?? true,
                    canSeeTickets: data["canSeeTickets"] as? Bool ?? true
                )
            } else {
                profile = fallbackProfile
                self.save(profile, collection: "users", id: authUser.uid)
            }

            Task { @MainActor in
                self.user = profile
                self.teamCode = profile.teamCode
                self.isAdmin = profile.isAdmin
                if !profile.email.isEmpty {
                    self.pushLogin(profile.email)
                }
                self.listenToTeamData()
            }
        }
    }

    func listenToTeamData() {
        teamMembersListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
        ticketsListener?.remove()
        channelsListener?.remove()
        lessonsListener?.remove()
        gearListener?.remove()
        locationsListener?.remove()
        roomsListener?.remove()
        hasInitializedChannelsSnapshot = false

        guard let code = teamCode, !code.isEmpty else {
            if let user {
                teamMembers = [user]
            }
            locations = []
            rooms = []
            tickets = []
            hasPrimedTicketAssignmentState = false
            ticketAssignedToCurrentUserIDs = []
            return
        }

        teamMembersListener = queryForUsersTeamCode(collection: "users", code: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let members: [UserProfile] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: UserProfile.self)
                }
                DispatchQueue.main.async {
                    self.teamMembers = members
                }
            }

        checklistsListener = db.collection("checklists")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [ChecklistTemplate] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: ChecklistTemplate.self)
                }
                DispatchQueue.main.async {
                    self.checklists = values
                }
            }

        ideasListener = db.collection("ideas")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [IdeaCard] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: IdeaCard.self)
                }
                DispatchQueue.main.async {
                    self.ideas = values
                }
            }

        ticketsListener = queryForUsersTeamCode(collection: "tickets", code: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [SupportTicket] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: SupportTicket.self)
                }
                DispatchQueue.main.async {
                    self.processTicketAssignmentNotifications(with: values)
                    self.tickets = values
                    self.refreshGearTicketState()
                }
            }

        channelsListener = db.collection("channels")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [ChatChannel] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: ChatChannel.self)
                }
                DispatchQueue.main.async {
                    let sorted = values.sorted { $0.position < $1.position }
                    self.processIncomingChatNotifications(previous: self.channels, latest: sorted)
                    self.channels = sorted
                }
            }

        lessonsListener = db.collection("lessons")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [TrainingLesson] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: TrainingLesson.self)
                }
                DispatchQueue.main.async {
                    self.lessons = values
                }
            }

        gearListener = db.collection("gear")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [GearItem] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: GearItem.self)
                }
                DispatchQueue.main.async {
                    self.gear = values
                }
            }

        locationsListener = db.collection("teams")
            .document(code)
            .collection("locations")
            .addSnapshotListener { snapshot, _ in
                let values = (snapshot?.documents ?? []).map(\.documentID).sorted()
                DispatchQueue.main.async {
                    self.locations = values
                }
            }

        roomsListener = db.collection("teams")
            .document(code)
            .collection("rooms")
            .addSnapshotListener { snapshot, _ in
                let values = (snapshot?.documents ?? []).map(\.documentID).sorted()
                DispatchQueue.main.async {
                    self.rooms = values
                }
            }
    }

    func setActiveChatChannel(_ channelID: String?) {
        activeChatChannelID = channelID
    }

    private func processIncomingChatNotifications(previous: [ChatChannel], latest: [ChatChannel]) {
        guard hasInitializedChannelsSnapshot else {
            hasInitializedChannelsSnapshot = true
            return
        }
        guard let currentEmail = user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !currentEmail.isEmpty else { return }

        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for channel in latest {
            guard let latestMessage = channel.messages.last else { continue }
            if latestMessage.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentEmail {
                continue
            }

            if channel.id == activeChatChannelID, isApplicationActive {
                continue
            }

            if channel.kind == .direct {
                let participants = channel.participantEmails.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                if !participants.isEmpty && !participants.contains(currentEmail) {
                    continue
                }
            } else if !isAdmin {
                if channel.isHidden || channel.hiddenUserEmails.contains(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentEmail
                }) {
                    continue
                }
            }

            let previousMessage = previousByID[channel.id]?.messages.last
            if let previousMessage, previousMessage.id == latestMessage.id {
                continue
            }

            #if canImport(OneSignalFramework)
            continue
            #else
            scheduleLocalChatNotification(for: latestMessage, channelName: channel.name, channelID: channel.id)
            #endif
        }
    }

    private func scheduleLocalChatNotification(for message: ChatMessage, channelName: String, channelID: String) {
        let content = UNMutableNotificationContent()
        content.title = channelName.isEmpty ? "Chat" : channelName
        let sender = teamMembers.first(where: {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == message.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })?.displayName ?? (message.author.components(separatedBy: "@").first ?? "User")
        content.body = "\(sender): \(message.text)"
        content.sound = .default
        content.userInfo = ["channelId": channelID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "chat-\(channelID)-\(message.id)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func processTicketAssignmentNotifications(with tickets: [SupportTicket]) {
        guard let currentUser = user else { return }

        let currentUserID = currentUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentAssignedIDs = Set(
            tickets.compactMap { ticket in
                let assignedID = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !currentUserID.isEmpty, assignedID == currentUserID {
                    return ticket.id
                }

                let assignedName = ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                if !currentName.isEmpty, assignedName == currentName {
                    return ticket.id
                }

                return nil
            }
        )

        guard hasPrimedTicketAssignmentState else {
            ticketAssignedToCurrentUserIDs = currentAssignedIDs
            hasPrimedTicketAssignmentState = true
            return
        }

        let newlyAssignedIDs = currentAssignedIDs.subtracting(ticketAssignedToCurrentUserIDs)
        for ticketID in newlyAssignedIDs {
            guard let ticket = tickets.first(where: { $0.id == ticketID }) else { continue }
            scheduleTicketAssignmentNotification(for: ticket)
        }

        ticketAssignedToCurrentUserIDs = currentAssignedIDs
    }

    private func scheduleTicketAssignmentNotification(for ticket: SupportTicket) {
        let content = UNMutableNotificationContent()
        content.title = "Ticket Assigned"
        let trimmedTitle = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmedTitle.isEmpty ? "A ticket was assigned to you." : "\"\(trimmedTitle)\" was assigned to you."
        content.sound = .default
        content.userInfo = ["ticketId": ticket.id]

        let request = UNNotificationRequest(
            identifier: "ticket-assigned-\(ticket.id)-\(Int(ticket.updatedAt.timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    func listenToTeamMembers() {
        teamMembersListener?.remove()
        guard let code = teamCode, !code.isEmpty else { return }
        teamMembersListener = queryForUsersTeamCode(collection: "users", code: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let members: [UserProfile] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: UserProfile.self)
                }
                DispatchQueue.main.async {
                    self.teamMembers = members
                }
            }
    }

    func saveGear(_ item: GearItem) {
        save(item, collection: "gear", id: item.id)
        let location = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { saveLocation(location) }
        let campus = item.campus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campus.isEmpty { saveLocation(campus) }
        if let index = gear.firstIndex(where: { $0.id == item.id }) {
            gear[index] = item
        } else {
            gear.append(item)
        }
    }
    func savePatch(_ item: PatchRow) {
        save(item, collection: "patchsheet", id: item.id)
        let campus = item.campus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campus.isEmpty { saveLocation(campus) }
    }
    func saveLesson(_ item: TrainingLesson) {
        save(item, collection: "lessons", id: item.id)
        if let index = lessons.firstIndex(where: { $0.id == item.id }) {
            lessons[index] = item
        } else {
            lessons.append(item)
        }
    }
    func deleteLesson(_ item: TrainingLesson) {
        if let url = item.urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty,
           !url.lowercased().contains("youtube.com"),
           !url.lowercased().contains("youtu.be") {
            deleteStorageObject(forDownloadURL: url)
        }
        db.collection("lessons").document(item.id).delete()
        lessons.removeAll { $0.id == item.id }
    }
    func saveChecklist(_ item: ChecklistTemplate) { save(item, collection: "checklists", id: item.id) }
    func saveIdea(_ item: IdeaCard) { save(item, collection: "ideas", id: item.id) }
    func saveTicket(_ item: SupportTicket) {
        var ticket = item
        let now = Date()
        let existingTicket = tickets.first(where: { $0.id == ticket.id })
        let activeTeamCode = ensureActiveTeamCodeForTicketing() ?? ticket.teamCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        ticket.title = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.detail = ticket.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activeTeamCode.isEmpty {
            ticket.teamCode = activeTeamCode
        } else {
            print("Ticket save skipped: no active team code available")
            return
        }
        ticket.campus = ticket.campus.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.room = ticket.room.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.assignedAgentID = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.assignedAgentName = ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.linkedGearID = ticket.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.linkedGearName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if ticket.createdAt.timeIntervalSince1970 <= 0 {
            ticket.createdAt = now
        }
        ticket.updatedAt = now

        if ticket.status == .resolved {
            ticket.resolvedAt = ticket.resolvedAt ?? now
        } else {
            ticket.resolvedAt = nil
        }

        var activity = existingTicket?.activity ?? ticket.activity
        if let existingTicket {
            if existingTicket.status != ticket.status {
                activity.append(
                    TicketActivityEntry(
                        message: "Status changed to \(ticket.status.rawValue)",
                        createdAt: now,
                        author: ticket.lastUpdatedBy
                    )
                )
            }
            if existingTicket.assignedAgentID != ticket.assignedAgentID {
                let assignee = ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = assignee.isEmpty ? "Agent cleared" : "Assigned to \(assignee)"
                activity.append(
                    TicketActivityEntry(
                        message: message,
                        createdAt: now,
                        author: ticket.lastUpdatedBy
                    )
                )
            }
            if existingTicket.linkedGearID != ticket.linkedGearID {
                let gearName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = gearName.isEmpty ? "Gear link removed" : "Linked gear: \(gearName)"
                activity.append(
                    TicketActivityEntry(
                        message: message,
                        createdAt: now,
                        author: ticket.lastUpdatedBy
                    )
                )
            }
        } else {
            activity.append(
                TicketActivityEntry(
                    message: "Ticket created",
                    createdAt: now,
                    author: ticket.createdBy
                )
            )
        }
        ticket.activity = Array(activity.suffix(25))

        save(ticket, collection: "tickets", id: ticket.id)
        if !ticket.room.isEmpty {
            saveRoom(ticket.room)
        }
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
        } else {
            tickets.append(ticket)
        }
        refreshGearTicketState()
    }

    private func ensureActiveTeamCodeForTicketing() -> String? {
        let storeTeamCode = teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userTeamCode = user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let existing = [storeTeamCode, userTeamCode].first(where: { !$0.isEmpty }) {
            let normalized = existing.uppercased()
            if teamCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != normalized {
                teamCode = normalized
            }
            if user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != normalized {
                user?.teamCode = normalized
            }
            return normalized
        }

        guard var currentUser = user, currentUser.isAdmin || currentUser.isOwner else {
            return nil
        }

        let generatedCode = generateTeamCode()
        currentUser.teamCode = generatedCode
        user = currentUser
        teamCode = generatedCode

        let uid = Auth.auth().currentUser?.uid ?? currentUser.id
        db.collection("users").document(uid).setData([
            "teamCode": generatedCode,
            "isAdmin": currentUser.isAdmin,
            "isOwner": currentUser.isOwner
        ], merge: true)
        db.collection("teams").document(generatedCode).setData([
            "code": generatedCode,
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": currentUser.email,
            "isActive": true,
            "ownerId": currentUser.isOwner ? currentUser.id : (currentUser.isAdmin ? currentUser.id : ""),
            "ownerEmail": currentUser.isOwner ? currentUser.email : (currentUser.isAdmin ? currentUser.email : "")
        ], merge: true)
        listenToTeamData()
        listenToTeamMembers()
        return generatedCode
    }
    func deletePatch(_ item: PatchRow) {
        db.collection("patchsheet").document(item.id).delete()
        patchsheet.removeAll { $0.id == item.id }
    }
    func deleteChecklist(_ item: ChecklistTemplate) {
        db.collection("checklists").document(item.id).delete()
        checklists.removeAll { $0.id == item.id }
    }
    func deleteIdea(_ item: IdeaCard) {
        db.collection("ideas").document(item.id).delete()
        ideas.removeAll { $0.id == item.id }
    }
    func deleteTicket(_ item: SupportTicket) {
        db.collection("tickets").document(item.id).delete()
        tickets.removeAll { $0.id == item.id }
        refreshGearTicketState()
    }
    func saveChannel(_ item: ChatChannel) {
        save(item, collection: "channels", id: item.id)
        if let index = channels.firstIndex(where: { $0.id == item.id }) {
            channels[index] = item
        } else {
            channels.append(item)
        }
        channels.sort { $0.position < $1.position }
    }
    func deleteChannel(_ item: ChatChannel) {
        for message in item.messages {
            deleteStorageObject(forDownloadURL: message.attachmentURL)
        }
        db.collection("channels").document(item.id).delete()
        channels.removeAll { $0.id == item.id }
    }

    func updateChannelOrder(orderedIds: [String?]) {
        for (index, id) in orderedIds.enumerated() {
            guard let id else { continue }
            db.collection("channels").document(id).setData(["position": index], merge: true)
        }
    }

    func nextChannelPosition() -> Int {
        (channels.map(\.position).max() ?? -1) + 1
    }

    func generateTeamCode() -> String {
        String(UUID().uuidString.prefix(6).uppercased())
    }

    func saveLocation(_ location: String) {
        guard let code = teamCode, !code.isEmpty else { return }
        db.collection("teams").document(code).collection("locations").document(location).setData([:])
        if !locations.contains(location) { locations.append(location) }
    }

    func saveRoom(_ room: String) {
        guard let code = teamCode, !code.isEmpty else { return }
        db.collection("teams").document(code).collection("rooms").document(room).setData([:])
        if !rooms.contains(room) { rooms.append(room) }
    }

    func deleteLocation(_ location: String) {
        guard let code = teamCode, !code.isEmpty else { return }
        db.collection("teams").document(code).collection("locations").document(location).delete()
        locations.removeAll { $0 == location }
    }

    func renameLocation(_ oldLocation: String, to newLocation: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let code = teamCode, !code.isEmpty else {
            completion?(.failure(NSError(domain: "ProdConnect", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid team code."])))
            return
        }

        let oldTrimmed = oldLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTrimmed.isEmpty, !newTrimmed.isEmpty else {
            completion?(.failure(NSError(domain: "ProdConnect", code: 2, userInfo: [NSLocalizedDescriptionKey: "Campus name cannot be empty."])))
            return
        }
        guard oldTrimmed.caseInsensitiveCompare(newTrimmed) != .orderedSame else {
            completion?(.success(()))
            return
        }

        let existing = Set(locations.map { $0.lowercased() })
        if existing.contains(newTrimmed.lowercased()) {
            completion?(.failure(NSError(domain: "ProdConnect", code: 3, userInfo: [NSLocalizedDescriptionKey: "A campus with that name already exists."])))
            return
        }

        let locationsRef = db.collection("teams").document(code).collection("locations")
        let locationBatch = db.batch()
        locationBatch.setData([:], forDocument: locationsRef.document(newTrimmed))
        locationBatch.deleteDocument(locationsRef.document(oldTrimmed))

        func updateCollectionField(collection: String, field: String, done: @escaping (Error?) -> Void) {
            db.collection(collection)
                .whereField("teamCode", isEqualTo: code)
                .whereField(field, isEqualTo: oldTrimmed)
                .getDocuments { snapshot, error in
                    if let error = error {
                        done(error)
                        return
                    }

                    let docs = snapshot?.documents ?? []
                    guard !docs.isEmpty else {
                        done(nil)
                        return
                    }

                    let chunkSize = 400
                    let chunks = stride(from: 0, to: docs.count, by: chunkSize).map {
                        Array(docs[$0..<min($0 + chunkSize, docs.count)])
                    }

                    func commitChunk(_ index: Int) {
                        if index >= chunks.count {
                            done(nil)
                            return
                        }
                        let batch = self.db.batch()
                        for doc in chunks[index] {
                            batch.updateData([field: newTrimmed], forDocument: doc.reference)
                        }
                        batch.commit { chunkError in
                            if let chunkError = chunkError {
                                done(chunkError)
                            } else {
                                commitChunk(index + 1)
                            }
                        }
                    }

                    commitChunk(0)
                }
        }

        locationBatch.commit { locationError in
            if let locationError = locationError {
                completion?(.failure(locationError))
                return
            }

            let group = DispatchGroup()
            var firstError: Error?
            let tasks: [(String, String)] = [
                ("gear", "location"),
                ("gear", "campus"),
                ("patchsheet", "campus"),
                ("users", "assignedCampus"),
                ("tickets", "campus")
            ]

            for (collection, field) in tasks {
                group.enter()
                updateCollectionField(collection: collection, field: field) { err in
                    if firstError == nil, let err = err { firstError = err }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let idx = self.locations.firstIndex(where: { $0.caseInsensitiveCompare(oldTrimmed) == .orderedSame }) {
                    self.locations[idx] = newTrimmed
                    self.locations.sort()
                }
                self.gear = self.gear.map { item in
                    var updated = item
                    if updated.location.caseInsensitiveCompare(oldTrimmed) == .orderedSame { updated.location = newTrimmed }
                    if updated.campus.caseInsensitiveCompare(oldTrimmed) == .orderedSame { updated.campus = newTrimmed }
                    return updated
                }
                self.patchsheet = self.patchsheet.map { row in
                    var updated = row
                    if updated.campus.caseInsensitiveCompare(oldTrimmed) == .orderedSame { updated.campus = newTrimmed }
                    return updated
                }
                self.teamMembers = self.teamMembers.map { member in
                    var updated = member
                    if updated.assignedCampus.caseInsensitiveCompare(oldTrimmed) == .orderedSame { updated.assignedCampus = newTrimmed }
                    return updated
                }
                self.tickets = self.tickets.map { ticket in
                    var updated = ticket
                    if updated.campus.caseInsensitiveCompare(oldTrimmed) == .orderedSame { updated.campus = newTrimmed }
                    return updated
                }
                if self.user?.assignedCampus.caseInsensitiveCompare(oldTrimmed) == .orderedSame {
                    self.user?.assignedCampus = newTrimmed
                }

                if let firstError = firstError {
                    completion?(.failure(firstError))
                } else {
                    completion?(.success(()))
                }
            }
        }
    }

    func deleteRoom(_ room: String) {
        guard let code = teamCode, !code.isEmpty else { return }
        db.collection("teams").document(code).collection("rooms").document(room).delete()
        rooms.removeAll { $0 == room }
    }

    func deleteAllGear() {
        gear.forEach { item in
            deleteStorageObject(forDownloadURL: item.imageURL)
            db.collection("gear").document(item.id).delete()
        }
        gear = []
    }

    func deletePatchesByCategory(_ category: String) {
        let toDelete = patchsheet.filter { $0.category == category }
        toDelete.forEach { item in
            db.collection("patchsheet").document(item.id).delete()
        }
        patchsheet.removeAll { $0.category == category }
    }

    func replaceAllGear(_ items: [GearItem]) {
        gear = items
        items.forEach(saveGear)
    }

    func replaceAllPatch(_ rows: [PatchRow]) {
        patchsheet = rows
        rows.forEach(savePatch)
    }

    private func refreshGearTicketState() {
        guard !gear.isEmpty else { return }

        var updatedGear = gear
        var hasChanges = false
        for index in updatedGear.indices {
            var item = updatedGear[index]
            let linkedTickets = tickets
                .filter { $0.linkedGearID == item.id }
                .sorted { $0.updatedAt > $1.updatedAt }

            let newActiveIDs = linkedTickets
                .filter { $0.status != .resolved }
                .map(\.id)

            let newHistory = linkedTickets.map {
                GearTicketHistoryEntry(
                    ticketID: $0.id,
                    ticketTitle: $0.title,
                    status: $0.status,
                    campus: $0.campus,
                    room: $0.room,
                    updatedAt: $0.updatedAt,
                    resolvedAt: $0.resolvedAt
                )
            }

            if item.activeTicketIDs != newActiveIDs || item.ticketHistory != newHistory {
                item.activeTicketIDs = newActiveIDs
                item.ticketHistory = newHistory
                updatedGear[index] = item
                save(item, collection: "gear", id: item.id)
                hasChanges = true
            }
        }

        if hasChanges {
            gear = updatedGear
        }
    }
}
