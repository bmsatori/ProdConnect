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
