import Foundation

struct PatchRow: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var input: String
    var output: String
    var teamCode: String
    var category: String
    var campus: String
    var room: String
    var channelCount: Int?
    var universe: String?
    var position: Int = 0
}

struct UserProfile: Identifiable, Codable {
    var id: String = UUID().uuidString
    var displayName: String
    var email: String
    var teamCode: String?
    var isAdmin: Bool = false
    var isOwner: Bool = false
    var subscriptionTier: String = "free"
    var assignedCampus: String = ""
    var canEditPatchsheet: Bool = false
    var canEditTraining: Bool = false
    var canEditGear: Bool = false
    var canEditIdeas: Bool = false
    var canEditChecklists: Bool = false
    var canSeeChat: Bool = true
    var canSeePatchsheet: Bool = true
    var canSeeTraining: Bool = true
    var canSeeGear: Bool = true
    var canSeeIdeas: Bool = true
    var canSeeChecklists: Bool = true

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case email
        case teamCode
        case isAdmin
        case isOwner
        case subscriptionTier
        case assignedCampus
        case canEditPatchsheet
        case canEditTraining
        case canEditGear
        case canEditIdeas
        case canEditChecklists
        case canSeeChat
        case canSeePatchsheet
        case canSeeTraining
        case canSeeGear
        case canSeeIdeas
        case canSeeChecklists
    }

    init(
        id: String = UUID().uuidString,
        displayName: String,
        email: String,
        teamCode: String? = nil,
        isAdmin: Bool = false,
        isOwner: Bool = false,
        subscriptionTier: String = "free",
        assignedCampus: String = "",
        canEditPatchsheet: Bool = false,
        canEditTraining: Bool = false,
        canEditGear: Bool = false,
        canEditIdeas: Bool = false,
        canEditChecklists: Bool = false,
        canSeeChat: Bool = true,
        canSeePatchsheet: Bool = true,
        canSeeTraining: Bool = true,
        canSeeGear: Bool = true,
        canSeeIdeas: Bool = true,
        canSeeChecklists: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.teamCode = teamCode
        self.isAdmin = isAdmin
        self.isOwner = isOwner
        self.subscriptionTier = subscriptionTier
        self.assignedCampus = assignedCampus
        self.canEditPatchsheet = canEditPatchsheet
        self.canEditTraining = canEditTraining
        self.canEditGear = canEditGear
        self.canEditIdeas = canEditIdeas
        self.canEditChecklists = canEditChecklists
        self.canSeeChat = canSeeChat
        self.canSeePatchsheet = canSeePatchsheet
        self.canSeeTraining = canSeeTraining
        self.canSeeGear = canSeeGear
        self.canSeeIdeas = canSeeIdeas
        self.canSeeChecklists = canSeeChecklists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enum LegacyCodingKeys: String, CodingKey {
            case subriptionTier
        }
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        let decodedEmail = try container.decodeIfPresent(String.self, forKey: .email)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackName = decodedEmail.components(separatedBy: "@").first ?? "User"
        let decodedName = try container.decodeIfPresent(String.self, forKey: .displayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        email = decodedEmail
        displayName = decodedName.isEmpty ? fallbackName : decodedName
        teamCode = try container.decodeIfPresent(String.self, forKey: .teamCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        let decodedSubscriptionTier = try container.decodeIfPresent(String.self, forKey: .subscriptionTier)
        let legacyDecodedSubscriptionTier = try legacyContainer.decodeIfPresent(String.self, forKey: .subriptionTier)
        subscriptionTier = decodedSubscriptionTier ?? legacyDecodedSubscriptionTier ?? "free"
        assignedCampus = try container.decodeIfPresent(String.self, forKey: .assignedCampus) ?? ""
        canEditPatchsheet = try container.decodeIfPresent(Bool.self, forKey: .canEditPatchsheet) ?? false
        canEditTraining = try container.decodeIfPresent(Bool.self, forKey: .canEditTraining) ?? false
        canEditGear = try container.decodeIfPresent(Bool.self, forKey: .canEditGear) ?? false
        canEditIdeas = try container.decodeIfPresent(Bool.self, forKey: .canEditIdeas) ?? false
        canEditChecklists = try container.decodeIfPresent(Bool.self, forKey: .canEditChecklists) ?? false
        canSeeChat = try container.decodeIfPresent(Bool.self, forKey: .canSeeChat) ?? true
        canSeePatchsheet = try container.decodeIfPresent(Bool.self, forKey: .canSeePatchsheet) ?? true
        canSeeTraining = try container.decodeIfPresent(Bool.self, forKey: .canSeeTraining) ?? true
        canSeeGear = try container.decodeIfPresent(Bool.self, forKey: .canSeeGear) ?? true
        canSeeIdeas = try container.decodeIfPresent(Bool.self, forKey: .canSeeIdeas) ?? true
        canSeeChecklists = try container.decodeIfPresent(Bool.self, forKey: .canSeeChecklists) ?? true
    }

    enum Role {
        case free
        case basic
        case premium
        case admin
    }

    var role: Role {
        if isAdmin { return .admin }
        switch subscriptionTier.lowercased() {
        case "premium": return .premium
        case "basic": return .basic
        default: return .free
        }
    }

    var hasCampusRoomFeatures: Bool {
        role == .premium || role == .admin
    }
}

struct TrainingLesson: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var category: String
    var teamCode: String
    var durationSeconds: Int = 0
    var urlString: String? = nil
    var isCompleted: Bool = false
    var assignedToUserID: String? = nil
    var assignedToUserEmail: String? = nil
}

