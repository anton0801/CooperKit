import XCTest

/// End-to-end checks through the real interface. Launch arguments are DEBUG-only:
/// `-uiTestReset` uses an isolated empty store, `-skipOnboarding` starts at Home and
/// `-uiTestSeed` fills the store with a small workshop for the screen tour.
/// Set `TEST_RUNNER_CK_SHOTS=<folder>` to also write every screenshot there as PNG.
final class CopperKitUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Acceptance: empty workshop → tool → loan → partial return → service

    func testAcceptanceFlowFromEmptyWorkshop() {
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        // Onboarding
        XCTAssertTrue(app.staticTexts["Give Every Tool a Place"].waitForExistence(timeout: 5))
        shot("01-onboarding-1")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Build the Kit Before You Begin"].waitForExistence(timeout: 3))
        shot("02-onboarding-2")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Know What Still Needs to Come Back"].waitForExistence(timeout: 3))
        shot("03-onboarding-3")
        app.buttons["Get Started"].tap()

        // Empty Home — no invented tools or value
        XCTAssertTrue(app.staticTexts["Add Your First Tool"].waitForExistence(timeout: 5))
        shot("04-home-empty")
        button("Add Tool").tap()

        // Tool Editor: create the location inline, then the tool
        XCTAssertTrue(app.navigationBars["New Tool"].waitForExistence(timeout: 5))
        shot("05-tool-editor-empty")
        button("Create Location").tap()
        XCTAssertTrue(app.navigationBars["New Location"].waitForExistence(timeout: 5))
        type("Garage Shelf", into: "Location Name, required")
        app.navigationBars["New Location"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["New Tool"].waitForExistence(timeout: 5))

        type("F-Clamp", into: "Name, required")
        app.buttons["Identical Units"].tap()
        let increase = app.buttons["Increase Initial Quantity"]
        XCTAssertTrue(increase.waitForExistence(timeout: 3))
        increase.tap(); increase.tap(); increase.tap() // 4 units
        shot("06-tool-editor-filled")
        app.navigationBars["New Tool"].buttons["Save"].tap()

        // Lands on Tool Detail
        let checkout = app.buttons["Checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "4 of 4 available").exists)
        shot("07-tool-detail")

        // Loan three clamps
        checkout.tap()
        XCTAssertTrue(app.navigationBars["Checkout Review"].waitForExistence(timeout: 5))
        app.buttons["Loan"].tap()
        type("Fence repair", into: "Purpose, required")
        type("Anna", into: "Recipient Name, required")
        let moreUnits = app.buttons["Increase Quantity"]
        moreUnits.tap(); moreUnits.tap()
        shot("08-checkout-review")
        scrollTo(app.buttons["Confirm Checkout"]).tap()

        // Handover detail
        let recordReturn = app.buttons["Record Return"]
        XCTAssertTrue(recordReturn.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["With Anna"].exists)
        shot("09-handover-open")

        // Partial return: one fine, one damaged, one still out
        recordReturn.tap()
        XCTAssertTrue(app.navigationBars["Record Return"].waitForExistence(timeout: 5))
        app.buttons["Increase Back to Available"].tap()
        app.buttons["Increase Needs Service"].tap()
        type("Jaw bent", into: "What Needs Attention, required")
        shot("10-return")
        scrollTo(app.buttons["Confirm Return"]).tap()

        XCTAssertTrue(element(containing: "1 Still Out").waitForExistence(timeout: 5))
        shot("11-handover-partial")

        // Service shows the damaged unit
        app.navigationBars.buttons.element(boundBy: 0).tap()
        button("Home").tap()
        XCTAssertTrue(app.staticTexts["Available Units"].waitForExistence(timeout: 5))
        shot("12-home-after-return")
        scrollTo(button("Service")).tap()
        XCTAssertTrue(app.staticTexts["Jaw bent"].waitForExistence(timeout: 5))
        shot("13-service-list")
    }

    // MARK: - Screen tour with a seeded workshop

    func testScreenTour() {
        app.launchArguments = ["-uiTestReset", "-skipOnboarding", "-uiTestSeed"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Available Units"].waitForExistence(timeout: 8))
        shot("20-home")
        app.swipeUp()
        shot("21-home-lower")

        // Tools
        tab("Tools")
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 5))
        shot("22-tools")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'F-Clamp 300 mm'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Checkout"].waitForExistence(timeout: 5))
        shot("23-tool-detail")
        app.swipeUp()
        shot("24-tool-detail-lower")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Kits → Prepare
        tab("Kits")
        XCTAssertTrue(app.navigationBars["Kits"].waitForExistence(timeout: 5))
        shot("25-kits")
        app.staticTexts["Deck Repair"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Prepare"].waitForExistence(timeout: 5))
        shot("26-kit-detail")
        app.buttons["Prepare"].tap()
        XCTAssertTrue(app.navigationBars["Prepare Kit"].waitForExistence(timeout: 5))
        shot("27-prepare")
        app.swipeUp()
        shot("28-prepare-lower")

        // Handovers
        tab("Handovers")
        XCTAssertTrue(app.navigationBars["Handovers"].waitForExistence(timeout: 5))
        shot("29-handovers")
        app.staticTexts["Shelf build at Mark's"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Record Return"].waitForExistence(timeout: 5))
        shot("30-handover-overdue")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Storage → location → inventory
        tab("Storage")
        XCTAssertTrue(app.navigationBars["Storage"].waitForExistence(timeout: 5))
        shot("31-storage")
        app.staticTexts["Garage Shelf A"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Start Inventory"].waitForExistence(timeout: 5))
        shot("32-location")
        app.buttons["Start Inventory"].tap()
        XCTAssertTrue(app.navigationBars["Inventory Check"].waitForExistence(timeout: 5))
        shot("33-inventory")

        // Back to the section root, then Home → History, Settings
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        button("Home").tap()
        XCTAssertTrue(app.staticTexts["Available Units"].waitForExistence(timeout: 5))
        scrollTo(button("History")).tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        shot("34-history")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shot("35-settings")
    }

    // MARK: - Sheets and the kit path

    func testKitPathAndSheets() {
        app.launchArguments = ["-uiTestReset", "-skipOnboarding", "-uiTestSeed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Available Units"].waitForExistence(timeout: 8))

        // Tool sheets
        tab("Tools")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Try Square'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Adjust Stock"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Adjust Stock"]).tap()
        XCTAssertTrue(app.navigationBars["Adjust Stock"].waitForExistence(timeout: 5))
        shot("50-adjust-stock")
        app.navigationBars["Adjust Stock"].buttons["Cancel"].tap()
        scrollTo(app.buttons["Send to Service"]).tap()
        XCTAssertTrue(app.navigationBars["Send to Service"].waitForExistence(timeout: 5))
        shot("51-send-to-service")
        app.navigationBars["Send to Service"].buttons["Cancel"].tap()
        app.navigationBars["Try Square"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Tool"].waitForExistence(timeout: 5))
        app.swipeUp(); app.swipeUp()
        shot("52-edit-tool-lower")
        app.navigationBars["Edit Tool"].buttons["Cancel"].tap()

        // Kit editor
        tab("Kits")
        app.staticTexts["Deck Repair"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Prepare"].waitForExistence(timeout: 5))
        scrollTo(button("Edit")).tap()
        XCTAssertTrue(app.navigationBars["Edit Kit"].waitForExistence(timeout: 5))
        shot("53-kit-editor")
        app.navigationBars["Edit Kit"].buttons["Cancel"].tap()

        // Prepare: fix the short clamp line, tick everything, review checkout
        app.swipeDown(); app.swipeDown()
        app.buttons["Prepare"].tap()
        XCTAssertTrue(app.navigationBars["Prepare Kit"].waitForExistence(timeout: 5))
        let fixes = app.buttons.matching(NSPredicate(format: "label == 'Fix or Change'"))
        fixes.element(boundBy: 1).tap()
        app.buttons["Reduce to 3 for This Run"].tap()
        for box in app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prepared:'")).allElementsBoundByIndex where box.isHittable {
            box.tap()
        }
        shot("54-prepare-fixed")
        scrollTo(app.buttons["Review Checkout"]).tap()
        XCTAssertTrue(app.navigationBars["Checkout Review"].waitForExistence(timeout: 5))
        shot("55-checkout-from-kit")
        app.swipeUp(); app.swipeUp()
        shot("56-checkout-from-kit-lower")
    }

    // MARK: - Large text

    func testAccessibilityTextSizes() {
        app.launchArguments = ["-uiTestReset", "-skipOnboarding", "-uiTestSeed",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Available Units"].waitForExistence(timeout: 8))
        shot("40-home-ax")
        tab("Tools")
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 5))
        shot("41-tools-ax")
        tab("Handovers")
        XCTAssertTrue(app.navigationBars["Handovers"].waitForExistence(timeout: 5))
        shot("42-handovers-ax")
    }

    // MARK: - Helpers

    private func tab(_ title: String) {
        let item = app.buttons["tab.\(title.lowercased())"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no tab \(title)")
        item.tap()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The first on-screen button with this label.
    private func button(_ label: String) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = query.firstMatch.waitForExistence(timeout: 5)
        return query.allElementsBoundByIndex.first { $0.isHittable } ?? query.firstMatch
    }

    private func type(_ text: String, into label: String) {
        let field = app.textFields[label]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field \(label)")
        scrollTo(field).tap()
        field.typeText(text + "\n") // return dismisses the keyboard
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> XCUIElement {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        return element
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["CK_SHOTS"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
