import Foundation

struct PatchRow: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var input: String
    var output: String
    var notes: String
    var teamCode: String
    var category: String
    var campus: String
    var room: String
    var channelCount: Int?
    var universe: String?
    var ndiEnabled: Bool = false
    var position: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case input
        case output
        case notes
        case teamCode
        case category
        case campus
        case room
        case channelCount
        case universe
        case ndiEnabled
        case position
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        input: String,
        output: String,
        notes: String = "",
        teamCode: String,
        category: String,
        campus: String,
        room: String,
        channelCount: Int? = nil,
        universe: String? = nil,
        ndiEnabled: Bool = false,
        position: Int = 0
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.output = output
        self.notes = notes
        self.teamCode = teamCode
        self.category = category
        self.campus = campus
        self.room = room
        self.channelCount = channelCount
        self.universe = universe
        self.ndiEnabled = ndiEnabled
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        input = try container.decode(String.self, forKey: .input)
        output = try container.decode(String.self, forKey: .output)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        teamCode = try container.decode(String.self, forKey: .teamCode)
        category = try container.decode(String.self, forKey: .category)
        campus = try container.decodeIfPresent(String.self, forKey: .campus) ?? ""
        room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount)
        universe = try container.decodeIfPresent(String.self, forKey: .universe)
        ndiEnabled = try container.decodeIfPresent(Bool.self, forKey: .ndiEnabled) ?? false
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
    }
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
        if lhs.position != rhs.position {
            return lhs.position < rhs.position
        }
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
    var canEditRunOfShow: Bool = false
    var canEditGear: Bool = false
    var canEditIdeas: Bool = false
    var canEditChecklists: Bool = false
    var isTicketAgent: Bool = false
    var canSeeChat: Bool = true
    var canSeePatchsheet: Bool = true
    var canSeeTraining: Bool = true
    var canSeeRunOfShow: Bool = true
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
        case canEditRunOfShow
        case canEditGear
        case canEditIdeas
        case canEditChecklists
        case isTicketAgent
        case canSeeChat
        case canSeePatchsheet
        case canSeeTraining
        case canSeeRunOfShow
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
        canEditRunOfShow: Bool = false,
        canEditGear: Bool = false,
        canEditIdeas: Bool = false,
        canEditChecklists: Bool = false,
        isTicketAgent: Bool = false,
        canSeeChat: Bool = true,
        canSeePatchsheet: Bool = true,
        canSeeTraining: Bool = true,
        canSeeRunOfShow: Bool = true,
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
        self.canEditRunOfShow = canEditRunOfShow
        self.canEditGear = canEditGear
        self.canEditIdeas = canEditIdeas
        self.canEditChecklists = canEditChecklists
        self.isTicketAgent = isTicketAgent
        self.canSeeChat = canSeeChat
        self.canSeePatchsheet = canSeePatchsheet
        self.canSeeTraining = canSeeTraining
        self.canSeeRunOfShow = canSeeRunOfShow
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
        canEditRunOfShow = try container.decodeIfPresent(Bool.self, forKey: .canEditRunOfShow) ?? false
        canEditGear = try container.decodeIfPresent(Bool.self, forKey: .canEditGear) ?? false
        canEditIdeas = try container.decodeIfPresent(Bool.self, forKey: .canEditIdeas) ?? false
        canEditChecklists = try container.decodeIfPresent(Bool.self, forKey: .canEditChecklists) ?? false
        isTicketAgent = try container.decodeIfPresent(Bool.self, forKey: .isTicketAgent) ?? false
        canSeeChat = try container.decodeIfPresent(Bool.self, forKey: .canSeeChat) ?? true
        canSeePatchsheet = try container.decodeIfPresent(Bool.self, forKey: .canSeePatchsheet) ?? true
        canSeeTraining = try container.decodeIfPresent(Bool.self, forKey: .canSeeTraining) ?? true
        canSeeRunOfShow = try container.decodeIfPresent(Bool.self, forKey: .canSeeRunOfShow) ?? true
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

    var hasPaidSubscription: Bool {
        normalizedSubscriptionTier != "free"
    }

    var hasChecklistTaskAssignmentFeatures: Bool {
        hasPaidSubscription
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
    var groupName: String? = nil
    var teamCode: String
    var durationSeconds: Int = 0
    var urlString: String? = nil
    var isCompleted: Bool = false
    var assignedToUserID: String? = nil
    var assignedToUserEmail: String? = nil
}

