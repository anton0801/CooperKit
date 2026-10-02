import XCTest
@testable import CopperKit

final class KitCostAndStorageTests: XCTestCase {
    private var h: Harness!

    override func setUp() {
        super.setUp()
        h = Harness()
    }

    // MARK: - Kits

    private func kit(_ lines: [(UUID, Int)], name: String = "Deck Repair") throws -> KitTemplate {
        var draft = KitDraft()
        draft.name = name
        draft.lines = lines.map { .init(toolID: $0.0, requiredQuantity: $0.1) }
        return try h.kits.save(draft, id: nil)
    }

    func testKitRejectsDuplicateToolsAndEmptyLists() throws {
        let drill = try h.tool("Drill", quantity: 2)
        XCTAssertThrowsError(try kit([]))
        XCTAssertThrowsError(try kit([(drill.id, 1), (drill.id, 2)]))
        XCTAssertNoThrow(try kit([(drill.id, 2)]))
    }

    func testArchivedToolCannotJoinANewKitButExistingLineNeedsReview() throws {
        let drill = try h.tool("Drill")
        let old = try h.tool("Old Saw")
        let template = try kit([(drill.id, 1), (old.id, 1)])
        try h.tools.archive(old.id)
        XCTAssertTrue(KitRules.needsReview(h.workshop.kit(template.id)!, in: h.workshop))
        // Re-saving the kit with the archived line kept is allowed …
        XCTAssertNoThrow(try h.kits.save(KitDraft(kit: h.workshop.kit(template.id)!), id: template.id))
        // … but a new kit cannot pick the archived tool.
        XCTAssertThrowsError(try kit([(old.id, 1)], name: "Other"))
    }

    func testDuplicateCopiesNeedsOnly() throws {
        let drill = try h.tool("Drill", quantity: 3)
        let template = try kit([(drill.id, 2)])
        var run = try h.preparation.run(forKit: template.id)
        run.setPrepared(run.lines[0].id, true)
        try h.preparation.save(run)
        let copy = try h.kits.duplicate(template.id)
        XCTAssertEqual(copy.name, "Deck Repair Copy")
        XCTAssertEqual(copy.lines.map(\.requiredQuantity), [2])
        XCTAssertNotEqual(copy.lines[0].id, template.lines[0].id)
        XCTAssertFalse(h.workshop.preparations.contains { $0.kitID == copy.id })
    }

    func testDeletingAKitKeepsPastHandovers() throws {
        let drill = try h.tool("Drill", quantity: 3)
        let template = try kit([(drill.id, 1)])
        var request = h.checkoutRequest([(drill.id, 1)])
        request.kitID = template.id
        try h.handovers.checkout(request)
        try h.kits.delete(template.id)
        XCTAssertEqual(h.workshop.handovers[0].kitNameSnapshot, "Deck Repair")
        XCTAssertEqual(h.workshop.handovers[0].lines[0].toolNameSnapshot, "Drill")
    }

    // MARK: - Preparation

    func testPreparationNeverReservesAndReviewsWhenStockMoves() throws {
        let drill = try h.tool("Drill", quantity: 2)
        let clamp = try h.tool("Clamp", quantity: 1)
        let template = try kit([(drill.id, 2), (clamp.id, 1)])
        var run = try h.preparation.run(forKit: template.id)
        run.setPrepared(run.lines[0].id, true)
        run.setPrepared(run.lines[1].id, true)
        try h.preparation.save(run)
        XCTAssertEqual(h.balance(drill.id).available, 2, "preparing reserves nothing")

        var evaluation = PreparationRules.evaluate(run, in: h.workshop, balances: StockLedger.balances(h.workshop))
        XCTAssertTrue(evaluation.canCheckout)
        XCTAssertEqual(evaluation.preparedCount, 2)

        // Someone else takes a drill: the prepared line loses Ready.
        try h.handovers.checkout(h.checkoutRequest([(drill.id, 1)]))
        evaluation = PreparationRules.evaluate(run, in: h.workshop, balances: StockLedger.balances(h.workshop))
        guard case .needsReview = evaluation.lines[0].state else { return XCTFail("expected Needs Review") }
        XCTAssertFalse(evaluation.canCheckout)
        XCTAssertEqual(evaluation.preparedCount, 1)

        // Reduce for this run only: the template keeps asking for two.
        try run.setQuantity(run.lines[0].id, 1)
        evaluation = PreparationRules.evaluate(run, in: h.workshop, balances: StockLedger.balances(h.workshop))
        XCTAssertTrue(evaluation.canCheckout)
        XCTAssertEqual(h.workshop.kit(template.id)?.lines[0].requiredQuantity, 2)
    }

