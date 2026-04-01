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

extension PatchRow {
    nonisolated private static func firstNumber(in value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let digits = trimmed
            .split(whereSeparator: { !$0.isNumber })
            .first
            .map(String.init)

        guard let digits else { return nil }
        return Int(digits)
    }

    nonisolated var sortUniverseNumber: Int {
        Self.firstNumber(in: universe ?? "") ?? 0
    }

    nonisolated var sortSignalNumber: Int {
        Self.firstNumber(in: input) ?? Self.firstNumber(in: output) ?? Int.max
    }

    nonisolated static func autoSort(_ lhs: PatchRow, _ rhs: PatchRow) -> Bool {
        if lhs.sortUniverseNumber != rhs.sortUniverseNumber {
            return lhs.sortUniverseNumber < rhs.sortUniverseNumber
        }
        if lhs.sortSignalNumber != rhs.sortSignalNumber {
            return lhs.sortSignalNumber < rhs.sortSignalNumber
        }

        let lhsInput = lhs.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsInput = rhs.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputOrder = lhsInput.localizedCaseInsensitiveCompare(rhsInput)
        if inputOrder != .orderedSame {
            return inputOrder == .orderedAscending
        }

        let lhsOutput = lhs.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsOutput = rhs.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputOrder = lhsOutput.localizedCaseInsensitiveCompare(rhsOutput)
        if outputOrder != .orderedSame {
            return outputOrder == .orderedAscending
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
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
    var isTicketAgent: Bool = false
    var canSeeChat: Bool = true
    var canSeePatchsheet: Bool = true
    var canSeeTraining: Bool = true
    var canSeeGear: Bool = true
    var canSeeIdeas: Bool = true
    var canSeeChecklists: Bool = true
    var canSeeTickets: Bool = true

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
        case isTicketAgent
        case canSeeChat
        case canSeePatchsheet
        case canSeeTraining
        case canSeeGear
        case canSeeIdeas
        case canSeeChecklists
        case canSeeTickets
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
        isTicketAgent: Bool = false,
        canSeeChat: Bool = true,
        canSeePatchsheet: Bool = true,
        canSeeTraining: Bool = true,
        canSeeGear: Bool = true,
        canSeeIdeas: Bool = true,
        canSeeChecklists: Bool = true,
        canSeeTickets: Bool = true
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
        self.isTicketAgent = isTicketAgent
        self.canSeeChat = canSeeChat
        self.canSeePatchsheet = canSeePatchsheet
        self.canSeeTraining = canSeeTraining
        self.canSeeGear = canSeeGear
        self.canSeeIdeas = canSeeIdeas
        self.canSeeChecklists = canSeeChecklists
        self.canSeeTickets = canSeeTickets
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
        isTicketAgent = try container.decodeIfPresent(Bool.self, forKey: .isTicketAgent) ?? false
        canSeeChat = try container.decodeIfPresent(Bool.self, forKey: .canSeeChat) ?? true
        canSeePatchsheet = try container.decodeIfPresent(Bool.self, forKey: .canSeePatchsheet) ?? true
        canSeeTraining = try container.decodeIfPresent(Bool.self, forKey: .canSeeTraining) ?? true
        canSeeGear = try container.decodeIfPresent(Bool.self, forKey: .canSeeGear) ?? true
        canSeeIdeas = try container.decodeIfPresent(Bool.self, forKey: .canSeeIdeas) ?? true
        canSeeChecklists = try container.decodeIfPresent(Bool.self, forKey: .canSeeChecklists) ?? true
        canSeeTickets = try container.decodeIfPresent(Bool.self, forKey: .canSeeTickets) ?? true
    }

    enum Role {
        case free
        case basic
        case premium
        case admin
    }

    var role: Role {
        if isAdmin { return .admin }
        switch normalizedSubscriptionTier {
        case "premium", "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return .premium
        case "basic", "basic_ticketing", "basic w/ticketing", "basic with ticketing":
            return .basic
        default: return .free
        }
    }

    var normalizedSubscriptionTier: String {
        subscriptionTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var subscriptionTierRank: Int {
        switch normalizedSubscriptionTier {
        case "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return 4
        case "premium":
            return 3
        case "basic_ticketing", "basic w/ticketing", "basic with ticketing":
            return 2
        case "basic":
            return 1
        default:
            return 0
        }
    }

    var hasChatAndTrainingFeatures: Bool {
        normalizedSubscriptionTier != "free"
    }

    var hasCampusRoomFeatures: Bool {
        switch normalizedSubscriptionTier {
        case "premium", "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return true
        default:
            return false
        }
    }

    var hasTicketingFeatures: Bool {
        switch normalizedSubscriptionTier {
        case "basic_ticketing", "basic w/ticketing", "basic with ticketing",
             "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return true
        default:
            return false
        }
    }

    func canDelete(_ target: UserProfile) -> Bool {
        guard id != target.id else { return false }
        guard !target.isOwner else { return false }
        if isOwner { return true }
        return isAdmin && !target.isAdmin
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
    var notes: String = ""
    var isDone: Bool = false
    var completedAt: Date? = nil
    var completedBy: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case notes
        case isDone
        case completedAt
        case completedBy
    }

    init(
        id: String = UUID().uuidString,
        text: String,
        notes: String = "",
        isDone: Bool = false,
        completedAt: Date? = nil,
        completedBy: String? = nil
    ) {
        self.id = id
        self.text = text
        self.notes = notes
        self.isDone = isDone
        self.completedAt = completedAt
        self.completedBy = completedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decode(String.self, forKey: .text)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
    }
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

enum TicketStatus: String, Codable, CaseIterable, Equatable {
    case new = "New"
    case open = "Open"
    case inProgress = "Pending"
    case resolved = "Resolved"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case TicketStatus.new.rawValue:
            self = .new
        case TicketStatus.open.rawValue:
            self = .open
        case "In Progress", TicketStatus.inProgress.rawValue:
            self = .inProgress
        case TicketStatus.resolved.rawValue:
            self = .resolved
        default:
            self = .new
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var sortOrder: Int {
        switch self {
        case .new: return 0
        case .open: return 1
        case .inProgress: return 2
        case .resolved: return 3
        }
    }
}

struct TicketActivityEntry: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var message: String
    var createdAt: Date = Date()
    var author: String? = nil
}

struct TicketPrivateNoteEntry: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var message: String
    var createdAt: Date = Date()
    var author: String? = nil
}

enum TicketAttachmentKind: String, Codable, Equatable {
    case image
    case video
    case document
}

struct SupportTicket: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var detail: String = ""
    var teamCode: String
    var campus: String = ""
    var room: String = ""
    var status: TicketStatus = .new
    var createdBy: String? = nil
    var createdByUserID: String? = nil
    var externalRequesterName: String? = nil
    var externalRequesterEmail: String? = nil
    var assignedAgentID: String? = nil
    var assignedAgentName: String? = nil
    var linkedGearID: String? = nil
    var linkedGearName: String? = nil
    var dueDate: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var resolvedAt: Date? = nil
    var lastUpdatedBy: String? = nil
    var attachmentURL: String? = nil
    var attachmentName: String? = nil
    var attachmentKind: TicketAttachmentKind? = nil
    var externalSubmission: Bool = false
    var privateNotes: String = ""
    var privateNoteEntries: [TicketPrivateNoteEntry] = []
    var activity: [TicketActivityEntry] = []

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case teamCode
        case campus
        case room
        case status
        case createdBy
        case createdByUserID
        case externalRequesterName
        case externalRequesterEmail
        case assignedAgentID
        case assignedAgentName
        case linkedGearID
        case linkedGearName
        case dueDate
        case createdAt
        case updatedAt
        case resolvedAt
        case lastUpdatedBy
        case attachmentURL
        case attachmentName
        case attachmentKind
        case externalSubmission
        case privateNotes
        case privateNoteEntries
        case activity
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        detail: String = "",
        teamCode: String,
        campus: String = "",
        room: String = "",
        status: TicketStatus = .new,
        createdBy: String? = nil,
        createdByUserID: String? = nil,
        externalRequesterName: String? = nil,
        externalRequesterEmail: String? = nil,
        assignedAgentID: String? = nil,
        assignedAgentName: String? = nil,
        linkedGearID: String? = nil,
        linkedGearName: String? = nil,
        dueDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil,
        lastUpdatedBy: String? = nil,
        attachmentURL: String? = nil,
        attachmentName: String? = nil,
        attachmentKind: TicketAttachmentKind? = nil,
        externalSubmission: Bool = false,
        privateNotes: String = "",
        privateNoteEntries: [TicketPrivateNoteEntry] = [],
        activity: [TicketActivityEntry] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.teamCode = teamCode
        self.campus = campus
        self.room = room
        self.status = status
        self.createdBy = createdBy
        self.createdByUserID = createdByUserID
        self.externalRequesterName = externalRequesterName
        self.externalRequesterEmail = externalRequesterEmail
        self.assignedAgentID = assignedAgentID
        self.assignedAgentName = assignedAgentName
        self.linkedGearID = linkedGearID
        self.linkedGearName = linkedGearName
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.lastUpdatedBy = lastUpdatedBy
        self.attachmentURL = attachmentURL
        self.attachmentName = attachmentName
        self.attachmentKind = attachmentKind
        self.externalSubmission = externalSubmission
        self.privateNotes = privateNotes
        self.privateNoteEntries = privateNoteEntries
        self.activity = activity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        teamCode = try container.decodeIfPresent(String.self, forKey: .teamCode) ?? ""
        campus = try container.decodeIfPresent(String.self, forKey: .campus) ?? ""
        room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
        status = try container.decodeIfPresent(TicketStatus.self, forKey: .status) ?? .new
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        createdByUserID = try container.decodeIfPresent(String.self, forKey: .createdByUserID)
        externalRequesterName = try container.decodeIfPresent(String.self, forKey: .externalRequesterName)
        externalRequesterEmail = try container.decodeIfPresent(String.self, forKey: .externalRequesterEmail)
        assignedAgentID = try container.decodeIfPresent(String.self, forKey: .assignedAgentID)
        assignedAgentName = try container.decodeIfPresent(String.self, forKey: .assignedAgentName)
        linkedGearID = try container.decodeIfPresent(String.self, forKey: .linkedGearID)
        linkedGearName = try container.decodeIfPresent(String.self, forKey: .linkedGearName)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        lastUpdatedBy = try container.decodeIfPresent(String.self, forKey: .lastUpdatedBy)
        attachmentURL = try container.decodeIfPresent(String.self, forKey: .attachmentURL)
        attachmentName = try container.decodeIfPresent(String.self, forKey: .attachmentName)
        attachmentKind = try container.decodeIfPresent(TicketAttachmentKind.self, forKey: .attachmentKind)
        externalSubmission = try container.decodeIfPresent(Bool.self, forKey: .externalSubmission) ?? false
        let legacyPrivateNotes = try container.decodeIfPresent(String.self, forKey: .privateNotes) ?? ""
        privateNoteEntries = try container.decodeIfPresent([TicketPrivateNoteEntry].self, forKey: .privateNoteEntries) ?? []
        if privateNoteEntries.isEmpty {
            let trimmedLegacyNotes = legacyPrivateNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLegacyNotes.isEmpty {
                privateNoteEntries = [
                    TicketPrivateNoteEntry(
                        message: trimmedLegacyNotes,
                        createdAt: updatedAt,
                        author: lastUpdatedBy ?? createdBy
                    )
                ]
            }
        }
        privateNotes = ""
        activity = try container.decodeIfPresent([TicketActivityEntry].self, forKey: .activity) ?? []
    }
}

struct GearTicketHistoryEntry: Identifiable, Codable, Equatable {
    var id: String { ticketID }
    var ticketID: String
    var ticketTitle: String
    var status: TicketStatus
    var campus: String = ""
    var room: String = ""
    var updatedAt: Date = Date()
    var resolvedAt: Date? = nil
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
