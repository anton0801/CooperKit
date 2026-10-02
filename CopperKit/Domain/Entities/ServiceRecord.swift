import Foundation

/// Where a service record came from.
enum ServiceSource: Equatable, Hashable {
    /// Set aside by the owner from the shelf.
    case manual
    /// Came back damaged from a handover.
    case handoverReturn(handoverID: UUID, holder: String)
}

enum ServiceResolutionKind: String, Hashable {
    /// Fixed or checked — the units are Available again.
    case returnedToAvailable
    /// Beyond repair — the units leave the total.
    case writtenOff
}

struct ServiceResolution: Identifiable, Equatable, Hashable {
    let id: UUID
    var kind: ServiceResolutionKind
    var quantity: Int
    var note: String
    var at: Date
}

/// Units set aside at home because they need attention. Needs Service here means
/// "not ready to hand out", not a trip to an outside repair shop.
struct ServiceRecord: Identifiable, Equatable, Hashable {
    let id: UUID
    var toolID: UUID
    var toolNameSnapshot: String
    var quantity: Int
    var issue: String
    var notes: String
    var openedAt: Date
    var source: ServiceSource
    var resolutions: [ServiceResolution]
    var updatedAt: Date

    var resolvedQuantity: Int { resolutions.reduce(0) { $0 + $1.quantity } }
    var openQuantity: Int { max(0, quantity - resolvedQuantity) }
    var isOpen: Bool { openQuantity > 0 }
    var closedAt: Date? { isOpen ? nil : resolutions.map(\.at).max() }
}
