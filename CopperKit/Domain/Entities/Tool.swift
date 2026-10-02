import Foundation

enum ToolCategory: String, CaseIterable, Hashable {
    case powerTool
    case handTool
    case measuring
    case accessory
    case toolCase
    case other
}

/// How the units of one tool record are counted.
///
/// `individual` is a single serialised thing and always has exactly one unit.
/// `identicalUnits` are interchangeable copies sharing one description — different
/// serial numbers mean different records.
enum TrackingMode: String, CaseIterable, Hashable {
    case individual
    case identicalUnits
}

/// What the owner paid for the whole counted batch on the purchase date.
/// Not a unit price and not a current valuation. Absent means Unknown — never zero.
struct PurchaseCost: Equatable, Hashable {
    var amount: Decimal
    var currencyCode: String
}

struct Tool: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var category: ToolCategory
    var trackingMode: TrackingMode
    var homeLocationID: UUID
    var ownLabel: String
    var serialNumber: String
    /// File names of the owner's photos, in display order.
    var photoIDs: [String]
    var notes: String
    var purchaseDate: Date?
    var purchaseCost: PurchaseCost?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isArchived: Bool { archivedAt != nil }
}