struct ChecklistItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var isDone: Bool = false
    var completedAt: Date? = nil
    var completedBy: String? = nil
}

struct ChecklistTemplate: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var teamCode: String
    var items: [ChecklistItem] = []
    var createdBy: String? = nil
    var dueDate: Date? = nil
    var completedAt: Date? = nil
    var completedBy: String? = nil
}

struct IdeaCard: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var detail: String = ""
    var tags: [String] = []
    var teamCode: String
    var createdBy: String? = nil
    var implemented: Bool = false
    var completedAt: Date? = nil
    var likedBy: [String] = []
}

struct ChatChannel: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var teamCode: String
    var position: Int = 0
    var isReadOnly: Bool = false
    var isHidden: Bool = false
    var readOnlyUserEmails: [String] = []
    var hiddenUserEmails: [String] = []
    var messages: [ChatMessage] = []
    var kind: ChatChannelKind = .group
    var participantEmails: [String] = []
    var lastMessageAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case teamCode
        case position
        case isReadOnly
        case isHidden
        case readOnlyUserEmails
        case hiddenUserEmails
        case messages
        case kind
        case participantEmails
        case lastMessageAt
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        teamCode: String,
        position: Int = 0,
        isReadOnly: Bool = false,
        isHidden: Bool = false,
        readOnlyUserEmails: [String] = [],
        hiddenUserEmails: [String] = [],
        messages: [ChatMessage] = [],
        kind: ChatChannelKind = .group,
        participantEmails: [String] = [],
        lastMessageAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.teamCode = teamCode
        self.position = position
        self.isReadOnly = isReadOnly
        self.isHidden = isHidden
        self.readOnlyUserEmails = readOnlyUserEmails
        self.hiddenUserEmails = hiddenUserEmails
        self.messages = messages
        self.kind = kind
        self.participantEmails = participantEmails
        self.lastMessageAt = lastMessageAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Channel"
        teamCode = try container.decodeIfPresent(String.self, forKey: .teamCode) ?? ""
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        readOnlyUserEmails = try container.decodeIfPresent([String].self, forKey: .readOnlyUserEmails) ?? []
        hiddenUserEmails = try container.decodeIfPresent([String].self, forKey: .hiddenUserEmails) ?? []
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        kind = try container.decodeIfPresent(ChatChannelKind.self, forKey: .kind) ?? .group
        participantEmails = try container.decodeIfPresent([String].self, forKey: .participantEmails) ?? []
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(teamCode, forKey: .teamCode)
        try container.encode(position, forKey: .position)
        try container.encode(isReadOnly, forKey: .isReadOnly)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(readOnlyUserEmails, forKey: .readOnlyUserEmails)
        try container.encode(hiddenUserEmails, forKey: .hiddenUserEmails)
        try container.encode(messages, forKey: .messages)
        try container.encode(kind, forKey: .kind)
        try container.encode(participantEmails, forKey: .participantEmails)
        try container.encodeIfPresent(lastMessageAt, forKey: .lastMessageAt)
    }
}

enum ChatChannelKind: String, Codable {
    case group
    case direct
}

struct ChatMessage: Identifiable, Codable {
    var id: String = UUID().uuidString
    var author: String
    var text: String
    var timestamp: Date
    var editedAt: Date? = nil
    var attachmentURL: String? = nil
    var attachmentName: String? = nil
    var attachmentKind: ChatAttachmentKind? = nil
}

enum ChatAttachmentKind: String, Codable {
    case image
    case file
}
