import XCTest
@testable import CopperKit

final class StockAndHandoverTests: XCTestCase {
    private var h: Harness!

    override func setUp() {
        super.setUp()
        h = Harness()
    }

    // MARK: - Tools and stock

    func testIndividualToolIsAlwaysOneUnit() throws {
        let drill = try h.tool("Drill", quantity: 5, mode: .individual)
        XCTAssertEqual(h.balance(drill.id).total, 1)
        XCTAssertThrowsError(try h.tools.adjustStock(toolID: drill.id, direction: .increase, quantity: 1, reason: "found"))
    }

    func testToolNeedsAHomeLocation() {
        var draft = ToolDraft(currencyCode: "EUR")
        draft.name = "Clamp"
        XCTAssertThrowsError(try h.tools.create(draft)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Home Location"))
        }
        XCTAssertTrue(h.workshop.tools.isEmpty)
    }

    func testAdjustStockDecreaseOnlyTakesAvailableAndNeedsReason() throws {
        let clamps = try h.tool("Clamp", quantity: 4)
        try h.handovers.checkout(h.checkoutRequest([(clamps.id, 3)]))
        XCTAssertThrowsError(try h.tools.adjustStock(toolID: clamps.id, direction: .decrease, quantity: 2, reason: "broken"))
        XCTAssertThrowsError(try h.tools.adjustStock(toolID: clamps.id, direction: .decrease, quantity: 1, reason: "  "))
        try h.tools.adjustStock(toolID: clamps.id, direction: .decrease, quantity: 1, reason: "Snapped")
        let balance = h.balance(clamps.id)
        XCTAssertEqual(balance.total, 3)
        XCTAssertEqual(balance.available, 0)
        XCTAssertEqual(balance.onLoan, 3)
        // Past events are kept, the decrease is its own movement.
        XCTAssertEqual(h.workshop.movements.filter { $0.toolID == clamps.id }.map(\.kind), [.initial, .decrease])
    }

    func testOutOfStockRecordIsKept() throws {
        let saw = try h.tool("Saw", quantity: 1)
        try h.tools.adjustStock(toolID: saw.id, direction: .decrease, quantity: 1, reason: "Gave away")
        XCTAssertTrue(h.balance(saw.id).isOutOfStock)
        XCTAssertNotNil(h.workshop.tool(saw.id))
        try h.tools.archive(saw.id)
        XCTAssertTrue(h.workshop.tool(saw.id)!.isArchived)
    }

    func testTrackingModeLockedAfterFirstMovement() throws {
        let bits = try h.tool("Bits", quantity: 1)
        var draft = ToolDraft(tool: bits, fallbackCurrency: "EUR")
        draft.trackingMode = .individual
        XCTAssertNoThrow(try h.tools.update(bits.id, with: draft)) // no movements yet
        draft.trackingMode = .identicalUnits
        try h.tools.update(bits.id, with: draft)
        try h.handovers.checkout(h.checkoutRequest([(bits.id, 1)]))
        draft.trackingMode = .individual
        XCTAssertThrowsError(try h.tools.update(bits.id, with: draft))
    }

    func testDeleteOnlyWithoutHistoryOtherwiseArchive() throws {
        let a = try h.tool("Level")
        let b = try h.tool("Square", quantity: 2)
        try h.tools.delete(a.id)
        XCTAssertNil(h.workshop.tool(a.id))
        try h.service.open(toolID: b.id, quantity: 1, issue: "Bent", notes: "")
        XCTAssertThrowsError(try h.tools.delete(b.id))
    }

