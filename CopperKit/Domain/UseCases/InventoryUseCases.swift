import Foundation

/// One row of a count in progress.
struct InventoryCountRow: Identifiable, Equatable {
    var tool: Tool
    /// Available + Needs Service — what the books say is physically at home.
    var expectedAtHome: Int
    var out: Int

    var id: UUID { tool.id }
}

final class InventoryUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock

    init(repository: WorkshopRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    /// The tools to count at a location (all locations when nil). Archived tools are
    /// included only while something of them is still recorded at home.
    func rows(locationID: UUID?) -> [InventoryCountRow] {
        let workshop = repository.workshop
        let balances = StockLedger.balances(workshop)
        var rows: [InventoryCountRow] = []
        for tool in workshop.tools where locationID == nil || tool.homeLocationID == locationID {
            let balance = balances[tool.id] ?? .zero
            if tool.isArchived && balance.atHome == 0 { continue }
            rows.append(InventoryCountRow(tool: tool, expectedAtHome: balance.atHome, out: balance.out))
        }
        return rows.sorted { $0.tool.name.localizedCaseInsensitiveCompare($1.tool.name) == .orderedAscending }
    }

    /// Applies a count. Only tools with an entered count are touched; each difference
    /// becomes its own inventory movement, and the check is kept as a record.
    @discardableResult
    func apply(locationID: UUID?, counts: [UUID: Int], note: String) throws -> InventoryCheck {
        let now = clock.now
        let note = try Validate.text(note, max: Limits.notesMax, field: "Note")
        guard !counts.isEmpty else { throw DomainError("Count at least one tool before applying.") }

        return try repository.transact { workshop in
            let balances = StockLedger.balances(workshop)
            let place = locationID.flatMap { workshop.location($0) }
            if locationID != nil && place == nil { throw DomainError.locationMissing }

            var lines: [InventoryCheckLine] = []
            let checkID = UUID()
            for (toolID, counted) in counts.sorted(by: { workshop.toolName($0.key) < workshop.toolName($1.key) }) {
                guard let tool = workshop.tool(toolID) else { throw DomainError.toolMissing }
                guard counted >= 0, counted <= Limits.quantity.upperBound else {
                    throw DomainError("\(tool.name): enter a count from 0 to \(Limits.quantity.upperBound).")
                }
                let balance = balances[toolID] ?? .zero
                let variance = counted - balance.atHome
                if variance > 0 {
                    if tool.trackingMode == .individual && balance.total + variance > 1 {
                        throw DomainError("\(tool.name) is recorded as out. If it is actually home, record its return instead of counting it.")
                    }
                    workshop.movements.append(StockMovement(id: UUID(), toolID: toolID, kind: .inventoryGain,
                                                            quantity: variance, reason: "Inventory Check", at: now,
                                                            inventoryCheckID: checkID))
                } else if variance < 0 {
                    let missing = -variance
                    guard missing <= balance.available else {
                        throw DomainError("\(tool.name): \(missing) fewer than expected, but only \(balance.available) Available can be reduced. Resolve its service record first.")
                    }
                    workshop.movements.append(StockMovement(id: UUID(), toolID: toolID, kind: .inventoryLoss,
                                                            quantity: missing, reason: "Inventory Check", at: now,
                                                            inventoryCheckID: checkID))
                }
                lines.append(InventoryCheckLine(toolID: toolID, toolNameSnapshot: tool.name,
                                                expectedAtHome: balance.atHome, counted: counted))
            }

            let check = InventoryCheck(id: checkID, locationID: locationID,
                                       locationNameSnapshot: place?.name ?? "All Locations",
                                       performedAt: now, note: note, lines: lines)
            workshop.inventoryChecks.append(check)
            let changed = lines.filter { $0.variance != 0 }
            workshop.log(.inventoryApplied, at: now, title: "Inventory Check · \(check.locationNameSnapshot)",
                         detail: changed.isEmpty
                            ? "\(lines.count) counted · no differences"
                            : "\(lines.count) counted · \(changed.count) adjusted",
                         tools: changed.map(\.toolID), location: locationID)
            return check
        }
    }
}
