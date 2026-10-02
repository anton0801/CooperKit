#if DEBUG
import Foundation

/// Fills an empty test store with a small workshop for UI tests and screenshots.
/// Compiled into Debug builds only and used only with `-uiTestSeed`; the shipping app
/// always starts empty.
@MainActor
enum DebugSeed {
    static func applyIfRequested(to store: WorkshopStore) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeed"), store.workshop.tools.isEmpty else { return }
        do {
            try seed(store)
        } catch {
            assertionFailure("Seed failed: \(error)")
        }
    }

    private static func seed(_ store: WorkshopStore) throws {
        var place = LocationDraft()
        place.name = "Garage Shelf A"
        place.roomZone = "Garage"
        place.shelfLabel = "Top shelf, left"
        let shelf = try store.locations.create(place)
        place = LocationDraft()
        place.name = "Blue Drawer Case"
        place.roomZone = "Workbench"
        place.shelfLabel = "Drawer 2"
        let drawer = try store.locations.create(place)

        func tool(_ name: String, _ category: ToolCategory, _ mode: TrackingMode, _ quantity: Int,
                  _ location: StorageLocation, label: String = "", serial: String = "", cost: String = "") throws -> Tool {
            var draft = ToolDraft(currencyCode: "EUR")
            draft.name = name
            draft.category = category
            draft.trackingMode = mode
            draft.initialQuantity = quantity
            draft.homeLocationID = location.id
            draft.ownLabel = label
            draft.serialNumber = serial
            draft.cost = CostInput(amountText: cost, currencyCode: "EUR")
            if !cost.isEmpty { draft.purchaseDate = Calendar.current.date(byAdding: .month, value: -14, to: Date()) }
            return try store.tools.create(draft)
        }

        let drill = try tool("Cordless Drill", .powerTool, .individual, 1, shelf, label: "D-01", serial: "CD18-4471", cost: "149.90")
        let clamps = try tool("F-Clamp 300 mm", .handTool, .identicalUnits, 6, shelf, label: "Red handles")
        let square = try tool("Try Square", .measuring, .identicalUnits, 2, drawer)
        _ = try tool("Digital Caliper", .measuring, .individual, 1, drawer, serial: "DC-150-22")
        let bits = try tool("Drill Bit Set", .accessory, .identicalUnits, 3, drawer)
        let sander = try tool("Orbital Sander", .powerTool, .identicalUnits, 1, shelf)
        _ = try tool("Small Tool Case", .toolCase, .identicalUnits, 1, shelf)

        var kit = KitDraft()
        kit.name = "Deck Repair"
        kit.purpose = "Replacing loose boards on the back deck"
        kit.preparationNote = "Charge the drill battery the night before."
        kit.lines = [
            .init(toolID: drill.id, requiredQuantity: 1),
            .init(toolID: clamps.id, requiredQuantity: 4),
            .init(toolID: square.id, requiredQuantity: 1),
            .init(toolID: bits.id, requiredQuantity: 1),
        ]
        try store.kits.save(kit, id: nil)

        let now = Date()
        // A loan recorded after the fact, already past due.
        try store.handovers.checkout(CheckoutRequest(
            operationID: UUID(), mode: .loan, purpose: "Shelf build at Mark's", recipientName: "Mark",
            contactNote: "Flat 4B", startedAt: now.addingTimeInterval(-9 * 86_400), dueAt: now.addingTimeInterval(-2 * 86_400),
            dueTimeZoneID: TimeZone.current.identifier, lines: [.init(toolID: clamps.id, quantity: 3)],
            conditionOutNote: "All clamps tight", preparationSummary: "", kitID: nil, preparationRunID: nil))
        // Personal use, due soon.
        try store.handovers.checkout(CheckoutRequest(
            operationID: UUID(), mode: .personalUse, purpose: "Sanding the garden bench", recipientName: "",
            contactNote: "", startedAt: now.addingTimeInterval(-86_400), dueAt: now.addingTimeInterval(2 * 86_400),
            dueTimeZoneID: TimeZone.current.identifier, lines: [.init(toolID: sander.id, quantity: 1)],
            conditionOutNote: "", preparationSummary: "", kitID: nil, preparationRunID: nil))
        // A loan returned in part, with one damaged unit.
        let partial = try store.handovers.checkout(CheckoutRequest(
            operationID: UUID(), mode: .loan, purpose: "Picture frames", recipientName: "Anna",
            contactNote: "", startedAt: now.addingTimeInterval(-5 * 86_400), dueAt: now.addingTimeInterval(3 * 86_400),
            dueTimeZoneID: TimeZone.current.identifier, lines: [.init(toolID: bits.id, quantity: 2), .init(toolID: square.id, quantity: 1)],
            conditionOutNote: "", preparationSummary: "", kitID: nil, preparationRunID: nil))
        try store.handovers.recordReturn(ReturnRequest(
            operationID: UUID(), handoverID: partial.id, returnedAt: now.addingTimeInterval(-3600), note: "Square still with Anna",
            lines: [.init(lineID: partial.lines[0].id, toAvailable: 1, needsService: 1, issueNote: "Two bits missing from the set")]))
    }
}
#endif