struct RunOfShowItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var lengthMinutes: Int
    var lengthSeconds: Int
    var person: String
    var notes: String
    var position: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case lengthMinutes
        case lengthSeconds
        case person
        case notes
        case position
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        lengthMinutes: Int = 5,
        lengthSeconds: Int = 0,
        person: String = "",
        notes: String = "",
        position: Int = 0
    ) {
        self.id = id
        self.title = title
        self.lengthMinutes = lengthMinutes
        self.lengthSeconds = lengthSeconds
        self.person = person
        self.notes = notes
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        lengthMinutes = try container.decodeIfPresent(Int.self, forKey: .lengthMinutes) ?? 5
        lengthSeconds = try container.decodeIfPresent(Int.self, forKey: .lengthSeconds) ?? 0
        person = try container.decodeIfPresent(String.self, forKey: .person) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
    }
}

enum RunOfShowStagePlotRole: String, CaseIterable, Codable, Identifiable {
    case instrument = "Instrument"
    case vocal = "Vocal"
    case drumSet = "Drum Set"
    case guitar = "Guitar"
    case bassGuitar = "Bass Guitar"
    case microphoneStand = "Microphone Stand"
    case keyboard = "Keyboard"
    case speaker = "Speaker"

    var id: String { rawValue }
}

extension RunOfShowStagePlotRole {
    var defaultTitle: String { rawValue }

    var systemImageName: String? {
        switch self {
        case .instrument, .vocal:
            return nil
        case .drumSet:
            return "drumsticks.fill"
        case .guitar:
            return "guitars.fill"
        case .bassGuitar:
            return "guitars"
        case .microphoneStand:
            return "music.mic"
        case .keyboard:
            return "pianokeys"
        case .speaker:
            return "hifispeaker.2.fill"
        }
    }

    var usesSymbolArtwork: Bool {
        systemImageName != nil
    }

    var defaultPosition: CGPoint {
        switch self {
        case .instrument:
            return CGPoint(x: 0.35, y: 0.55)
        case .vocal:
            return CGPoint(x: 0.65, y: 0.55)
        case .drumSet:
            return CGPoint(x: 0.5, y: 0.34)
        case .guitar:
            return CGPoint(x: 0.28, y: 0.58)
        case .bassGuitar:
            return CGPoint(x: 0.72, y: 0.58)
        case .microphoneStand:
            return CGPoint(x: 0.5, y: 0.68)
        case .keyboard:
            return CGPoint(x: 0.5, y: 0.48)
        case .speaker:
            return CGPoint(x: 0.12, y: 0.42)
        }
    }
}

enum RunOfShowStageType: String, CaseIterable, Codable, Identifiable {
    case rectangle = "Rectangle"
    case archedFront = "Rectangle + Arch"
    case round = "Round"

    var id: String { rawValue }
}

struct RunOfShowStagePlotItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var role: RunOfShowStagePlotRole
    var title: String
    var subtitle: String
    var x: Double
    var y: Double
    var rotationDegrees: Double
    var sizeScale: Double
    var position: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case title
        case subtitle
        case x
        case y
        case rotationDegrees
        case sizeScale
        case position
    }

    init(
        id: String = UUID().uuidString,
        role: RunOfShowStagePlotRole = .instrument,
        title: String = "",
        subtitle: String = "",
        x: Double = 0.5,
        y: Double = 0.5,
        rotationDegrees: Double = 0,
        sizeScale: Double = 1,
        position: Int = 0
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.subtitle = subtitle
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.rotationDegrees = rotationDegrees
        self.sizeScale = min(max(sizeScale, 0.6), 1.8)
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try container.decodeIfPresent(RunOfShowStagePlotRole.self, forKey: .role) ?? .instrument
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        x = min(max(try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5, 0), 1)
        y = min(max(try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5, 0), 1)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        sizeScale = min(max(try container.decodeIfPresent(Double.self, forKey: .sizeScale) ?? 1, 0.6), 1.8)
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
    }
}

