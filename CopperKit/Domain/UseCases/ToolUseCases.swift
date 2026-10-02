import Foundation

/// Everything the Tool Editor collects.
struct ToolDraft: Equatable {
    var name: String = ""
    var category: ToolCategory = .handTool
    var trackingMode: TrackingMode = .individual
    /// Used only when creating; an existing quantity changes through Adjust Stock.
    var initialQuantity: Int = 1
    var homeLocationID: UUID?
    var ownLabel: String = ""
    var serialNumber: String = ""
    var photoIDs: [String] = []
    var notes: String = ""
    var purchaseDate: Date?
    var cost: CostInput

    init(currencyCode: String) {
        cost = CostInput(currencyCode: currencyCode)
    }

    init(tool: Tool, fallbackCurrency: String) {
        name = tool.name
        category = tool.category
        trackingMode = tool.trackingMode
        homeLocationID = tool.homeLocationID
        ownLabel = tool.ownLabel
        serialNumber = tool.serialNumber
        photoIDs = tool.photoIDs
        notes = tool.notes
        purchaseDate = tool.purchaseDate
        cost = CostInput(cost: tool.purchaseCost, fallbackCurrency: fallbackCurrency)
        initialQuantity = 1
    }

    /// Duplicate Description: the shared description of a tool, without what makes the
    /// original one individual thing (serial, own label, photos, cost).
    func duplicatedDescription() -> ToolDraft {
        var copy = self
        copy.serialNumber = ""
        copy.ownLabel = ""
        copy.photoIDs = []
        copy.purchaseDate = nil
        copy.cost = CostInput(currencyCode: cost.currencyCode)
        copy.initialQuantity = 1
        return copy
    }
}

enum StockAdjustmentDirection: String, CaseIterable, Hashable {
    case increase
    case decrease
}

