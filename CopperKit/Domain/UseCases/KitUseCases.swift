import Foundation

struct KitDraft: Equatable {
    struct Line: Identifiable, Equatable {
        var id: UUID = UUID()
        var toolID: UUID
        var requiredQuantity: Int
    }

    var name: String = ""
    var purpose: String = ""
    var preparationNote: String = ""
    var lines: [Line] = []

    init() {}

    init(kit: KitTemplate) {
        name = kit.name
        purpose = kit.purpose
        preparationNote = kit.preparationNote
        lines = kit.lines.map { Line(id: $0.id, toolID: $0.toolID, requiredQuantity: $0.requiredQuantity) }
    }

    func contains(_ toolID: UUID) -> Bool { lines.contains { $0.toolID == toolID } }
}

/// Why a kit line cannot be trusted as written.
enum KitLineIssue: Equatable {
    case missingTool
    case archivedTool

    var text: String {
        switch self {
        case .missingTool: return "Tool removed — Needs Review"
        case .archivedTool: return "Tool archived — Needs Review"
        }
    }
}

enum KitRules {
    static func issue(for line: KitLine, in workshop: Workshop) -> KitLineIssue? {
        guard let tool = workshop.tool(line.toolID) else { return .missingTool }
        return tool.isArchived ? .archivedTool : nil
    }

    static func needsReview(_ kit: KitTemplate, in workshop: Workshop) -> Bool {
        kit.lines.contains { issue(for: $0, in: workshop) != nil }
    }
}

final class KitUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock

    init(repository: WorkshopRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    /// Creates a kit (id nil) or replaces an existing one's fields and lines.
    @discardableResult
    func save(_ draft: KitDraft, id: UUID?) throws -> KitTemplate {
        let now = clock.now
        let name = try Validate.name(draft.name, field: "Kit Name")
        let purpose = try Validate.text(draft.purpose, max: Limits.purposeMax, field: "Purpose")
        let note = try Validate.text(draft.preparationNote, max: Limits.notesMax, field: "Preparation Note")
        guard Limits.kitLines.contains(draft.lines.count) else {
            throw DomainError(draft.lines.isEmpty
                ? "Add at least one tool to the kit."
                : "A kit can hold up to \(Limits.kitLines.upperBound) different tools.")
        }
        var seen = Set<UUID>()
        for line in draft.lines {
            guard seen.insert(line.toolID).inserted else {
                throw DomainError("Each tool can appear once in a kit. Change its quantity instead.")
            }
            _ = try Validate.quantity(line.requiredQuantity, field: "Required Quantity")
        }

        return try repository.transact { workshop in
            let previous = id.flatMap { workshop.kit($0) }
            if id != nil && previous == nil { throw DomainError.kitMissing }
            let previousTools = Set(previous?.lines.map(\.toolID) ?? [])

            let lines: [KitLine] = try draft.lines.map { line in
                let tool = workshop.tool(line.toolID)
                // New lines must point at active tools; lines already in the kit may stay
                // as they are and show Needs Review.
                if !previousTools.contains(line.toolID) {
                    guard let tool else { throw DomainError.toolMissing }
                    if tool.isArchived { throw DomainError("\(tool.name) is archived and cannot be added to a kit.") }
                }
                let snapshot = tool?.name ?? previous?.lines.first { $0.toolID == line.toolID }?.toolNameSnapshot ?? "Removed Tool"
                return KitLine(id: line.id, toolID: line.toolID, toolNameSnapshot: snapshot, requiredQuantity: line.requiredQuantity)
            }

            let kit: KitTemplate
            if let previous, let index = workshop.kits.firstIndex(where: { $0.id == previous.id }) {
                var updated = previous
                updated.name = name
                updated.purpose = purpose
                updated.preparationNote = note
                updated.lines = lines
                updated.updatedAt = now
                workshop.kits[index] = updated
                kit = updated
            } else {
                kit = KitTemplate(id: UUID(), name: name, purpose: purpose, lines: lines, preparationNote: note,
                                  archivedAt: nil, createdAt: now, updatedAt: now)
                workshop.kits.append(kit)
            }
            workshop.log(.kitSaved, at: now, title: "Saved kit \(kit.name)",
                         detail: "\(lines.count) \(lines.count == 1 ? "tool" : "tools")", kit: kit.id)
            return kit
        }
    }

    /// Copies the needs only — no preparation marks and no history.
    @discardableResult
    func duplicate(_ id: UUID) throws -> KitTemplate {
        let now = clock.now
        return try repository.transact { workshop in
            let source = workshop.kits[try workshop.kitIndex(id)]
            let baseName = "\(source.name) Copy"
            let copy = KitTemplate(
                id: UUID(), name: String(baseName.prefix(Limits.nameLength.upperBound)), purpose: source.purpose,
                lines: source.lines.map { KitLine(id: UUID(), toolID: $0.toolID, toolNameSnapshot: $0.toolNameSnapshot, requiredQuantity: $0.requiredQuantity) },
                preparationNote: source.preparationNote, archivedAt: nil, createdAt: now, updatedAt: now
            )
            workshop.kits.append(copy)
            workshop.log(.kitSaved, at: now, title: "Duplicated kit \(source.name)", kit: copy.id)
            return copy
        }
    }

    func setArchived(_ id: UUID, _ archived: Bool) throws {
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.kitIndex(id)
            workshop.kits[index].archivedAt = archived ? now : nil
            workshop.kits[index].updatedAt = now
            workshop.log(archived ? .kitArchived : .kitRestored, at: now,
                         title: "\(archived ? "Archived" : "Restored") kit \(workshop.kits[index].name)", kit: id)
        }
    }

    /// Deletes the template and its unsaved preparation. Past handovers keep their own
    /// copies of the kit name and lines.
    func delete(_ id: UUID) throws {
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.kitIndex(id)
            let kit = workshop.kits.remove(at: index)
            workshop.preparations.removeAll { $0.kitID == id }
            workshop.log(.kitDeleted, at: now, title: "Deleted kit \(kit.name)", detail: "Past handovers are kept.")
        }
    }
}