struct RunOfShowDocument: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var teamCode: String
    var scheduledStart: Date
    var items: [RunOfShowItem]
    var stageType: RunOfShowStageType
    var stagePlotItems: [RunOfShowStagePlotItem]
    var autoStartLive: Bool = false
    var isLiveActive: Bool = false
    var liveCurrentItemID: String?
    var liveShowStartedAt: Date?
    var liveItemStartedAt: Date?
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case teamCode
        case scheduledStart
        case items
        case stageType
        case stagePlotItems
        case autoStartLive
        case isLiveActive
        case liveCurrentItemID
        case liveShowStartedAt
        case liveItemStartedAt
        case updatedAt
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        teamCode: String,
        scheduledStart: Date = Date(),
        items: [RunOfShowItem] = [],
        stageType: RunOfShowStageType = .rectangle,
        stagePlotItems: [RunOfShowStagePlotItem] = [],
        autoStartLive: Bool = false,
        isLiveActive: Bool = false,
        liveCurrentItemID: String? = nil,
        liveShowStartedAt: Date? = nil,
        liveItemStartedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.teamCode = teamCode
        self.scheduledStart = scheduledStart
        self.items = items
        self.stageType = stageType
        self.stagePlotItems = stagePlotItems
        self.autoStartLive = autoStartLive
        self.isLiveActive = isLiveActive
        self.liveCurrentItemID = liveCurrentItemID
        self.liveShowStartedAt = liveShowStartedAt
        self.liveItemStartedAt = liveItemStartedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Run of Show"
        teamCode = try container.decodeIfPresent(String.self, forKey: .teamCode) ?? ""
        scheduledStart = try container.decodeIfPresent(Date.self, forKey: .scheduledStart) ?? Date()
        items = (try container.decodeIfPresent([RunOfShowItem].self, forKey: .items) ?? []).sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        stageType = try container.decodeIfPresent(RunOfShowStageType.self, forKey: .stageType) ?? .rectangle
        stagePlotItems = (try container.decodeIfPresent([RunOfShowStagePlotItem].self, forKey: .stagePlotItems) ?? []).sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        autoStartLive = try container.decodeIfPresent(Bool.self, forKey: .autoStartLive) ?? false
        isLiveActive = try container.decodeIfPresent(Bool.self, forKey: .isLiveActive) ?? false
        liveCurrentItemID = try container.decodeIfPresent(String.self, forKey: .liveCurrentItemID)
        liveShowStartedAt = try container.decodeIfPresent(Date.self, forKey: .liveShowStartedAt)
        liveItemStartedAt = try container.decodeIfPresent(Date.self, forKey: .liveItemStartedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

private func csvEscapedValue(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

private func exportStagePlotItemTitle(_ item: RunOfShowStagePlotItem) -> String {
    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? item.role.defaultTitle : title
}

func runOfShowCSV(for show: RunOfShowDocument) -> String {
    let isoFormatter = ISO8601DateFormatter()
    let header = [
        "Show Title",
        "Scheduled Start",
        "Position",
        "Item Start",
        "Duration",
        "Title",
        "Person",
        "Notes"
    ].map(csvEscapedValue).joined(separator: ",")

    var currentStart = show.scheduledStart
    let rows = show.sortedItems.enumerated().map { index, item in
        defer {
            currentStart = currentStart.addingTimeInterval(TimeInterval(item.durationSeconds))
        }
        return [
            show.title,
            isoFormatter.string(from: show.scheduledStart),
            String(index + 1),
            isoFormatter.string(from: currentStart),
            item.formattedDuration,
            item.title.trimmingCharacters(in: .whitespacesAndNewlines),
            item.person.trimmingCharacters(in: .whitespacesAndNewlines),
            item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ].map(csvEscapedValue).joined(separator: ",")
    }

    return "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
}

func stagePlotCSV(for show: RunOfShowDocument) -> String {
    let header = [
        "Show Title",
        "Stage Type",
        "Position",
        "Role",
        "Title",
        "Subtitle",
        "X",
        "Y",
        "Rotation Degrees",
        "Size Percent"
    ].map(csvEscapedValue).joined(separator: ",")

    let rows = show.sortedStagePlotItems.enumerated().map { index, item in
        [
            show.title,
            show.stageType.rawValue,
            String(index + 1),
            item.role.rawValue,
            exportStagePlotItemTitle(item),
            item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            String(format: "%.4f", item.x),
            String(format: "%.4f", item.y),
            String(format: "%.1f", item.rotationDegrees),
            String(Int((item.sizeScale * 100).rounded()))
        ].map(csvEscapedValue).joined(separator: ",")
    }

    return "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
}

extension RunOfShowDocument {
    var sortedItems: [RunOfShowItem] {
        items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var sortedStagePlotItems: [RunOfShowStagePlotItem] {
        stagePlotItems.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var totalLengthMinutes: Int {
        totalDurationSeconds / 60
    }

    var totalDurationSeconds: Int {
        sortedItems.reduce(0) { $0 + $1.durationSeconds }
    }

    func itemIndex(for itemID: String?) -> Int? {
        guard let itemID else { return nil }
        return sortedItems.firstIndex(where: { $0.id == itemID })
    }

    func currentElapsedSeconds(at now: Date) -> Int {
        guard isLiveActive else { return 0 }
        guard let currentIndex = itemIndex(for: liveCurrentItemID),
              sortedItems.indices.contains(currentIndex) else { return 0 }
        return max(Int(now.timeIntervalSince(liveItemStartedAt ?? now)), 0)
    }

    func currentRemainingSeconds(at now: Date) -> Int {
        guard isLiveActive else { return 0 }
        guard let currentIndex = itemIndex(for: liveCurrentItemID),
              sortedItems.indices.contains(currentIndex) else { return 0 }
        let currentItem = sortedItems[currentIndex]
        return max(currentItem.durationSeconds - currentElapsedSeconds(at: now), 0)
    }

    func currentOverrunSeconds(at now: Date) -> Int {
        guard isLiveActive else { return 0 }
        guard let currentIndex = itemIndex(for: liveCurrentItemID),
              sortedItems.indices.contains(currentIndex) else { return 0 }
        let currentItem = sortedItems[currentIndex]
        return max(currentElapsedSeconds(at: now) - currentItem.durationSeconds, 0)
    }

    func projectedEndTime(at now: Date) -> Date {
        let baseStart = liveShowStartedAt ?? scheduledStart
        let totalScheduledSeconds = totalDurationSeconds
        return baseStart.addingTimeInterval(TimeInterval(totalScheduledSeconds + currentOverrunSeconds(at: now)))
    }
}

extension RunOfShowItem {
    var durationSeconds: Int {
        max(lengthMinutes, 0) * 60 + min(max(lengthSeconds, 0), 59)
    }

    var formattedDuration: String {
        String(format: "%d:%02d", max(lengthMinutes, 0), min(max(lengthSeconds, 0), 59))
    }
}

struct ChecklistSubtask: Identifiable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var isDone: Bool = false
    var completedAt: Date? = nil
    var completedBy: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case isDone
        case completedAt
        case completedBy
    }

    init(
        id: String = UUID().uuidString,
        text: String,
        isDone: Bool = false,
        completedAt: Date? = nil,
        completedBy: String? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
        self.completedBy = completedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decode(String.self, forKey: .text)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
    }
}

struct ChecklistTaskAttachment: Identifiable, Codable {
    var id: String = UUID().uuidString
    var url: String
    var name: String
    var kind: TicketAttachmentKind = .document
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case kind
        case createdAt
    }

    init(
        id: String = UUID().uuidString,
        url: String,
        name: String,
        kind: TicketAttachmentKind = .document,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        url = try container.decode(String.self, forKey: .url)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Attachment"
        kind = try container.decodeIfPresent(TicketAttachmentKind.self, forKey: .kind) ?? .document
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct ChecklistItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var notes: String = ""
    var assignedUserID: String? = nil
    var assignedUserName: String? = nil
    var assignedUserEmail: String? = nil
    var dueDate: Date? = nil
    var subtasks: [ChecklistSubtask] = []
    var attachments: [ChecklistTaskAttachment] = []
    var isDone: Bool = false
    var completedAt: Date? = nil
    var completedBy: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case notes
        case assignedUserID
        case assignedUserName
        case assignedUserEmail
        case dueDate
        case subtasks
        case attachments
        case isDone
        case completedAt
        case completedBy
    }

    init(
        id: String = UUID().uuidString,
        text: String,
        notes: String = "",
        assignedUserID: String? = nil,
        assignedUserName: String? = nil,
        assignedUserEmail: String? = nil,
        dueDate: Date? = nil,
        subtasks: [ChecklistSubtask] = [],
        attachments: [ChecklistTaskAttachment] = [],
        isDone: Bool = false,
        completedAt: Date? = nil,
        completedBy: String? = nil
    ) {
        self.id = id
        self.text = text
        self.notes = notes
        self.assignedUserID = assignedUserID
        self.assignedUserName = assignedUserName
        self.assignedUserEmail = assignedUserEmail
        self.dueDate = dueDate
        self.subtasks = subtasks
        self.attachments = attachments
        self.isDone = isDone
        self.completedAt = completedAt
        self.completedBy = completedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decode(String.self, forKey: .text)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        assignedUserID = try container.decodeIfPresent(String.self, forKey: .assignedUserID)
        assignedUserName = try container.decodeIfPresent(String.self, forKey: .assignedUserName)
        assignedUserEmail = try container.decodeIfPresent(String.self, forKey: .assignedUserEmail)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        subtasks = try container.decodeIfPresent([ChecklistSubtask].self, forKey: .subtasks) ?? []
        attachments = try container.decodeIfPresent([ChecklistTaskAttachment].self, forKey: .attachments) ?? []
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
    }
}

struct ChecklistTemplate: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var teamCode: String
    var position: Int = 0
    var groupName: String = ""
    var assignedUserID: String? = nil
    var assignedUserName: String? = nil
    var assignedUserEmail: String? = nil
    var items: [ChecklistItem] = []
    var createdBy: String? = nil
    var dueDate: Date? = nil
    var completedAt: Date? = nil
    var completedBy: String? = nil
    var archivedAt: Date? = nil
    var archivedBy: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case teamCode
        case position
        case groupName
        case assignedUserID
        case assignedUserName
        case assignedUserEmail
        case items
        case createdBy
        case dueDate
        case completedAt
        case completedBy
        case archivedAt
        case archivedBy
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        teamCode: String,
        position: Int = 0,
        groupName: String = "",
        assignedUserID: String? = nil,
        assignedUserName: String? = nil,
        assignedUserEmail: String? = nil,
        items: [ChecklistItem] = [],
        createdBy: String? = nil,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        completedBy: String? = nil,
        archivedAt: Date? = nil,
        archivedBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.teamCode = teamCode
        self.position = position
        self.groupName = groupName
        self.assignedUserID = assignedUserID
        self.assignedUserName = assignedUserName
        self.assignedUserEmail = assignedUserEmail
        self.items = items
        self.createdBy = createdBy
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.archivedAt = archivedAt
        self.archivedBy = archivedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        teamCode = try container.decode(String.self, forKey: .teamCode)
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        assignedUserID = try container.decodeIfPresent(String.self, forKey: .assignedUserID)
        assignedUserName = try container.decodeIfPresent(String.self, forKey: .assignedUserName)
        assignedUserEmail = try container.decodeIfPresent(String.self, forKey: .assignedUserEmail)
        items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        archivedBy = try container.decodeIfPresent(String.self, forKey: .archivedBy)
    }
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
    var category: String = ""
    var subcategory: String = ""
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
        case category
        case subcategory
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
        category: String = "",
        subcategory: String = "",
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
        self.category = category
        self.subcategory = subcategory
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
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory) ?? ""
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
