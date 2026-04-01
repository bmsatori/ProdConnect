import Foundation
import SwiftUI
import Combine
@preconcurrency import FirebaseFirestore
#if canImport(FirebaseFirestoreInternal)
@preconcurrency import FirebaseFirestoreInternal
#endif
import FirebaseStorage
@preconcurrency import FirebaseAuth
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
    enum GearSaveError: LocalizedError {
        case duplicateSerial(serial: String, existingName: String)

        var errorDescription: String? {
            switch self {
            case let .duplicateSerial(serial, existingName):
                if existingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "An asset with serial number \(serial) already exists."
                }
                return "Serial number \(serial) is already assigned to \(existingName)."
            }
        }
    }

    enum FreshserviceSyncMode: String, CaseIterable {
        case pull
        case push
        case bidirectional = "bidirectional"

        var title: String {
            switch self {
            case .pull: return "Pull"
            case .push: return "Push"
            case .bidirectional: return "Bi-directional"
            }
        }
    }

    struct FreshserviceIntegrationSettings: Equatable {
        var apiURL: String = ""
        var apiKey: String = ""
        var isEnabled = false
        var managedByGroup: String = ""
        var managedByGroupOptions: [String] = []
        var syncMode: FreshserviceSyncMode = .pull
    }

    struct ExternalTicketFormSettings: Equatable {
        var isEnabled = false
        var accessKey = ""
    }

    struct ChecklistNotificationNotice: Identifiable {
        let id: String
        let checklist: ChecklistTemplate
        let item: ChecklistItem
    }

    private func ensureTeamIntegrationDocumentsExist(for rawTeamCode: String) {
        let normalizedCode = rawTeamCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else { return }

        let integrations = db.collection("teams")
            .document(normalizedCode)
            .collection("integrations")

        let freshserviceRef = integrations.document("freshservice")
        freshserviceRef.getDocument { snapshot, error in
            guard error == nil else { return }
            guard snapshot?.exists != true else { return }
            freshserviceRef.setData([
                "apiURL": "",
                "apiKey": "",
                "isEnabled": false,
                "managedByGroup": "",
                "managedByGroupOptions": [],
                "syncMode": FreshserviceSyncMode.pull.rawValue
            ], merge: true)
        }

        let externalTicketRef = integrations.document("externalTicketForm")
        externalTicketRef.getDocument { snapshot, error in
            guard error == nil else { return }
            guard snapshot?.exists != true else { return }
            externalTicketRef.setData([
                "isEnabled": false,
                "accessKey": ""
            ], merge: true)
        }
    }

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

    nonisolated private func deleteStorageObject(forDownloadURL urlString: String?) {
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

    private func deleteGearDocuments(ids: [String], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let cleanedIDs = Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).filter { !$0.isEmpty }
        guard !cleanedIDs.isEmpty else {
            completion?(.success(()))
            return
        }

        let chunkSize = 400
        let chunks = stride(from: 0, to: cleanedIDs.count, by: chunkSize).map {
            Array(cleanedIDs[$0..<min($0 + chunkSize, cleanedIDs.count)])
        }

        func commitChunk(index: Int) {
            guard index < chunks.count else {
                completion?(.success(()))
                return
            }

            let batch = db.batch()
            for id in chunks[index] {
                batch.deleteDocument(db.collection("gear").document(id))
            }
            batch.commit { error in
                if let error {
                    print("Error deleting gear batch:", error.localizedDescription)
                    Task { @MainActor in
                        completion?(.failure(error))
                    }
                    return
                }
                Task { @MainActor in
                    commitChunk(index: index + 1)
                }
            }
        }

        commitChunk(index: 0)
    }

    // Add deleteGear method for compatibility
    func deleteGear(items: [GearItem], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }

        let imageURLs = items.map(\.imageURL)
        DispatchQueue.global(qos: .utility).async {
            for url in imageURLs {
                self.deleteStorageObject(forDownloadURL: url)
            }
        }

        deleteGearDocuments(ids: Array(ids)) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    self.gear.removeAll { ids.contains($0.id) }
                    completion?(.success(()))
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }
    static let shared = ProdConnectStore()

    let db = Firestore.firestore()
    private var teamDocumentListener: ListenerRegistration?
    private var teamMembersListener: ListenerRegistration?
    private var checklistsListener: ListenerRegistration?
    private var ideasListener: ListenerRegistration?
    private var ticketsListener: ListenerRegistration?
    private var channelsListener: ListenerRegistration?
    private var lessonsListener: ListenerRegistration?
    private var gearListener: ListenerRegistration?
    private var patchsheetListener: ListenerRegistration?
    private var locationsListener: ListenerRegistration?
    private var roomsListener: ListenerRegistration?
    private var freshserviceIntegrationListener: ListenerRegistration?
    private var externalTicketFormListener: ListenerRegistration?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var activeTeamListenersCode: String?
    private var hasInitializedChannelsSnapshot = false
    private var activeChatChannelID: String?
    private var hasPrimedTicketAssignmentState = false
    private var ticketAssignedToCurrentUserIDs: Set<String> = []
    private var hasPrimedTicketSubmissionState = false
    private var seenTicketIDs: Set<String> = []
    private let userDefaults = UserDefaults.standard
    private let cachedUserProfileKey = "prodconnect_cached_user_profile"
    private let cachedUserProfileIDKey = "prodconnect_cached_user_profile_id"

    @Published var gear: [GearItem] = []
    @Published var patchsheet: [PatchRow] = []
    @Published var user: UserProfile?
    @Published var lessons: [TrainingLesson] = []
    @Published var checklists: [ChecklistTemplate] = []
    @Published var ideas: [IdeaCard] = []
    @Published var tickets: [SupportTicket] = []
    @Published var channels: [ChatChannel] = []
    @Published var teamMembers: [UserProfile] = []
    @Published var organizationName: String = ""
    @Published var locations: [String] = []
    @Published var rooms: [String] = []
    @Published var freshserviceIntegration = FreshserviceIntegrationSettings()
    @Published var externalTicketFormIntegration = ExternalTicketFormSettings()
    @Published private var seenChatMessageIDsByChannel: [String: String] = [:]
    @Published private var seenTicketUpdateTokens: [String: TimeInterval] = [:]
    @Published private var seenChecklistNotificationIDs: Set<String> = []
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
        if user.isTicketAgent {
            return true
        }
        return false
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
                    if ticket.externalSubmission {
                        return true
                    }
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

    var notificationIncomingChannels: [ChatChannel] {
        guard let currentEmail = user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !currentEmail.isEmpty else { return [] }

        return channels
            .filter { channel in
                guard let last = channel.messages.last else { return false }
                let messageID = last.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !messageID.isEmpty else { return false }
                guard last.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != currentEmail else {
                    return false
                }
                return seenChatMessageIDsByChannel[channel.id] != messageID
            }
            .sorted { lhs, rhs in
                let leftDate = lhs.lastMessageAt ?? lhs.messages.last?.timestamp ?? .distantPast
                let rightDate = rhs.lastMessageAt ?? rhs.messages.last?.timestamp ?? .distantPast
                return leftDate > rightDate
            }
    }

    var notificationAssignedTickets: [SupportTicket] {
        guard let currentUser = user else { return [] }

        let currentUserID = currentUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return tickets
            .filter { ticket in
                let assignedID = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let assignedName = ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                let isAssigned = (!currentUserID.isEmpty && assignedID == currentUserID)
                    || (!currentName.isEmpty && assignedName == currentName)
                guard isAssigned else { return false }
                return seenTicketUpdateTokens[ticket.id] != ticket.updatedAt.timeIntervalSince1970
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var checklistNotificationNotices: [ChecklistNotificationNotice] {
        guard let currentUser = user else { return [] }

        return checklists
            .flatMap { checklist in
                checklist.items.compactMap { item in
                    guard item.completedAt == nil, checklistItemMentionsCurrentUser(item.text, user: currentUser) else {
                        return nil
                    }
                    let noticeID = "\(checklist.id)-\(item.id)"
                    guard !seenChecklistNotificationIDs.contains(noticeID) else { return nil }
                    return ChecklistNotificationNotice(id: noticeID, checklist: checklist, item: item)
                }
            }
    }

    var notificationBadgeCount: Int {
        notificationIncomingChannels.count + notificationAssignedTickets.count + checklistNotificationNotices.count
    }
    @Published var isAdmin = false
    @Published var teamCode: String?

    private init() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, authUser in
            guard let self else { return }

            guard let authUser else {
                Task { @MainActor in
                    self.user = nil
                    self.clearCachedUserProfile()
                    self.resetNotificationState()
                }
                return
            }

            self.restoreSession(for: authUser)
        }

        if let authUser = Auth.auth().currentUser {
            if let cachedProfile = loadCachedUserProfile(for: authUser.uid) {
                user = cachedProfile
                teamCode = cachedProfile.teamCode
                isAdmin = cachedProfile.isAdmin
            }
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

    private func cacheUserProfile(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        userDefaults.set(data, forKey: cachedUserProfileKey)
        userDefaults.set(profile.id, forKey: cachedUserProfileIDKey)
    }

    private func loadCachedUserProfile(for userID: String) -> UserProfile? {
        guard userDefaults.string(forKey: cachedUserProfileIDKey) == userID else { return nil }
        guard let data = userDefaults.data(forKey: cachedUserProfileKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private func clearCachedUserProfile() {
        userDefaults.removeObject(forKey: cachedUserProfileKey)
        userDefaults.removeObject(forKey: cachedUserProfileIDKey)
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
            let dict = try Self.makeEncodedDictionary(for: item)
            db.collection(collection).document(docID).setData(dict, merge: true)
        } catch {
            print("Save error (\(collection)):", error)
        }
    }

    nonisolated private static func makeEncodedDictionary<T: Encodable>(for item: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(item)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = json as? [String: Any] else {
            throw NSError(
                domain: "ProdConnectStore",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode Firestore document."]
            )
        }
        return dict
    }

    private func affectedGearIDs(
        previousTickets: [SupportTicket],
        latestTickets: [SupportTicket]
    ) -> Set<String> {
        let previousByID = Dictionary(uniqueKeysWithValues: previousTickets.map { ($0.id, $0) })
        let latestByID = Dictionary(uniqueKeysWithValues: latestTickets.map { ($0.id, $0) })
        let allIDs = Set(previousByID.keys).union(latestByID.keys)

        return Set<String>(allIDs.compactMap { ticketID in
            let previousGearID = previousByID[ticketID]?.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let latestGearID = latestByID[ticketID]?.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if previousGearID == latestGearID {
                return latestGearID?.isEmpty == false ? latestGearID : nil
            }
            return nil
        }.compactMap { $0 }).union(
            Set<String>(allIDs.flatMap { ticketID in
                [
                    previousByID[ticketID]?.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines),
                    latestByID[ticketID]?.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
                ].compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
            })
        )
    }

    private func encodedDictionary<T: Encodable>(for item: T) throws -> [String: Any] {
        try Self.makeEncodedDictionary(for: item)
    }

    nonisolated private static func normalizedTeamCode(_ rawCode: String?) -> String? {
        let trimmed = rawCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    nonisolated private func teamCodeVariants(for rawCode: String) -> [String] {
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
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return db.collection(collection).whereField("teamCode", isEqualTo: normalizedCode)
    }

    nonisolated private func invalidTeamCodeError() -> NSError {
        NSError(
            domain: "InvalidTeamCode",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Team code does not exist."]
        )
    }

    private func resolveSignUpTeamCode(_ rawCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.uppercased()
        let variants = teamCodeVariants(for: trimmed)
        let db = self.db
        guard normalized.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil else {
            completion(.failure(invalidTeamCodeError()))
            return
        }

        db.collection("teams").document(normalized).getDocument { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let snapshot, snapshot.exists, snapshot.data()?["isActive"] as? Bool != false {
                let resolvedCode = (snapshot.data()?["code"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                completion(.success(resolvedCode?.isEmpty == false ? resolvedCode! : normalized))
                return
            }

            let query: Query
            if variants.count == 1, let only = variants.first {
                query = db.collection("teams").whereField("code", isEqualTo: only)
            } else {
                query = db.collection("teams").whereField("code", in: variants)
            }

            query.limit(to: 1).getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let doc = snapshot?.documents.first else {
                    completion(.failure(self.invalidTeamCodeError()))
                    return
                }

                if doc.data()["isActive"] as? Bool == false {
                    completion(.failure(self.invalidTeamCodeError()))
                    return
                }

                let resolvedCode = (doc.data()["code"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                completion(.success(resolvedCode?.isEmpty == false ? resolvedCode! : doc.documentID.uppercased()))
            }
        }
    }

    private func notificationDefaultsKey(_ suffix: String, userID: String) -> String {
        "prodconnect.notifications.\(suffix).\(userID)"
    }

    private func loadNotificationState(for userID: String) {
        guard !userID.isEmpty else {
            resetNotificationState()
            return
        }

        seenChatMessageIDsByChannel =
            (userDefaults.dictionary(forKey: notificationDefaultsKey("chat", userID: userID)) as? [String: String]) ?? [:]
        seenTicketUpdateTokens =
            (userDefaults.dictionary(forKey: notificationDefaultsKey("tickets", userID: userID)) as? [String: Double]) ?? [:]
        seenChecklistNotificationIDs = Set(
            (userDefaults.array(forKey: notificationDefaultsKey("checklists", userID: userID)) as? [String]) ?? []
        )
    }

    private func persistNotificationState() {
        guard let userID = user?.id.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty else { return }
        userDefaults.set(seenChatMessageIDsByChannel, forKey: notificationDefaultsKey("chat", userID: userID))
        userDefaults.set(seenTicketUpdateTokens, forKey: notificationDefaultsKey("tickets", userID: userID))
        userDefaults.set(Array(seenChecklistNotificationIDs), forKey: notificationDefaultsKey("checklists", userID: userID))
    }

    private func resetNotificationState() {
        seenChatMessageIDsByChannel = [:]
        seenTicketUpdateTokens = [:]
        seenChecklistNotificationIDs = []
    }

    func markAllNotificationsSeen() {
        for channel in notificationIncomingChannels {
            guard let messageID = channel.messages.last?.id.trimmingCharacters(in: .whitespacesAndNewlines), !messageID.isEmpty else {
                continue
            }
            seenChatMessageIDsByChannel[channel.id] = messageID
        }

        for ticket in notificationAssignedTickets {
            seenTicketUpdateTokens[ticket.id] = ticket.updatedAt.timeIntervalSince1970
        }

        for notice in checklistNotificationNotices {
            seenChecklistNotificationIDs.insert(notice.id)
        }

        persistNotificationState()
        clearDeliveredNotifications()
    }

    private func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        #if canImport(UIKit)
        UIApplication.shared.applicationIconBadgeNumber = 0
        #elseif canImport(AppKit)
        NSApplication.shared.dockTile.badgeLabel = nil
        #endif
    }

    private func checklistItemMentionsCurrentUser(_ text: String, user: UserProfile) -> Bool {
        let tags = mentionTokens(in: text)
        return !mentionMatchTokens(for: user).isDisjoint(with: tags)
    }

    private func mentionTokens(in text: String) -> Set<String> {
        let pattern = "(?<!\\S)@([A-Za-z0-9._-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, options: [], range: range).compactMap {
            guard $0.numberOfRanges > 1, let tokenRange = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[tokenRange]).lowercased()
        })
    }

    private func mentionMatchTokens(for user: UserProfile) -> Set<String> {
        var tokens: Set<String> = []
        let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let localPart = email.split(separator: "@").first, !localPart.isEmpty {
            tokens.insert(String(localPart))
        }
        let name = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty {
            tokens.insert(name.replacingOccurrences(of: " ", with: ""))
            tokens.insert(name.replacingOccurrences(of: " ", with: "."))
            tokens.insert(name.replacingOccurrences(of: " ", with: "_"))
        }
        return tokens
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
            let initialProfile = self.loadCachedUserProfile(for: uid) ?? fallbackProfile

            Task { @MainActor in
                self.user = initialProfile
                self.teamCode = initialProfile.teamCode
                self.isAdmin = initialProfile.isAdmin
                self.loadNotificationState(for: initialProfile.id)
                self.pushLogin(initialProfile.email)
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
                    let normalizedProfileTeamCode = Self.normalizedTeamCode(data["teamCode"] as? String)
                    profile = UserProfile(
                        id: uid,
                        displayName: (data["displayName"] as? String) ?? signedInEmail.components(separatedBy: "@").first ?? "User",
                        email: (data["email"] as? String) ?? signedInEmail,
                        teamCode: normalizedProfileTeamCode,
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
                    Task { @MainActor in
                        self.repairMissingUserProfile(for: authUser) { repairedProfile in
                            guard let repairedProfile else { return }
                            Task { @MainActor in
                                self.user = repairedProfile
                                self.teamCode = repairedProfile.teamCode
                                self.isAdmin = repairedProfile.isAdmin
                                self.cacheUserProfile(repairedProfile)
                                self.loadNotificationState(for: repairedProfile.id)
                                self.listenToTeamData()
                            }
                        }
                    }
                    return
                }

                Task { @MainActor in
                    self.user = profile
                    self.teamCode = profile.teamCode
                    self.isAdmin = profile.isAdmin
                    self.cacheUserProfile(profile)
                    self.loadNotificationState(for: profile.id)
                    self.listenToTeamData()
                }
            }
        }
    }

    func signUp(email: String, password: String, teamCode: String? = nil, isAdmin: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedTeamCode = teamCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let completeSignUp: (String?) -> Void = { validatedTeamCode in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let uid = result?.user.uid ?? UUID().uuidString
                let normalizedTeamCode = validatedTeamCode?.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTeamCode = (normalizedTeamCode?.isEmpty == false ? normalizedTeamCode : self.generateTeamCode()) ?? self.generateTeamCode()
                let subscriptionTier = "free"
                let profile = UserProfile(
                    id: uid,
                    displayName: email.components(separatedBy: "@").first ?? "User",
                    email: email,
                    teamCode: finalTeamCode,
                    isAdmin: isAdmin,
                    subscriptionTier: subscriptionTier,
                    canEditPatchsheet: true,
                    canEditTraining: false,
                    canEditGear: true,
                    canEditIdeas: true,
                    canEditChecklists: true,
                    canSeeChat: false,
                    canSeeTraining: false,
                    canSeeTickets: false
                )

                let teamPayload: [String: Any] = [
                    "code": finalTeamCode,
                    "createdAt": FieldValue.serverTimestamp(),
                    "createdBy": email,
                    "isActive": true,
                    "organizationName": ""
                ]

                let profilePayload: [String: Any]
                do {
                    profilePayload = try self.encodedDictionary(for: profile)
                } catch {
                    completion(.failure(error))
                    return
                }

                let db = self.db

                db.collection("teams").document(finalTeamCode).setData(teamPayload, merge: true) { teamError in
                    if let teamError {
                        completion(.failure(teamError))
                        return
                    }

                    Task { @MainActor in
                        self.ensureTeamIntegrationDocumentsExist(for: finalTeamCode)
                    }

                    db.collection("users").document(uid).setData(profilePayload, merge: true) { userError in
                        if let userError {
                            completion(.failure(userError))
                            return
                        }

                        Task { @MainActor in
                            self.user = profile
                            self.teamCode = finalTeamCode
                            self.isAdmin = isAdmin
                            self.cacheUserProfile(profile)
                            self.loadNotificationState(for: profile.id)
                            self.pushLogin(email)
                            self.listenToTeamData()
                            completion(.success(()))
                        }
                    }
                }
            }
        }

        guard let trimmedTeamCode, !trimmedTeamCode.isEmpty else {
            completeSignUp(nil)
            return
        }

        resolveSignUpTeamCode(trimmedTeamCode) { result in
            switch result {
            case .success(let resolvedCode):
                completeSignUp(resolvedCode)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        pushLogout()
        KeychainHelper.shared.delete(for: "prodconnect_email")
        KeychainHelper.shared.delete(for: "prodconnect_password")
        clearCachedUserProfile()
        removeTeamDataListeners()
        user = nil
        resetNotificationState()
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
        freshserviceIntegration = FreshserviceIntegrationSettings()
        externalTicketFormIntegration = ExternalTicketFormSettings()
        teamCode = nil
        isAdmin = false
        activeTeamListenersCode = nil
        activeChatChannelID = nil
        hasInitializedChannelsSnapshot = false
        hasPrimedTicketAssignmentState = false
        ticketAssignedToCurrentUserIDs = []
        hasPrimedTicketSubmissionState = false
        seenTicketIDs = []
    }

    private func removeTeamDataListeners() {
        teamMembersListener?.remove()
        teamDocumentListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
        ticketsListener?.remove()
        channelsListener?.remove()
        lessonsListener?.remove()
        gearListener?.remove()
        patchsheetListener?.remove()
        locationsListener?.remove()
        roomsListener?.remove()
        freshserviceIntegrationListener?.remove()
        externalTicketFormListener?.remove()
        teamMembersListener = nil
        checklistsListener = nil
        ideasListener = nil
        ticketsListener = nil
        channelsListener = nil
        lessonsListener = nil
        gearListener = nil
        patchsheetListener = nil
        locationsListener = nil
        roomsListener = nil
        freshserviceIntegrationListener = nil
        externalTicketFormListener = nil
    }

    private func restoreSession(for authUser: FirebaseAuth.User) {
        let authUID = authUser.uid
        let authEmail = authUser.email ?? ""
        let fallbackProfile = UserProfile(
            id: authUID,
            displayName: authEmail.components(separatedBy: "@").first ?? "User",
            email: authEmail
        )
        let initialProfile = loadCachedUserProfile(for: authUID) ?? fallbackProfile

        Task { @MainActor in
            self.user = initialProfile
            self.teamCode = initialProfile.teamCode
            self.isAdmin = initialProfile.isAdmin
            self.loadNotificationState(for: initialProfile.id)
            if !initialProfile.email.isEmpty {
                self.pushLogin(initialProfile.email)
            }
            self.listenToTeamData()
        }

        db.collection("users").document(authUID).getDocument { snapshot, fetchError in
            if let fetchError {
                print("Session restore profile fetch failed:", fetchError.localizedDescription)
                return
            }

            let profile: UserProfile
            if let data = snapshot?.data() {
                let normalizedProfileTeamCode = Self.normalizedTeamCode(data["teamCode"] as? String)
                profile = UserProfile(
                    id: authUID,
                    displayName: (data["displayName"] as? String) ?? authEmail.components(separatedBy: "@").first ?? "User",
                    email: (data["email"] as? String) ?? authEmail,
                    teamCode: normalizedProfileTeamCode,
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
                Task { @MainActor in
                    self.repairMissingUserProfile(for: authUser) { repairedProfile in
                        guard let repairedProfile else { return }
                        Task { @MainActor in
                            self.user = repairedProfile
                            self.teamCode = repairedProfile.teamCode
                            self.isAdmin = repairedProfile.isAdmin
                            self.cacheUserProfile(repairedProfile)
                            self.loadNotificationState(for: repairedProfile.id)
                            if !repairedProfile.email.isEmpty {
                                self.pushLogin(repairedProfile.email)
                            }
                            self.listenToTeamData()
                        }
                    }
                }
                return
            }

            Task { @MainActor in
                self.user = profile
                self.teamCode = profile.teamCode
                self.isAdmin = profile.isAdmin
                self.cacheUserProfile(profile)
                self.loadNotificationState(for: profile.id)
                if !profile.email.isEmpty {
                    self.pushLogin(profile.email)
                }
                self.listenToTeamData()
            }
        }
    }

    private func repairMissingUserProfile(
        for authUser: FirebaseAuth.User,
        completion: @escaping (UserProfile?) -> Void
    ) {
        let email = authUser.email ?? ""
        let defaultName = email.components(separatedBy: "@").first ?? "User"
        let generatedTeamCode = generateTeamCode()
        let profile = UserProfile(
            id: authUser.uid,
            displayName: defaultName,
            email: email,
            teamCode: generatedTeamCode,
            isAdmin: false,
            subscriptionTier: "free",
            canEditPatchsheet: true,
            canEditTraining: false,
            canEditGear: true,
            canEditIdeas: true,
            canEditChecklists: true,
            canSeeChat: false,
            canSeeTraining: false,
            canSeeTickets: false
        )

        let profilePayload: [String: Any]
        do {
            profilePayload = try encodedDictionary(for: profile)
        } catch {
            print("Missing-profile repair encode failed:", error.localizedDescription)
            completion(nil)
            return
        }

        let teamPayload: [String: Any] = [
            "code": generatedTeamCode,
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": email,
            "isActive": true,
            "organizationName": ""
        ]

        let db = self.db

        db.collection("teams").document(generatedTeamCode).setData(teamPayload, merge: true) { teamError in
            if let teamError {
                print("Missing-profile repair team write failed:", teamError.localizedDescription)
                completion(nil)
                return
            }

            Task { @MainActor in
                self.ensureTeamIntegrationDocumentsExist(for: generatedTeamCode)
            }

            db.collection("users").document(authUser.uid).setData(profilePayload, merge: true) { userError in
                if let userError {
                    print("Missing-profile repair user write failed:", userError.localizedDescription)
                    completion(nil)
                    return
                }
                completion(profile)
            }
        }
    }

    func listenToTeamData() {
        let normalizedCode = Self.normalizedTeamCode(teamCode)
        if let normalizedCode, !normalizedCode.isEmpty, activeTeamListenersCode == normalizedCode {
            return
        }

        removeTeamDataListeners()
        hasInitializedChannelsSnapshot = false
        activeTeamListenersCode = normalizedCode

        guard let code = normalizedCode, !code.isEmpty else {
            if let user {
                teamMembers = [user]
            }
            organizationName = ""
            locations = []
            rooms = []
            freshserviceIntegration = FreshserviceIntegrationSettings()
            tickets = []
            hasPrimedTicketAssignmentState = false
            ticketAssignedToCurrentUserIDs = []
            hasPrimedTicketSubmissionState = false
            seenTicketIDs = []
            return
        }

        ensureTeamIntegrationDocumentsExist(for: code)

        teamDocumentListener = db.collection("teams")
            .document(code)
            .addSnapshotListener { snapshot, _ in
                let organizationName = snapshot?.data()?["organizationName"] as? String ?? ""
                DispatchQueue.main.async {
                    self.organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
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
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("Ticket listener error for team \(code): \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let values: [SupportTicket] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: SupportTicket.self)
                }
                DispatchQueue.main.async {
                    let affectedGearIDs = self.affectedGearIDs(previousTickets: self.tickets, latestTickets: values)
                    self.processTicketSubmissionNotifications(with: values)
                    self.processTicketAssignmentNotifications(with: values)
                    self.tickets = values
                    print("Ticket listener loaded \(values.count) tickets for team \(code). Visible tickets now: \(self.visibleTickets.count). Current user: \(self.user?.email ?? "unknown")")
                    self.refreshGearTicketState(for: affectedGearIDs)
                }
            }

        channelsListener = queryForUsersTeamCode(collection: "channels", code: code)
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

        patchsheetListener = db.collection("patchsheet")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let values: [PatchRow] = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return self.decodeDocument(data, as: PatchRow.self)
                }
                DispatchQueue.main.async {
                    self.patchsheet = values.sorted(by: PatchRow.autoSort)
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

        freshserviceIntegrationListener = db.collection("teams")
            .document(code)
            .collection("integrations")
            .document("freshservice")
            .addSnapshotListener { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                let settings = FreshserviceIntegrationSettings(
                    apiURL: data["apiURL"] as? String ?? "",
                    apiKey: data["apiKey"] as? String ?? "",
                    isEnabled: data["isEnabled"] as? Bool ?? false,
                    managedByGroup: data["managedByGroup"] as? String ?? "",
                    managedByGroupOptions: data["managedByGroupOptions"] as? [String] ?? [],
                    syncMode: FreshserviceSyncMode(rawValue: data["syncMode"] as? String ?? "") ?? .pull
                )
                DispatchQueue.main.async {
                    self.freshserviceIntegration = settings
                }
            }

        externalTicketFormListener = db.collection("teams")
            .document(code)
            .collection("integrations")
            .document("externalTicketForm")
            .addSnapshotListener { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                let settings = ExternalTicketFormSettings(
                    isEnabled: data["isEnabled"] as? Bool ?? false,
                    accessKey: data["accessKey"] as? String ?? ""
                )
                DispatchQueue.main.async {
                    self.externalTicketFormIntegration = settings
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

    private func processTicketSubmissionNotifications(with tickets: [SupportTicket]) {
        guard let currentUser = user else { return }
        guard currentUser.isAdmin || currentUser.isOwner else { return }

        let currentTicketIDs = Set(tickets.map(\.id))
        guard hasPrimedTicketSubmissionState else {
            seenTicketIDs = currentTicketIDs
            hasPrimedTicketSubmissionState = true
            return
        }

        let newTicketIDs = currentTicketIDs.subtracting(seenTicketIDs)
        let currentUserID = currentUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentEmail = currentUser.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for ticketID in newTicketIDs {
            guard let ticket = tickets.first(where: { $0.id == ticketID }) else { continue }
            let ticketCreatorID = ticket.createdByUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ticketCreatorEmail = ticket.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if (!currentUserID.isEmpty && ticketCreatorID == currentUserID)
                || (!currentEmail.isEmpty && ticketCreatorEmail == currentEmail) {
                continue
            }
            scheduleTicketSubmissionNotification(for: ticket)
        }

        seenTicketIDs = currentTicketIDs
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

    private func scheduleTicketSubmissionNotification(for ticket: SupportTicket) {
        let content = UNMutableNotificationContent()
        content.title = "New Ticket Submitted"
        let trimmedTitle = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let requester = ticket.externalRequesterName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let campus = ticket.campus.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !trimmedTitle.isEmpty {
            parts.append("\"\(trimmedTitle)\"")
        } else {
            parts.append("A new ticket")
        }
        if let requester, !requester.isEmpty {
            parts.append("from \(requester)")
        }
        if !campus.isEmpty {
            parts.append("at \(campus)")
        }
        content.body = parts.joined(separator: " ")
        content.sound = .default
        content.userInfo = ["ticketId": ticket.id]

        let request = UNNotificationRequest(
            identifier: "ticket-submitted-\(ticket.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    func listenToTeamMembers() {
        let normalizedCode = teamCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code = normalizedCode, !code.isEmpty else { return }
        if activeTeamListenersCode == code, teamMembersListener != nil {
            return
        }
        teamMembersListener?.remove()
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

    func conflictingGear(for item: GearItem) -> GearItem? {
        let normalizedSerial = item.serialNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedSerial.isEmpty else { return nil }

        return gear.first { existing in
            existing.id != item.id &&
            existing.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedSerial
        }
    }

    func saveGear(_ item: GearItem, completion: ((Result<Void, Error>) -> Void)? = nil) {
        if let conflict = conflictingGear(for: item) {
            completion?(.failure(GearSaveError.duplicateSerial(
                serial: item.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                existingName: conflict.name
            )))
            return
        }

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
        completion?(.success(()))
    }
    func savePatch(_ item: PatchRow, completion: ((Result<Void, Error>) -> Void)? = nil) {
        do {
            let data = try encodedDictionary(for: item)
            db.collection("patchsheet").document(item.id).setData(data, merge: true) { error in
                Task { @MainActor in
                    if let error {
                        completion?(.failure(error))
                        return
                    }

                    let campus = item.campus.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !campus.isEmpty { self.saveLocation(campus) }
                    if let index = self.patchsheet.firstIndex(where: { $0.id == item.id }) {
                        self.patchsheet[index] = item
                    } else {
                        self.patchsheet.append(item)
                    }
                    completion?(.success(()))
                }
            }
        } catch {
            completion?(.failure(error))
        }
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
        let affectedGearIDs = Set<String>([
            existingTicket?.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines),
            ticket.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        })
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
        ticket.externalRequesterName = ticket.externalRequesterName?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.externalRequesterEmail = ticket.externalRequesterEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        ticket.assignedAgentID = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.assignedAgentName = ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.linkedGearID = ticket.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.linkedGearName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.privateNotes = ticket.privateNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ticket.privateNotes.isEmpty {
            ticket.privateNoteEntries.append(
                TicketPrivateNoteEntry(
                    message: ticket.privateNotes,
                    createdAt: now,
                    author: ticket.lastUpdatedBy ?? ticket.createdBy
                )
            )
            ticket.privateNotes = ""
        }
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

        let ticketRef = db.collection("tickets").document(ticket.id)
        let roomsCollectionRef = db.collection("teams").document(activeTeamCode).collection("rooms")
        var assignmentPayload: [String: Any] = [
            "updatedAt": ticket.updatedAt,
            "lastUpdatedBy": ticket.lastUpdatedBy ?? ""
        ]
        if let assignedAgentID = ticket.assignedAgentID, !assignedAgentID.isEmpty {
            assignmentPayload["assignedAgentID"] = assignedAgentID
        } else {
            assignmentPayload["assignedAgentID"] = FieldValue.delete()
        }
        if let assignedAgentName = ticket.assignedAgentName, !assignedAgentName.isEmpty {
            assignmentPayload["assignedAgentName"] = assignedAgentName
        } else {
            assignmentPayload["assignedAgentName"] = FieldValue.delete()
        }
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
        } else {
            tickets.append(ticket)
        }
        refreshGearTicketState(for: affectedGearIDs)

        let ticketToPersist = ticket
        let shouldPersistRoom = !ticket.room.isEmpty && existingTicket?.room != ticket.room
        let roomToPersist = ticket.room
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Self.makeEncodedDictionary(for: ticketToPersist)
                ticketRef.setData(data, merge: true)
                ticketRef.setData(assignmentPayload, merge: true)
                if shouldPersistRoom {
                    roomsCollectionRef.document(roomToPersist).setData([:])
                }
            } catch {
                print("Save error (tickets):", error)
            }
        }
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
            "organizationName": organizationName,
            "ownerId": currentUser.isOwner ? currentUser.id : (currentUser.isAdmin ? currentUser.id : ""),
            "ownerEmail": currentUser.isOwner ? currentUser.email : (currentUser.isAdmin ? currentUser.email : "")
        ], merge: true)
        ensureTeamIntegrationDocumentsExist(for: generatedCode)
        listenToTeamData()
        listenToTeamMembers()
        return generatedCode
    }
    func deletePatch(_ item: PatchRow, completion: ((Result<Void, Error>) -> Void)? = nil) {
        db.collection("patchsheet").document(item.id).delete { error in
            Task { @MainActor in
                if let error {
                    completion?(.failure(error))
                    return
                }
                self.patchsheet.removeAll { $0.id == item.id }
                completion?(.success(()))
            }
        }
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
        let affectedGearIDs = Set<String>([
            item.linkedGearID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        })
        db.collection("tickets").document(item.id).delete()
        tickets.removeAll { $0.id == item.id }
        refreshGearTicketState(for: affectedGearIDs)
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

    func saveOrganizationName(_ name: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let code = ensureActiveTeamCodeForTicketing(), !code.isEmpty else {
            completion?(.failure(NSError(
                domain: "ProdConnect",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No valid team is available."]
            )))
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        db.collection("teams").document(code).setData([
            "organizationName": trimmedName
        ], merge: true) { error in
            Task { @MainActor in
                if let error {
                    completion?(.failure(error))
                    return
                }
                self.organizationName = trimmedName
                completion?(.success(()))
            }
        }
    }

    func saveFreshserviceIntegration(
        apiURL: String,
        apiKey: String,
        managedByGroup: String,
        managedByGroupOptions: [String],
        syncMode: FreshserviceSyncMode,
        isEnabled: Bool,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let code = ensureActiveTeamCodeForTicketing() else {
            completion?(.failure(NSError(
                domain: "ProdConnect",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No valid team is available for this integration."]
            )))
            return
        }

        let trimmedURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedManagedByGroup = managedByGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedManagedByGroupOptions = Array(Set(
            managedByGroupOptions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let payload: [String: Any] = [
            "apiURL": trimmedURL,
            "apiKey": trimmedKey,
            "managedByGroup": trimmedManagedByGroup,
            "managedByGroupOptions": cleanedManagedByGroupOptions,
            "syncMode": syncMode.rawValue,
            "isEnabled": isEnabled && !trimmedURL.isEmpty && !trimmedKey.isEmpty,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": user?.email ?? ""
        ]

        db.collection("teams")
            .document(code)
            .collection("integrations")
            .document("freshservice")
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion?(.failure(error))
                    } else {
                        self.freshserviceIntegration = FreshserviceIntegrationSettings(
                            apiURL: trimmedURL,
                            apiKey: trimmedKey,
                            isEnabled: isEnabled && !trimmedURL.isEmpty && !trimmedKey.isEmpty,
                            managedByGroup: trimmedManagedByGroup,
                            managedByGroupOptions: cleanedManagedByGroupOptions,
                            syncMode: syncMode
                        )
                        completion?(.success(()))
                    }
                }
            }
    }

    func generateExternalTicketAccessKey() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func saveExternalTicketFormIntegration(
        isEnabled: Bool,
        accessKey: String,
        completion: ((Result<ExternalTicketFormSettings, Error>) -> Void)? = nil
    ) {
        guard let code = ensureActiveTeamCodeForTicketing() else {
            completion?(.failure(NSError(
                domain: "ProdConnect",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No valid team is available for external ticket intake."]
            )))
            return
        }

        let trimmedAccessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAccessKey = trimmedAccessKey.isEmpty ? generateExternalTicketAccessKey() : trimmedAccessKey
        let resolvedSettings = ExternalTicketFormSettings(
            isEnabled: isEnabled,
            accessKey: resolvedAccessKey
        )
        let payload: [String: Any] = [
            "isEnabled": isEnabled,
            "accessKey": resolvedAccessKey,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": user?.email ?? ""
        ]

        db.collection("teams")
            .document(code)
            .collection("integrations")
            .document("externalTicketForm")
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion?(.failure(error))
                    } else {
                        self.externalTicketFormIntegration = resolvedSettings
                        completion?(.success(resolvedSettings))
                    }
                }
            }
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

        let db = self.db
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
                        let batch = db.batch()
                        for doc in chunks[index] {
                            batch.updateData([field: newTrimmed], forDocument: doc.reference)
                        }
                        batch.commit { chunkError in
                            if let chunkError = chunkError {
                                done(chunkError)
                            } else {
                                DispatchQueue.main.async {
                                    commitChunk(index + 1)
                                }
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
                DispatchQueue.main.async {
                    updateCollectionField(collection: collection, field: field) { err in
                        if firstError == nil, let err = err { firstError = err }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                let finalError = firstError
                Task { @MainActor in
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

                    if let finalError {
                        completion?(.failure(finalError))
                    } else {
                        completion?(.success(()))
                    }
                }
            }
        }
    }

    func deleteRoom(_ room: String) {
        guard let code = teamCode, !code.isEmpty else { return }
        db.collection("teams").document(code).collection("rooms").document(room).delete()
        rooms.removeAll { $0 == room }
    }

    func deleteAllGear(completion: ((Result<Void, Error>) -> Void)? = nil) {
        let itemsToDelete = gear
        guard !itemsToDelete.isEmpty else {
            completion?(.success(()))
            return
        }

        let ids = itemsToDelete.map(\.id)
        let imageURLs = itemsToDelete.map(\.imageURL)

        gearListener?.remove()
        gearListener = nil
        gear = []

        DispatchQueue.global(qos: .utility).async {
            for url in imageURLs {
                self.deleteStorageObject(forDownloadURL: url)
            }
        }

        deleteGearDocuments(ids: ids) { result in
            DispatchQueue.main.async {
                if self.gearListener == nil, let code = self.teamCode, !code.isEmpty {
                    self.gearListener = self.queryForUsersTeamCode(collection: "gear", code: code)
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
                }
                switch result {
                case .success:
                    completion?(.success(()))
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }

    func deletePatchesByCategory(_ category: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let toDelete = patchsheet.filter { $0.category == category }
        guard !toDelete.isEmpty else {
            completion?(.success(()))
            return
        }

        let group = DispatchGroup()
        var firstError: Error?
        toDelete.forEach { item in
            group.enter()
            db.collection("patchsheet").document(item.id).delete { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.patchsheet.removeAll { $0.category == category }
            if let firstError {
                completion?(.failure(firstError))
            } else {
                completion?(.success(()))
            }
        }
    }

    func replaceAllGear(_ items: [GearItem], completion: ((Result<Void, Error>) -> Void)? = nil) {
        gear = items

        let locationsToSave = Set(items.flatMap { item in
            [item.location, item.campus]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        })
        locationsToSave.forEach(saveLocation)

        let chunkSize = 250
        let chunks = stride(from: 0, to: items.count, by: chunkSize).map {
            Array(items[$0..<min($0 + chunkSize, items.count)])
        }
        var firstError: Error?

        guard !chunks.isEmpty else {
            completion?(.success(()))
            return
        }

        func commitChunk(index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    if let firstError {
                        completion?(.failure(firstError))
                    } else {
                        completion?(.success(()))
                    }
                }
                return
            }

            let batch = db.batch()
            for item in chunks[index] {
                do {
                    try batch.setData(from: item, forDocument: db.collection("gear").document(item.id))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            batch.commit { error in
                if firstError == nil, let error {
                    firstError = error
                }
                Task { @MainActor in
                    commitChunk(index: index + 1)
                }
            }
        }

        commitChunk(index: 0)
    }

    func upsertGear(_ items: [GearItem], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !items.isEmpty else {
            completion?(.success(()))
            return
        }

        let locationsToSave = Set(items.flatMap { item in
            [item.location, item.campus]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        })
        locationsToSave.forEach(saveLocation)

        let chunkSize = 250
        let chunks = stride(from: 0, to: items.count, by: chunkSize).map {
            Array(items[$0..<min($0 + chunkSize, items.count)])
        }
        var firstError: Error?

        func commitChunk(index: Int) {
            guard index < chunks.count else {
                let merged = Dictionary(uniqueKeysWithValues: gear.map { ($0.id, $0) })
                    .merging(Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })) { _, new in new }
                gear = Array(merged.values)
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                completion?(firstError.map(Result.failure) ?? .success(()))
                return
            }

            let batch = db.batch()
            for item in chunks[index] {
                do {
                    try batch.setData(from: item, forDocument: db.collection("gear").document(item.id), merge: true)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            batch.commit { error in
                if firstError == nil, let error {
                    firstError = error
                }
                Task { @MainActor in
                    commitChunk(index: index + 1)
                }
            }
        }

        commitChunk(index: 0)
    }

    func upsertTickets(_ items: [SupportTicket], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !items.isEmpty else {
            completion?(.success(()))
            return
        }

        let chunkSize = 250
        let chunks = stride(from: 0, to: items.count, by: chunkSize).map {
            Array(items[$0..<min($0 + chunkSize, items.count)])
        }
        var firstError: Error?

        func commitChunk(index: Int) {
            guard index < chunks.count else {
                let merged = Dictionary(uniqueKeysWithValues: tickets.map { ($0.id, $0) })
                    .merging(Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })) { _, new in new }
                tickets = Array(merged.values)
                    .sorted { $0.updatedAt > $1.updatedAt }
                completion?(firstError.map(Result.failure) ?? .success(()))
                return
            }

            let batch = db.batch()
            for item in chunks[index] {
                do {
                    try batch.setData(from: item, forDocument: db.collection("tickets").document(item.id), merge: true)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            batch.commit { error in
                if firstError == nil, let error {
                    firstError = error
                }
                Task { @MainActor in
                    commitChunk(index: index + 1)
                }
            }
        }

        commitChunk(index: 0)
    }

    func replaceAllPatch(_ rows: [PatchRow], completion: ((Result<Void, Error>) -> Void)? = nil) {
        patchsheet = rows

        let locationsToSave = Set(rows.map(\.campus)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        locationsToSave.forEach(saveLocation)

        let chunkSize = 250
        let chunks = stride(from: 0, to: rows.count, by: chunkSize).map {
            Array(rows[$0..<min($0 + chunkSize, rows.count)])
        }
        var firstError: Error?

        guard !chunks.isEmpty else {
            completion?(.success(()))
            return
        }

        func commitChunk(index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    if let firstError {
                        completion?(.failure(firstError))
                    } else {
                        completion?(.success(()))
                    }
                }
                return
            }

            let batch = db.batch()
            for row in chunks[index] {
                do {
                    try batch.setData(from: row, forDocument: db.collection("patchsheet").document(row.id))
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            batch.commit { error in
                if firstError == nil, let error {
                    firstError = error
                }
                Task { @MainActor in
                    commitChunk(index: index + 1)
                }
            }
        }

        commitChunk(index: 0)
    }

    private func refreshGearTicketState(for gearIDs: Set<String>? = nil) {
        guard !gear.isEmpty else { return }
        if let gearIDs, gearIDs.isEmpty { return }

        var updatedGear = gear
        var hasChanges = false
        for index in updatedGear.indices {
            var item = updatedGear[index]
            if let gearIDs, !gearIDs.isEmpty, !gearIDs.contains(item.id) {
                continue
            }
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
