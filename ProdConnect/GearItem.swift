// GearItem model extracted from ContentView.swift for cross-file usage
import Foundation

struct GearItem: Identifiable, Codable {
        // Restored fields for compatibility with old code
        var notes: String {
            get { maintenanceNotes }
            set { maintenanceNotes = newValue }
        }
    var id: String = UUID().uuidString
    var name: String
    var category: String
    var status: GearStatus = .available
    var teamCode: String
    var purchaseDate: Date?
    var purchasedFrom: String = ""
    var cost: Double?
    var location: String = ""
    var serialNumber: String = ""
    var campus: String = ""
    var assetId: String = ""
    var installDate: Date?
    var maintenanceIssue: String = ""
    var maintenanceCost: Double?
    var maintenanceRepairDate: Date?
    var maintenanceNotes: String = ""
    var imageURL: String?
    var createdBy: String?
    var activeTicketIDs: [String] = []
    var ticketHistory: [GearTicketHistoryEntry] = []

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case status
        case teamCode
        case purchaseDate
        case purchasedFrom
        case cost
        case location
        case serialNumber
        case campus
        case assetId
        case installDate
        case maintenanceIssue
        case maintenanceCost
        case maintenanceRepairDate
        case maintenanceNotes
        case imageURL
        case createdBy
        case activeTicketIDs
        case ticketHistory
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        category: String,
        status: GearStatus = .available,
        teamCode: String,
        purchaseDate: Date? = nil,
        purchasedFrom: String = "",
        cost: Double? = nil,
        location: String = "",
        serialNumber: String = "",
        campus: String = "",
        assetId: String = "",
        installDate: Date? = nil,
        maintenanceIssue: String = "",
        maintenanceCost: Double? = nil,
        maintenanceRepairDate: Date? = nil,
        maintenanceNotes: String = "",
        imageURL: String? = nil,
        createdBy: String? = nil,
        activeTicketIDs: [String] = [],
        ticketHistory: [GearTicketHistoryEntry] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.status = status
        self.teamCode = teamCode
        self.purchaseDate = purchaseDate
        self.purchasedFrom = purchasedFrom
        self.cost = cost
        self.location = location
        self.serialNumber = serialNumber
        self.campus = campus
        self.assetId = assetId
        self.installDate = installDate
        self.maintenanceIssue = maintenanceIssue
        self.maintenanceCost = maintenanceCost
        self.maintenanceRepairDate = maintenanceRepairDate
        self.maintenanceNotes = maintenanceNotes
        self.imageURL = imageURL
        self.createdBy = createdBy
        self.activeTicketIDs = activeTicketIDs
        self.ticketHistory = ticketHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        status = try container.decodeIfPresent(GearStatus.self, forKey: .status) ?? .available
        teamCode = try container.decodeIfPresent(String.self, forKey: .teamCode) ?? ""
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
        purchasedFrom = try container.decodeIfPresent(String.self, forKey: .purchasedFrom) ?? ""
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? ""
        campus = try container.decodeIfPresent(String.self, forKey: .campus) ?? ""
        assetId = try container.decodeIfPresent(String.self, forKey: .assetId) ?? ""
        installDate = try container.decodeIfPresent(Date.self, forKey: .installDate)
        maintenanceIssue = try container.decodeIfPresent(String.self, forKey: .maintenanceIssue) ?? ""
        maintenanceCost = try container.decodeIfPresent(Double.self, forKey: .maintenanceCost)
        maintenanceRepairDate = try container.decodeIfPresent(Date.self, forKey: .maintenanceRepairDate)
        maintenanceNotes = try container.decodeIfPresent(String.self, forKey: .maintenanceNotes) ?? ""
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        activeTicketIDs = try container.decodeIfPresent([String].self, forKey: .activeTicketIDs) ?? []
        ticketHistory = try container.decodeIfPresent([GearTicketHistoryEntry].self, forKey: .ticketHistory) ?? []
    }

    enum GearStatus: String, Codable, CaseIterable {
        case available = "In Stock"
        case inUse = "In Use"
        case needsRepair = "Needs Repair"
        case retired = "Retired"
        case missing = "Missing"
        case checkedOut = "Checked Out"
        case maintenance = "Maintenance"
        case lost = "Lost"
        case unknown = "Unknown"
        case blank = ""
    }
}
