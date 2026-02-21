import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import OneSignalFramework
import UserNotifications
import UIKit

@MainActor
final class ProdConnectStore: ObservableObject {
        // Add deleteGear method for compatibility
        func deleteGear(items: [GearItem]) {
            for item in items {
                db.collection("gear").document(item.id).delete()
            }
            gear.removeAll { g in items.contains(where: { $0.id == g.id }) }
        }
    static let shared = ProdConnectStore()

    let db = Firestore.firestore()
    private var teamMembersListener: ListenerRegistration?
    private var checklistsListener: ListenerRegistration?
    private var ideasListener: ListenerRegistration?
    private var channelsListener: ListenerRegistration?
    private var lessonsListener: ListenerRegistration?
    private var gearListener: ListenerRegistration?
    private var locationsListener: ListenerRegistration?
    private var roomsListener: ListenerRegistration?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var hasInitializedChannelsSnapshot = false
    private var activeChatChannelID: String?

    @Published var gear: [GearItem] = []
    @Published var patchsheet: [PatchRow] = []
    @Published var user: UserProfile?
    @Published var lessons: [TrainingLesson] = []
    @Published var checklists: [ChecklistTemplate] = []
    @Published var ideas: [IdeaCard] = []
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
        return user.isAdmin || user.isOwner || user.canSeeChat
    }
    var canSeeTrainingTab: Bool {
        guard let user else { return false }
        return user.isAdmin || user.isOwner || user.canSeeTraining
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
                OneSignal.login(fallbackProfile.email)
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
                        canSeeChat: data["canSeeChat"] as? Bool ?? true,
                        canSeePatchsheet: data["canSeePatchsheet"] as? Bool ?? true,
                        canSeeTraining: data["canSeeTraining"] as? Bool ?? true,
                        canSeeGear: data["canSeeGear"] as? Bool ?? true,
                        canSeeIdeas: data["canSeeIdeas"] as? Bool ?? true,
                        canSeeChecklists: data["canSeeChecklists"] as? Bool ?? true
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
            let profile = UserProfile(
                id: uid,
                displayName: email.components(separatedBy: "@").first ?? "User",
                email: email,
                teamCode: teamCode,
                isAdmin: isAdmin
            )
            self.user = profile
            self.teamCode = teamCode
            self.isAdmin = isAdmin
            self.save(profile, collection: "users", id: uid)
            OneSignal.login(email)
            self.listenToTeamData()
            completion(.success(()))
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        OneSignal.logout()
        KeychainHelper.shared.delete(for: "prodconnect_email")
        KeychainHelper.shared.delete(for: "prodconnect_password")
        teamMembersListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
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
        channels = []
        teamMembers = []
        locations = []
        rooms = []
        teamCode = nil
        isAdmin = false
        activeChatChannelID = nil
        hasInitializedChannelsSnapshot = false
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
                OneSignal.login(fallbackProfile.email)
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
                    canSeeChat: data["canSeeChat"] as? Bool ?? true,
                    canSeePatchsheet: data["canSeePatchsheet"] as? Bool ?? true,
                    canSeeTraining: data["canSeeTraining"] as? Bool ?? true,
                    canSeeGear: data["canSeeGear"] as? Bool ?? true,
                    canSeeIdeas: data["canSeeIdeas"] as? Bool ?? true,
                    canSeeChecklists: data["canSeeChecklists"] as? Bool ?? true
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
                    OneSignal.login(profile.email)
                }
                self.listenToTeamData()
            }
        }
    }

    func listenToTeamData() {
        teamMembersListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
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

            if channel.id == activeChatChannelID, UIApplication.shared.applicationState == .active {
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

            scheduleLocalChatNotification(for: latestMessage, channelName: channel.name, channelID: channel.id)
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
    func saveChecklist(_ item: ChecklistTemplate) { save(item, collection: "checklists", id: item.id) }
    func saveIdea(_ item: IdeaCard) { save(item, collection: "ideas", id: item.id) }
    func saveChannel(_ item: ChatChannel) {
        save(item, collection: "channels", id: item.id)
        if let index = channels.firstIndex(where: { $0.id == item.id }) {
            channels[index] = item
        } else {
            channels.append(item)
        }
        channels.sort { $0.position < $1.position }
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
                ("users", "assignedCampus")
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
}
