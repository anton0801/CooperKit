import Foundation

struct LocationDraft: Equatable {
    var name: String = ""
    var roomZone: String = ""
    var shelfLabel: String = ""
    var notes: String = ""

    init() {}

    init(location: StorageLocation) {
        name = location.name
        roomZone = location.roomZone
        shelfLabel = location.shelfLabel
        notes = location.notes
    }
}

final class LocationUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock

    init(repository: WorkshopRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    @discardableResult
    func create(_ draft: LocationDraft) throws -> StorageLocation {
        let now = clock.now
        let fields = try validated(draft)
        return try repository.transact { workshop in
            let location = StorageLocation(
                id: UUID(), name: fields.name, roomZone: fields.roomZone, shelfLabel: fields.shelfLabel,
                notes: fields.notes, createdAt: now, updatedAt: now
            )
            workshop.locations.append(location)
            workshop.log(.locationAdded, at: now, title: "Added location \(location.name)", location: location.id)
            return location
        }
    }

    func update(_ id: UUID, with draft: LocationDraft) throws {
        let now = clock.now
        let fields = try validated(draft)
        try repository.transact { workshop in
            let index = try workshop.locationIndex(id)
            workshop.locations[index].name = fields.name
            workshop.locations[index].roomZone = fields.roomZone
            workshop.locations[index].shelfLabel = fields.shelfLabel
            workshop.locations[index].notes = fields.notes
            workshop.locations[index].updatedAt = now
            workshop.log(.locationEdited, at: now, title: "Edited location \(fields.name)", location: id)
        }
    }

    /// Deletes a location. When tools — archived ones included — still call it home,
    /// a new home must be given for all of them in the same step.
    func delete(_ id: UUID, reassignTo newLocationID: UUID?) throws {
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.locationIndex(id)
            let assigned = workshop.tools.indices.filter { workshop.tools[$0].homeLocationID == id }
            if !assigned.isEmpty {
                guard let newLocationID else {
                    throw DomainError("\(assigned.count == 1 ? "1 tool uses" : "\(assigned.count) tools use") this location. Choose a new Home Location for them first.")
                }
                guard newLocationID != id else { throw DomainError("Choose a different location for these tools.") }
                let target = workshop.locations[try workshop.locationIndex(newLocationID)]
                for toolIndex in assigned {
                    workshop.tools[toolIndex].homeLocationID = newLocationID
                    workshop.tools[toolIndex].updatedAt = now
                    workshop.log(.toolMoved, at: now, title: "Moved \(workshop.tools[toolIndex].name)",
                                 detail: "Home Location: \(target.name)", tools: [workshop.tools[toolIndex].id],
                                 location: newLocationID)
                }
            }
            let removed = workshop.locations.remove(at: index)
            workshop.log(.locationDeleted, at: now, title: "Deleted location \(removed.name)",
                         detail: assigned.isEmpty ? "" : "\(assigned.count) tools reassigned.")
        }
    }

    private func validated(_ draft: LocationDraft) throws -> LocationDraft {
        var result = LocationDraft()
        result.name = try Validate.name(draft.name, field: "Location Name")
        result.roomZone = try Validate.text(draft.roomZone, max: Limits.nameLength.upperBound, field: "Room/Zone")
        result.shelfLabel = try Validate.text(draft.shelfLabel, max: Limits.nameLength.upperBound, field: "Shelf/Box Label")
        result.notes = try Validate.text(draft.notes, max: Limits.notesMax, field: "Notes")
        return result
    }
}