    func testShortLinesBlockAndEmptyRunCannotCheckout() throws {
        let drill = try h.tool("Drill", quantity: 1)
        let template = try kit([(drill.id, 3)])
        var run = try h.preparation.run(forKit: template.id)
        var evaluation = PreparationRules.evaluate(run, in: h.workshop, balances: StockLedger.balances(h.workshop))
        XCTAssertEqual(evaluation.lines[0].state, .short(missing: 2))
        XCTAssertFalse(evaluation.canCheckout)
        try run.setRemoved(run.lines[0].id, true)
        evaluation = PreparationRules.evaluate(run, in: h.workshop, balances: StockLedger.balances(h.workshop))
        XCTAssertFalse(evaluation.canCheckout)
        XCTAssertNotNil(evaluation.blockingReason)
    }

    func testReplacementIsForThisRunUntilTemplateIsUpdated() throws {
        let drill = try h.tool("Drill")
        let spare = try h.tool("Spare Drill")
        let template = try kit([(drill.id, 1)])
        var run = try h.preparation.run(forKit: template.id)
        try run.replace(run.lines[0].id, with: spare)
        XCTAssertTrue(run.lines[0].isReplacement)
        XCTAssertEqual(h.workshop.kit(template.id)?.lines[0].toolID, drill.id)
        try h.preparation.updateTemplate(from: run)
        XCTAssertEqual(h.workshop.kit(template.id)?.lines[0].toolID, spare.id)
    }

    func testCheckoutConsumesTheSavedPreparation() throws {
        let drill = try h.tool("Drill", quantity: 2)
        let template = try kit([(drill.id, 1)])
        let run = try h.preparation.run(forKit: template.id)
        try h.preparation.save(run)
        var request = h.checkoutRequest([(drill.id, 1)])
        request.kitID = template.id
        request.preparationRunID = run.id
        try h.handovers.checkout(request)
        XCTAssertTrue(h.workshop.preparations.isEmpty)
    }

