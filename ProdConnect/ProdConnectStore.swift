import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import OneSignalFramework

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
    @Published var canEditPatchsheet = false
    @Published var canSeeChat = true
    @Published var canSeeTrainingTab = true
    @Published var canEditGear = true
    @Published var canEditIdeas = true
    @Published var canEditChecklists = true
    @Published var isAdmin = false
    @Published var teamCode: String?

    private init() {}

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
        teamMembersListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
        channelsListener?.remove()
        lessonsListener?.remove()
        gearListener?.remove()
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
    }

    func listenToTeamData() {
        teamMembersListener?.remove()
        checklistsListener?.remove()
        ideasListener?.remove()
        channelsListener?.remove()
        lessonsListener?.remove()
        gearListener?.remove()

        guard let code = teamCode, !code.isEmpty else {
            if let user {
                teamMembers = [user]
            }
            return
        }

        teamMembersListener = db.collection("users")
            .whereField("teamCode", isEqualTo: code)
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
                    self.channels = values.sorted { $0.position < $1.position }
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
    }

    func listenToTeamMembers() {
        teamMembersListener?.remove()
        guard let code = teamCode, !code.isEmpty else { return }
        teamMembersListener = db.collection("users")
            .whereField("teamCode", isEqualTo: code)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let members = docs.compactMap { try? $0.data(as: UserProfile.self) }
                DispatchQueue.main.async {
                    self.teamMembers = members
                }
            }
    }

    func saveGear(_ item: GearItem) {
        save(item, collection: "gear", id: item.id)
        if let index = gear.firstIndex(where: { $0.id == item.id }) {
            gear[index] = item
        } else {
            gear.append(item)
        }
    }
    func savePatch(_ item: PatchRow) { save(item, collection: "patchsheet", id: item.id) }
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
