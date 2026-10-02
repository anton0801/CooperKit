import Foundation

/// A place at home where a tool record's units live when they are not out.
/// Each tool has exactly one home location; units are not split across shelves.
struct StorageLocation: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var roomZone: String
    var shelfLabel: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}