    func testRepeatCopiesNeedsNotDatesOrMarks() throws {
        let drill = try h.tool("Drill", quantity: 3)
        let handover = try h.handovers.checkout(h.checkoutRequest([(drill.id, 2)]))
        try h.handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id, returnedAt: h.clock.now,
                                                   note: "", lines: [.init(lineID: handover.lines[0].id, toAvailable: 2)]))
        let run = try h.preparation.repeatRun(ofHandover: handover.id)
        XCTAssertEqual(run.lines.map(\.runQuantity), [2])
        XCTAssertFalse(run.lines[0].isPrepared)
        XCTAssertEqual(run.sourceHandoverID, handover.id)
    }

    // MARK: - Cost

    func testCostUnknownZeroAndParsing() throws {
        let locale = Locale(identifier: "en_US")
        XCTAssertNil(try CostRules.parse(CostInput(amountText: "", currencyCode: "EUR"), locale: locale))
        XCTAssertThrowsError(try CostRules.parse(CostInput(amountText: "0", currencyCode: "EUR"), locale: locale))
        XCTAssertEqual(try CostRules.parse(CostInput(amountText: "", currencyCode: "EUR", zeroConfirmed: true), locale: locale)?.amount, 0)
        XCTAssertEqual(try CostRules.parse(CostInput(amountText: "129,90", currencyCode: "eur"), locale: locale),
                       PurchaseCost(amount: Decimal(string: "129.9")!, currencyCode: "EUR"))
        XCTAssertEqual(try CostRules.parse(CostInput(amountText: "1,299.50", currencyCode: "USD"), locale: locale)?.amount,
                       Decimal(string: "1299.5"))
        XCTAssertThrowsError(try CostRules.parse(CostInput(amountText: "12.345", currencyCode: "EUR"), locale: locale))
        XCTAssertThrowsError(try CostRules.parse(CostInput(amountText: "-5", currencyCode: "EUR"), locale: locale))
        XCTAssertThrowsError(try CostRules.parse(CostInput(amountText: "abc", currencyCode: "EUR"), locale: locale))
        XCTAssertThrowsError(try CostRules.parse(CostInput(amountText: "10", currencyCode: "EURO"), locale: locale))
    }

    // MARK: - Persistence

    private func temporaryPaths() -> StoragePaths {
        StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ck-test-\(UUID().uuidString)"))
    }

    func testFileRepositoryRoundTrip() throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_790_000_000))
        let repository = FileWorkshopRepository(paths: paths, clock: clock)
        let tools = ToolUseCases(repository: repository, clock: clock)
        let locations = LocationUseCases(repository: repository, clock: clock)
        let handovers = HandoverUseCases(repository: repository, clock: clock)
        var place = LocationDraft()
        place.name = "Shelf"
        let shelf = try locations.create(place)
        var draft = ToolDraft(currencyCode: "EUR")
        draft.name = "Drill"
        draft.trackingMode = .identicalUnits
        draft.initialQuantity = 3
        draft.homeLocationID = shelf.id
        draft.cost = CostInput(amountText: "199.99", currencyCode: "EUR")
        let drill = try tools.create(draft)
        let handover = try handovers.checkout(CheckoutRequest(
            operationID: UUID(), mode: .loan, purpose: "Loan", recipientName: "Anna", contactNote: "",
            startedAt: clock.now, dueAt: clock.now.addingTimeInterval(86_400), dueTimeZoneID: "Europe/Berlin",
            lines: [.init(toolID: drill.id, quantity: 2)], conditionOutNote: "", preparationSummary: "",
            kitID: nil, preparationRunID: nil))
        try handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id, returnedAt: clock.now, note: "",
                                                 lines: [.init(lineID: handover.lines[0].id, toAvailable: 1, needsService: 1, issueNote: "Chuck")]))

        let reopened = FileWorkshopRepository(paths: paths, clock: clock)
        XCTAssertNil(reopened.loadProblem)
        XCTAssertEqual(reopened.workshop, repository.workshop)
        XCTAssertEqual(reopened.workshop.tools[0].purchaseCost?.amount, Decimal(string: "199.99"))
    }

    func testNewerDocumentIsLeftUntouchedAndReadOnly() throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let text = #"{"schemaVersion": 99, "tools": []}"#
        try text.write(to: paths.document, atomically: true, encoding: .utf8)
        let repository = FileWorkshopRepository(paths: paths)
        XCTAssertTrue(repository.isReadOnly)
        XCTAssertNotNil(repository.loadProblem)
        XCTAssertThrowsError(try repository.transact { $0.locations = [] ; $0.settings.defaultLoanDays = 3 })
        XCTAssertEqual(try String(contentsOf: paths.document), text)
    }

    func testUnreadableDocumentIsKeptAside() throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try "not json".write(to: paths.document, atomically: true, encoding: .utf8)
        let repository = FileWorkshopRepository(paths: paths)
        XCTAssertNotNil(repository.loadProblem)
        let files = try FileManager.default.contentsOfDirectory(atPath: paths.root.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("workshop-unreadable-") })
    }

    func testOlderDocumentWithMissingFieldsDegrades() throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let location = UUID(), tool = UUID()
        let text = """
        {"locations":[{"id":"\(location)","name":"Shelf"}],
         "tools":[{"id":"\(tool)","name":"Drill","homeLocationID":"\(location)","category":"somethingNew"}],
         "movements":[{"id":"\(UUID())","toolID":"\(tool)","kind":"initial","quantity":2}]}
        """
        try text.write(to: paths.document, atomically: true, encoding: .utf8)
        let repository = FileWorkshopRepository(paths: paths)
        XCTAssertNil(repository.loadProblem)
        XCTAssertEqual(repository.workshop.tools.first?.category, .other)
        XCTAssertEqual(StockLedger.balance(of: tool, in: repository.workshop).available, 2)
    }

    // MARK: - Export

    func testCSVQuotesAndDefusesFormulas() {
        let csv = WorkshopExport.csv([["=SUM(A1)", "a,b", "say \"hi\""]])
        XCTAssertEqual(csv, "'=SUM(A1),\"a,b\",\"say \"\"hi\"\"\"\r\n")
    }
}