    func testArchiveBlockedWhileOutOrInService() throws {
        let sander = try h.tool("Sander", quantity: 2)
        let handover = try h.handovers.checkout(h.checkoutRequest([(sander.id, 1)]))
        try h.service.open(toolID: sander.id, quantity: 1, issue: "Pad worn", notes: "")
        let blockers = StockLedger.archiveBlockers(toolID: sander.id, in: h.workshop, now: h.clock.now)
        XCTAssertEqual(blockers.count, 2)
        XCTAssertTrue(blockers[0].contains("on loan to Anna"))
        XCTAssertThrowsError(try h.tools.archive(sander.id))

        try h.handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id, returnedAt: h.clock.now,
                                                   note: "", lines: [.init(lineID: handover.lines[0].id, toAvailable: 1)]))
        let record = h.workshop.serviceRecords[0]
        try h.service.resolve(record.id, kind: .returnedToAvailable, quantity: 1, note: "")
        XCTAssertNoThrow(try h.tools.archive(sander.id))
        // Archived tools are not offered for checkout.
        XCTAssertThrowsError(try h.handovers.checkout(h.checkoutRequest([(sander.id, 1)])))
    }

    // MARK: - Checkout

    func testCheckoutIsAllOrNothing() throws {
        let drill = try h.tool("Drill", quantity: 2)
        let clamp = try h.tool("Clamp", quantity: 1)
        let before = h.workshop
        XCTAssertThrowsError(try h.handovers.checkout(h.checkoutRequest([(drill.id, 2), (clamp.id, 2)]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Nothing was checked out"))
        }
        XCTAssertEqual(h.workshop, before)
        XCTAssertEqual(h.balance(drill.id).available, 2)
    }

    func testRepeatedConfirmWithSameOperationCreatesOneHandover() throws {
        let drill = try h.tool("Drill", quantity: 3)
        let op = UUID()
        let first = try h.handovers.checkout(h.checkoutRequest([(drill.id, 1)], operation: op))
        let second = try h.handovers.checkout(h.checkoutRequest([(drill.id, 1)], operation: op))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(h.workshop.handovers.count, 1)
        XCTAssertEqual(h.balance(drill.id).available, 2)
    }

    func testDuplicateLinesAreMergedBeforeCheckingStock() throws {
        let drill = try h.tool("Drill", quantity: 3)
        XCTAssertThrowsError(try h.handovers.checkout(h.checkoutRequest([(drill.id, 2), (drill.id, 2)])))
        let handover = try h.handovers.checkout(h.checkoutRequest([(drill.id, 1), (drill.id, 2)]))
        XCTAssertEqual(handover.lines.count, 1)
        XCTAssertEqual(handover.lines[0].quantity, 3)
    }

    func testPersonalUseAndLoanCountSeparately() throws {
        let clamp = try h.tool("Clamp", quantity: 5)
        try h.handovers.checkout(h.checkoutRequest([(clamp.id, 2)], mode: .personalUse))
        try h.handovers.checkout(h.checkoutRequest([(clamp.id, 1)], mode: .loan))
        let balance = h.balance(clamp.id)
        XCTAssertEqual(balance.inUse, 2)
        XCTAssertEqual(balance.onLoan, 1)
        XCTAssertEqual(balance.available, 2)
        XCTAssertEqual(balance.total, 5)
    }

    func testCheckoutValidation() throws {
        let drill = try h.tool("Drill", quantity: 2)
        var request = h.checkoutRequest([(drill.id, 1)])
        request.recipientName = " "
        XCTAssertThrowsError(try h.handovers.checkout(request))           // loan needs a recipient
        request = h.checkoutRequest([(drill.id, 1)], startedAt: h.clock.now.addingTimeInterval(3600))
        XCTAssertThrowsError(try h.handovers.checkout(request))           // start in the future
        request = h.checkoutRequest([(drill.id, 1)], dueInDays: -1)
        XCTAssertThrowsError(try h.handovers.checkout(request))           // due before start
        request = h.checkoutRequest([])
        XCTAssertThrowsError(try h.handovers.checkout(request))           // empty
        request = h.checkoutRequest([(drill.id, 0)])
        XCTAssertThrowsError(try h.handovers.checkout(request))           // zero quantity
        request = h.checkoutRequest([(drill.id, 1)])
        request.purpose = String(repeating: "x", count: 121)
        XCTAssertThrowsError(try h.handovers.checkout(request))           // purpose limit
        XCTAssertTrue(h.workshop.handovers.isEmpty)
    }

    func testBackDatedHandoverWithPastDueIsOverdueImmediately() throws {
        let drill = try h.tool("Drill")
        let started = h.clock.now.addingTimeInterval(-10 * 86_400)
        let handover = try h.handovers.checkout(h.checkoutRequest([(drill.id, 1)], startedAt: started, dueInDays: 3))
        XCTAssertEqual(handover.status(at: h.clock.now), .overdue)
        XCTAssertEqual(StockLedger.summary(h.workshop, now: h.clock.now).overdueHandovers, 1)
    }

    func testHomeSummaryCountsRecordsUnitsAndOverdueHandovers() throws {
        let clamps = try h.tool("Clamp", quantity: 6)
        let drill = try h.tool("Drill", mode: .individual)
        let old = try h.tool("Old Level", quantity: 2)
        try h.tools.archive(old.id)
        let started = h.clock.now.addingTimeInterval(-5 * 86_400)
        // One overdue handover holding two different tools counts once.
        try h.handovers.checkout(h.checkoutRequest([(clamps.id, 3), (drill.id, 1)], startedAt: started, dueInDays: 1))
        let summary = StockLedger.summary(h.workshop, now: h.clock.now)
        XCTAssertEqual(summary.toolRecords, 2)
        XCTAssertEqual(summary.totalUnits, 7)
        XCTAssertEqual(summary.availableUnits, 3)
        XCTAssertEqual(summary.onLoan, 4)
        XCTAssertEqual(summary.overdueHandovers, 1)
    }

    // MARK: - Return

    func testPartialReturnWithDamageAndOverdue() throws {
        let clamp = try h.tool("Clamp", quantity: 6)
        let handover = try h.handovers.checkout(h.checkoutRequest([(clamp.id, 5)], dueInDays: 2))
        let line = handover.lines[0].id

        var updated = try h.handovers.recordReturn(ReturnRequest(
            operationID: UUID(), handoverID: handover.id, returnedAt: h.clock.now, note: "",
            lines: [.init(lineID: line, toAvailable: 2, needsService: 1, issueNote: "Jaw bent")]))
        XCTAssertEqual(updated.totalOutstanding, 2)
        XCTAssertEqual(updated.status(at: h.clock.now), .open)
        var balance = h.balance(clamp.id)
        XCTAssertEqual(balance.available, 3)
        XCTAssertEqual(balance.needsService, 1)
        XCTAssertEqual(balance.onLoan, 2)
        XCTAssertEqual(h.workshop.serviceRecords.count, 1)
        XCTAssertEqual(h.workshop.serviceRecords[0].issue, "Jaw bent")

        h.clock.advance(days: 3)
        XCTAssertEqual(updated.status(at: h.clock.now), .overdue)

        updated = try h.handovers.recordReturn(ReturnRequest(
            operationID: UUID(), handoverID: handover.id, returnedAt: h.clock.now, note: "",
            lines: [.init(lineID: line, toAvailable: 2)]))
        XCTAssertEqual(updated.status(at: h.clock.now), .returned)
        balance = h.balance(clamp.id)
        XCTAssertEqual(balance.available, 5)
        XCTAssertEqual(balance.needsService, 1)
        XCTAssertEqual(balance.total, 6)
        // History survives the close.
        XCTAssertEqual(h.workshop.handovers[0].returns.count, 2)
    }

    func testReturnValidationAndIdempotency() throws {
        let clamp = try h.tool("Clamp", quantity: 3)
        let handover = try h.handovers.checkout(h.checkoutRequest([(clamp.id, 2)]))
        let line = handover.lines[0].id
        // More than outstanding
        XCTAssertThrowsError(try h.handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id,
                                                                        returnedAt: h.clock.now, note: "",
                                                                        lines: [.init(lineID: line, toAvailable: 3)])))
        // Service without an issue
        XCTAssertThrowsError(try h.handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id,
                                                                        returnedAt: h.clock.now, note: "",
                                                                        lines: [.init(lineID: line, needsService: 1)])))
        // Nothing entered
        XCTAssertThrowsError(try h.handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id,
                                                                        returnedAt: h.clock.now, note: "",
                                                                        lines: [.init(lineID: line)])))
        // Before the checkout
        XCTAssertThrowsError(try h.handovers.recordReturn(ReturnRequest(operationID: UUID(), handoverID: handover.id,
                                                                        returnedAt: h.clock.now.addingTimeInterval(-60), note: "",
                                                                        lines: [.init(lineID: line, toAvailable: 1)])))
        let op = UUID()
        let request = ReturnRequest(operationID: op, handoverID: handover.id, returnedAt: h.clock.now, note: "",
                                    lines: [.init(lineID: line, toAvailable: 1)])
        try h.handovers.recordReturn(request)
        try h.handovers.recordReturn(request)
        XCTAssertEqual(h.workshop.handovers[0].returns.count, 1)
        XCTAssertEqual(h.balance(clamp.id).available, 2)
    }

    func testLostUnitsLeaveTheTotalAndCloseTheLine() throws {
        let bit = try h.tool("Bit", quantity: 4)
        let handover = try h.handovers.checkout(h.checkoutRequest([(bit.id, 2)]))
        let updated = try h.handovers.recordReturn(ReturnRequest(
            operationID: UUID(), handoverID: handover.id, returnedAt: h.clock.now, note: "",
            lines: [.init(lineID: handover.lines[0].id, toAvailable: 1, lost: 1)]))
        XCTAssertTrue(updated.isClosed)
        let balance = h.balance(bit.id)
        XCTAssertEqual(balance.total, 3)
        XCTAssertEqual(balance.available, 3)
    }

    func testChangeDue() throws {
        let drill = try h.tool("Drill")
        let handover = try h.handovers.checkout(h.checkoutRequest([(drill.id, 1)], dueInDays: 1))
        XCTAssertThrowsError(try h.handovers.changeDue(handover.id, dueAt: handover.startedAt.addingTimeInterval(-1), timeZoneID: "UTC"))
        try h.handovers.changeDue(handover.id, dueAt: handover.startedAt.addingTimeInterval(9 * 86_400), timeZoneID: "Asia/Tokyo")
        XCTAssertEqual(h.workshop.handovers[0].dueTimeZoneID, "Asia/Tokyo")
    }

    // MARK: - Service

    func testServiceResolution() throws {
        let saw = try h.tool("Saw", quantity: 3)
        XCTAssertThrowsError(try h.service.open(toolID: saw.id, quantity: 4, issue: "Dull", notes: ""))
        XCTAssertThrowsError(try h.service.open(toolID: saw.id, quantity: 1, issue: " ", notes: ""))
        let record = try h.service.open(toolID: saw.id, quantity: 2, issue: "Dull", notes: "")
        XCTAssertEqual(h.balance(saw.id).available, 1)
        XCTAssertThrowsError(try h.service.resolve(record.id, kind: .returnedToAvailable, quantity: 3, note: ""))
        XCTAssertThrowsError(try h.service.resolve(record.id, kind: .writtenOff, quantity: 1, note: ""))
        try h.service.resolve(record.id, kind: .returnedToAvailable, quantity: 1, note: "Sharpened")
        try h.service.resolve(record.id, kind: .writtenOff, quantity: 1, note: "Teeth gone")
        let balance = h.balance(saw.id)
        XCTAssertEqual(balance.total, 2)
        XCTAssertEqual(balance.available, 2)
        XCTAssertEqual(balance.needsService, 0)
        XCTAssertFalse(h.workshop.serviceRecords[0].isOpen)
    }

    // MARK: - Inventory

    func testInventoryAppliesDifferencesAsEvents() throws {
        let shelf = try h.location("Shelf A")
        let clamps = try h.tool("Clamp", quantity: 4, at: shelf)
        let square = try h.tool("Square", quantity: 2, at: shelf)
        try h.handovers.checkout(h.checkoutRequest([(clamps.id, 1)]))
        let rows = h.inventory.rows(locationID: shelf.id)
        XCTAssertEqual(rows.first { $0.tool.id == clamps.id }?.expectedAtHome, 3)

        let check = try h.inventory.apply(locationID: shelf.id, counts: [clamps.id: 2, square.id: 3], note: "")
        XCTAssertEqual(check.lines.count, 2)
        XCTAssertEqual(h.balance(clamps.id).total, 3)
        XCTAssertEqual(h.balance(clamps.id).onLoan, 1)
        XCTAssertEqual(h.balance(square.id).total, 3)
        XCTAssertEqual(h.workshop.movements.filter { $0.inventoryCheckID == check.id }.count, 2)
    }

    func testInventoryCannotRemoveMoreThanAvailable() throws {
        let clamps = try h.tool("Clamp", quantity: 2)
        try h.service.open(toolID: clamps.id, quantity: 2, issue: "Rust", notes: "")
        let before = h.workshop
        XCTAssertThrowsError(try h.inventory.apply(locationID: nil, counts: [clamps.id: 0], note: ""))
        XCTAssertEqual(h.workshop, before)
    }

    func testInventoryWillNotDuplicateAnIndividualToolThatIsOut() throws {
        let drill = try h.tool("Drill", mode: .individual)
        try h.handovers.checkout(h.checkoutRequest([(drill.id, 1)]))
        XCTAssertThrowsError(try h.inventory.apply(locationID: nil, counts: [drill.id: 1], note: ""))
    }

    // MARK: - Locations

    func testDeletingAUsedLocationRequiresANewHomeForAllIncludingArchived() throws {
        let a = try h.location("A")
        let b = try h.location("B")
        let level = try h.tool("Level", at: a)
        try h.tools.archive(level.id)
        XCTAssertThrowsError(try h.locations.delete(a.id, reassignTo: nil))
        XCTAssertThrowsError(try h.locations.delete(a.id, reassignTo: a.id))
        try h.locations.delete(a.id, reassignTo: b.id)
        XCTAssertEqual(h.workshop.tool(level.id)?.homeLocationID, b.id)
        XCTAssertNil(h.workshop.location(a.id))
    }

    func testMovingHomeKeepsOutUnitsOnTheirHandover() throws {
        let a = try h.location("A")
        let b = try h.location("B")
        let clamps = try h.tool("Clamp", quantity: 3, at: a)
        try h.handovers.checkout(h.checkoutRequest([(clamps.id, 1)]))
        try h.tools.moveHome([clamps.id], to: b.id)
        XCTAssertEqual(h.balance(clamps.id).onLoan, 1)
        XCTAssertEqual(h.inventory.rows(locationID: b.id).first?.expectedAtHome, 2)
    }
}
