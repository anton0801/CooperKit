import Foundation

/// Every change to how many units of a tool exist at all. Handovers and service
/// records move units between states; only movements change the total.
enum StockMovementKind: String, CaseIterable, Hashable {
    case initial
    case increase
    case decrease
    case lost
    case writtenOff
    case inventoryGain
    case inventoryLoss

    /// +1 when the movement adds units, −1 when it removes them.
    var sign: Int {
        switch self {
        case .initial, .increase, .inventoryGain: return 1
        case .decrease, .lost, .writtenOff, .inventoryLoss: return -1
        }
    }
}

struct StockMovement: Identifiable, Equatable, Hashable {
    let id: UUID
    var toolID: UUID
    var kind: StockMovementKind
    /// Always positive; the direction comes from `kind`.
    var quantity: Int
    var reason: String
    var at: Date
    var handoverID: UUID?
    var serviceRecordID: UUID?
    var inventoryCheckID: UUID?

    var signedQuantity: Int { kind.sign * quantity }
}

/// One counted line of an inventory check.
struct InventoryCheckLine: Equatable, Hashable {
    var toolID: UUID
    var toolNameSnapshot: String
    /// Available + Needs Service at the moment of the check.
    var expectedAtHome: Int
    var counted: Int

    var variance: Int { counted - expectedAtHome }
}

/// A comparison of what is physically at home against the books. Differences are
/// applied as separate inventory movements; the check itself is kept as a record.
struct InventoryCheck: Identifiable, Equatable, Hashable {
    let id: UUID
    var locationID: UUID?
    var locationNameSnapshot: String
    var performedAt: Date
    var note: String
    var lines: [InventoryCheckLine]
}