final class ToolUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock
    private let locale: Locale

    init(repository: WorkshopRepository, clock: Clock, locale: Locale = .current) {
        self.repository = repository
        self.clock = clock
        self.locale = locale
    }

    @discardableResult
    func create(_ draft: ToolDraft) throws -> Tool {
        let now = clock.now
        let fields = try validated(draft, existing: nil)
        let quantity = draft.trackingMode == .individual ? 1 : try Validate.quantity(draft.initialQuantity, field: "Initial Quantity")

        return try repository.transact { workshop in
            _ = try workshop.locationIndex(fields.locationID)
            let tool = Tool(
                id: UUID(), name: fields.name, category: draft.category, trackingMode: draft.trackingMode,
                homeLocationID: fields.locationID, ownLabel: fields.ownLabel, serialNumber: fields.serial,
                photoIDs: fields.photos, notes: fields.notes, purchaseDate: draft.purchaseDate,
                purchaseCost: fields.cost, archivedAt: nil, createdAt: now, updatedAt: now
            )
            workshop.tools.append(tool)
            workshop.movements.append(StockMovement(
                id: UUID(), toolID: tool.id, kind: .initial, quantity: quantity,
                reason: "Initial quantity", at: now
            ))
            let place = workshop.location(fields.locationID)?.name ?? ""
            workshop.log(.toolAdded, at: now, title: "Added \(tool.name)",
                         detail: "\(StockLedger.unitWord(quantity)) · \(place)", tools: [tool.id])
            return tool
        }
    }

    @discardableResult
    func update(_ id: UUID, with draft: ToolDraft) throws -> Tool {
        let now = clock.now
        return try repository.transact { workshop in
            let index = try workshop.toolIndex(id)
            let old = workshop.tools[index]
            let fields = try validated(draft, existing: old)
            _ = try workshop.locationIndex(fields.locationID)

            if draft.trackingMode != old.trackingMode {
                if StockLedger.hasMovements(toolID: id, in: workshop) {
                    throw DomainError("Tracking Mode cannot change after the tool has been checked out, serviced or adjusted. Create a new record instead.")
                }
                let total = StockLedger.balance(of: id, in: workshop).total
                if draft.trackingMode == .individual && total > 1 {
                    throw DomainError("Individual tracking always means one unit. This record has \(total) units — use a separate record for each serial number.")
                }
            }

            var tool = old
            tool.name = fields.name
            tool.category = draft.category
            tool.trackingMode = draft.trackingMode
            tool.ownLabel = fields.ownLabel
            tool.serialNumber = fields.serial
            tool.photoIDs = fields.photos
            tool.notes = fields.notes
            tool.purchaseDate = draft.purchaseDate
            tool.purchaseCost = fields.cost
            tool.updatedAt = now
            let moved = tool.homeLocationID != fields.locationID
            tool.homeLocationID = fields.locationID
            workshop.tools[index] = tool

            workshop.log(.toolEdited, at: now, title: "Edited \(tool.name)", tools: [id])
            if moved {
                workshop.log(.toolMoved, at: now, title: "Moved \(tool.name)",
                             detail: "Home Location: \(workshop.location(fields.locationID)?.name ?? "")", tools: [id],
                             location: fields.locationID)
            }
            return tool
        }
    }

    /// Adjust Stock: a positive quantity with a reason, recorded as its own event.
    /// A decrease can only take Available units — handed-out units cannot vanish here.
    func adjustStock(toolID: UUID, direction: StockAdjustmentDirection, quantity: Int, reason: String) throws {
        let now = clock.now
        let quantity = try Validate.quantity(quantity)
        let reason = try Validate.required(reason, max: Limits.reasonMax, field: "Reason")
        try repository.transact { workshop in
            let tool = workshop.tools[try workshop.toolIndex(toolID)]
            let balance = StockLedger.balance(of: toolID, in: workshop)
            switch direction {
            case .increase:
                if tool.trackingMode == .individual && balance.total + quantity > 1 {
                    throw DomainError("An individual tool is always one unit. Add identical units as their own record.")
                }
                if tool.isArchived { throw DomainError("Restore this tool before adding units.") }
            case .decrease:
                guard quantity <= balance.available else {
                    throw DomainError(balance.available == 0
                        ? "No units are Available to remove. Units that are out or in service must be returned or resolved first."
                        : "Only \(StockLedger.unitWord(balance.available)) Available to remove. Units that are out or in service cannot be removed here.")
                }
            }
            workshop.movements.append(StockMovement(
                id: UUID(), toolID: toolID, kind: direction == .increase ? .increase : .decrease,
                quantity: quantity, reason: reason, at: now
            ))
            let sign = direction == .increase ? "+" : "−"
            workshop.log(.stockAdjusted, at: now, title: "\(tool.name) \(sign)\(quantity)",
                         detail: reason, tools: [toolID])
        }
    }

    /// Changes the home of the given tools. Units at home move with the record; units
    /// that are out keep their handover and come back to the new place.
    func moveHome(_ toolIDs: [UUID], to locationID: UUID) throws {
        guard !toolIDs.isEmpty else { throw DomainError("Select at least one tool to move.") }
        let now = clock.now
        try repository.transact { workshop in
            let place = workshop.locations[try workshop.locationIndex(locationID)]
            for id in toolIDs {
                let index = try workshop.toolIndex(id)
                guard workshop.tools[index].homeLocationID != locationID else { continue }
                workshop.tools[index].homeLocationID = locationID
                workshop.tools[index].updatedAt = now
                workshop.log(.toolMoved, at: now, title: "Moved \(workshop.tools[index].name)",
                             detail: "Home Location: \(place.name)", tools: [id], location: locationID)
            }
        }
    }

    func archive(_ id: UUID) throws {
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.toolIndex(id)
            let blockers = StockLedger.archiveBlockers(toolID: id, in: workshop, now: now)
            guard blockers.isEmpty else { throw DomainError(blockers.joined(separator: "\n")) }
            workshop.tools[index].archivedAt = now
            workshop.tools[index].updatedAt = now
            workshop.log(.toolArchived, at: now, title: "Archived \(workshop.tools[index].name)", tools: [id])
        }
    }

    func restore(_ id: UUID) throws {
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.toolIndex(id)
            _ = try workshop.locationIndex(workshop.tools[index].homeLocationID)
            workshop.tools[index].archivedAt = nil
            workshop.tools[index].updatedAt = now
            workshop.log(.toolRestored, at: now, title: "Restored \(workshop.tools[index].name)", tools: [id])
        }
    }

    /// Deletes a record that has no history. Returns the photo ids to remove from disk.
    /// A tool with movements must be archived instead; its history is kept.
    @discardableResult
    func delete(_ id: UUID) throws -> [String] {
        let now = clock.now
        return try repository.transact { workshop in
            let index = try workshop.toolIndex(id)
            if StockLedger.hasMovements(toolID: id, in: workshop) {
                throw DomainError("This tool has handovers, service or stock changes in its history. Archive it instead — the history is kept.")
            }
            let tool = workshop.tools.remove(at: index)
            workshop.movements.removeAll { $0.toolID == id }
            workshop.log(.toolDeleted, at: now, title: "Deleted \(tool.name)", detail: "Record had no history.")
            return tool.photoIDs
        }
    }

    // MARK: - Validation

    private struct Fields {
        var name: String
        var locationID: UUID
        var ownLabel: String
        var serial: String
        var photos: [String]
        var notes: String
        var cost: PurchaseCost?
    }

    private func validated(_ draft: ToolDraft, existing: Tool?) throws -> Fields {
        let name = try Validate.name(draft.name)
        guard let locationID = draft.homeLocationID else {
            throw DomainError("Choose a Home Location, or create one first.")
        }
        let ownLabel = try Validate.text(draft.ownLabel, max: Limits.labelMax, field: "Own Label")
        let serial = try Validate.text(draft.serialNumber, max: Limits.serialMax, field: "Serial Number")
        let notes = try Validate.text(draft.notes, max: Limits.notesMax, field: "Notes")
        guard draft.photoIDs.count <= Limits.photosMax else {
            throw DomainError("A tool can have up to \(Limits.photosMax) photos.")
        }
        if let date = draft.purchaseDate, date > clock.now {
            throw DomainError("Purchase Date cannot be in the future.")
        }
        if existing == nil, draft.trackingMode == .identicalUnits {
            _ = try Validate.quantity(draft.initialQuantity, field: "Initial Quantity")
        }
        let cost = try CostRules.parse(draft.cost, locale: locale)
        return Fields(name: name, locationID: locationID, ownLabel: ownLabel, serial: serial,
                      photos: draft.photoIDs, notes: notes, cost: cost)
    }
}
