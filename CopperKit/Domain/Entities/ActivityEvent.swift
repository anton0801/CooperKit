import Foundation

enum ActivityKind: String, CaseIterable, Hashable {
    case toolAdded
    case toolEdited
    case stockAdjusted
    case toolMoved
    case toolArchived
    case toolRestored
    case toolDeleted
    case checkout
    case returned
    case lost
    case dueChanged
    case serviceOpened
    case serviceResolved
    case inventoryApplied
    case locationAdded
    case locationEdited
    case locationDeleted
    case kitSaved
    case kitArchived
    case kitRestored
    case kitDeleted

    var group: ActivityGroup {
        switch self {
        case .toolAdded, .toolEdited, .toolMoved, .toolArchived, .toolRestored, .toolDeleted: return .tools
        case .stockAdjusted, .inventoryApplied, .lost: return .stock
        case .checkout, .returned, .dueChanged: return .handovers
        case .serviceOpened, .serviceResolved: return .service
        case .locationAdded, .locationEdited, .locationDeleted: return .storage
        case .kitSaved, .kitArchived, .kitRestored, .kitDeleted: return .kits
        }
    }
}

enum ActivityGroup: String, CaseIterable, Hashable {
    case handovers
    case service
    case stock
    case tools
    case storage
    case kits
}

/// One line of the workshop history. Written in the same transaction as the change it
/// describes, with names captured at that moment so it still reads correctly after a
/// rename or a deletion.
struct ActivityEvent: Identifiable, Equatable, Hashable {
    let id: UUID
    var at: Date
    var kind: ActivityKind
    var title: String
    var detail: String
    var toolIDs: [UUID]
    var handoverID: UUID?
    var serviceRecordID: UUID?
    var locationID: UUID?
    var kitID: UUID?
}
