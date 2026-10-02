import Foundation

// The stored format, kept apart from the domain entities so the file can evolve
// without the rules changing. Every field is optional: a document written by an older
// build — or missing a key for any other reason — degrades to defaults in
// `WorkshopMapper` instead of refusing to open.

struct WorkshopDocumentDTO: Codable {
    var schemaVersion: Int?
    var savedAt: Date?
    var tools: [ToolDTO]?
    var locations: [LocationDTO]?
    var kits: [KitDTO]?
    var preparations: [PreparationDTO]?
    var handovers: [HandoverDTO]?
    var serviceRecords: [ServiceDTO]?
    var movements: [MovementDTO]?
    var inventoryChecks: [InventoryCheckDTO]?
    var activity: [ActivityDTO]?
    var settings: SettingsDTO?
}

struct ToolDTO: Codable {
    var id: UUID?
    var name: String?
    var category: String?
    var trackingMode: String?
    var homeLocationID: UUID?
    var ownLabel: String?
    var serialNumber: String?
    var photoIDs: [String]?
    var notes: String?
    var purchaseDate: Date?
    /// Stored as text so a price never picks up binary floating-point noise.
    var costAmount: String?
    var costCurrency: String?
    var archivedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
}

struct LocationDTO: Codable {
    var id: UUID?
    var name: String?
    var roomZone: String?
    var shelfLabel: String?
    var notes: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct KitLineDTO: Codable {
    var id: UUID?
    var toolID: UUID?
    var toolName: String?
    var requiredQuantity: Int?
}

struct KitDTO: Codable {
    var id: UUID?
    var name: String?
    var purpose: String?
    var lines: [KitLineDTO]?
    var preparationNote: String?
    var archivedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
}

struct PreparationLineDTO: Codable {
    var id: UUID?
    var templateToolID: UUID?
    var toolID: UUID?
    var toolName: String?
    var requiredQuantity: Int?
    var runQuantity: Int?
    var isPrepared: Bool?
    var isRemoved: Bool?
}

struct PreparationDTO: Codable {
    var id: UUID?
    var kitID: UUID?
    var title: String?
    var sourceHandoverID: UUID?
    var lines: [PreparationLineDTO]?
    var runNote: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct HandoverLineDTO: Codable {
    var id: UUID?
    var toolID: UUID?
    var toolName: String?
    var quantity: Int?
}

struct ReturnLineDTO: Codable {
    var lineID: UUID?
    var toolID: UUID?
    var returnedToAvailable: Int?
    var needsService: Int?
    var lost: Int?
    var issueNote: String?
}

struct ReturnRecordDTO: Codable {
    var id: UUID?
    var operationID: UUID?
    var returnedAt: Date?
    var recordedAt: Date?
    var note: String?
    var lines: [ReturnLineDTO]?
}

struct HandoverDTO: Codable {
    var id: UUID?
    var operationID: UUID?
    var mode: String?
    var purpose: String?
    var recipientName: String?
    var contactNote: String?
    var startedAt: Date?
    var dueAt: Date?
    var dueTimeZoneID: String?
    var lines: [HandoverLineDTO]?
    var conditionOutNote: String?
    var preparationSummary: String?
    var kitID: UUID?
    var kitName: String?
    var returns: [ReturnRecordDTO]?
    var createdAt: Date?
    var updatedAt: Date?
}

struct ServiceResolutionDTO: Codable {
    var id: UUID?
    var kind: String?
    var quantity: Int?
    var note: String?
    var at: Date?
}

struct ServiceDTO: Codable {
    var id: UUID?
    var toolID: UUID?
    var toolName: String?
    var quantity: Int?
    var issue: String?
    var notes: String?
    var openedAt: Date?
    var sourceKind: String?
    var sourceHandoverID: UUID?
    var sourceHolder: String?
    var resolutions: [ServiceResolutionDTO]?
    var updatedAt: Date?
}

struct MovementDTO: Codable {
    var id: UUID?
    var toolID: UUID?
    var kind: String?
    var quantity: Int?
    var reason: String?
    var at: Date?
    var handoverID: UUID?
    var serviceRecordID: UUID?
    var inventoryCheckID: UUID?
}

struct InventoryLineDTO: Codable {
    var toolID: UUID?
    var toolName: String?
    var expectedAtHome: Int?
    var counted: Int?
}

struct InventoryCheckDTO: Codable {
    var id: UUID?
    var locationID: UUID?
    var locationName: String?
    var performedAt: Date?
    var note: String?
    var lines: [InventoryLineDTO]?
}

struct ActivityDTO: Codable {
    var id: UUID?
    var at: Date?
    var kind: String?
    var title: String?
    var detail: String?
    var toolIDs: [UUID]?
    var handoverID: UUID?
    var serviceRecordID: UUID?
    var locationID: UUID?
    var kitID: UUID?
}

struct SettingsDTO: Codable {
    var defaultLoanDays: Int?
    var defaultCurrencyCode: String?
    var dueRemindersEnabled: Bool?
}
