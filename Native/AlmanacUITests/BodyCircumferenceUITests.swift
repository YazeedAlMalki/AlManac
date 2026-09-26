import XCTest

final class BodyCircumferenceUITests: XCTestCase {
    func testSidedLoggingWarningAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Modules"].waitForExistence(timeout: 15))
        app.buttons["Modules"].tap()
        openSettings(app)
        let toggle = app.switches["Track left/right arms and thighs"]
        // Start from a known state: a previous partial run may have left it on.
        if toggle.value as? String == "1" { tapSwitch(toggle) }
        XCTAssertEqual(toggle.value as? String, "0")
        tapSwitch(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        openCircumferences(app)

        app.buttons["Log circumference"].tap()
        XCTAssertTrue(app.buttons["circumference-type"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["circumference-side"].exists, "Waist must never ask for a side")
        app.buttons["circumference-type"].tap()
        app.buttons["Arm"].tap()
        XCTAssertTrue(app.buttons["circumference-side"].waitForExistence(timeout: 5))
        app.buttons["circumference-side"].tap()
        app.buttons["Right"].tap()
        let value = app.textFields["Circumference (cm)"]
        value.tap()
        value.typeText("80.5") // Deliberately outside the arm's plausible range.
        let noteText = "Circumference UI check \(UUID().uuidString)"
        let note = app.textFields["Note"]
        note.tap()
        note.typeText(noteText)
        app.buttons["Save"].tap()
        let warning = app.alerts["That looks unusually low or high"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["Save anyway"].tap()
        XCTAssertTrue(app.staticTexts[noteText].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Arm · right: 80.5 cm"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Modules"].waitForExistence(timeout: 15))
        app.buttons["Modules"].tap()
        openSettings(app)
        XCTAssertEqual(toggle.value as? String, "1", "Side preference must persist across launch")
        tapSwitch(toggle) // Exercise the reversible toggle-off stub.
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        openCircumferences(app)
        XCTAssertTrue(app.staticTexts[noteText].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Arm · right: 80.5 cm"].exists, "Turning sides off must retain the old row")
        app.buttons["Log circumference"].tap()
        app.buttons["circumference-type"].tap()
        app.buttons["Arm"].tap()
        XCTAssertFalse(app.buttons["circumference-side"].exists)
        app.buttons["Cancel"].tap()

        // Swipe actions attach to the row, so query them at screen level.
        app.staticTexts[noteText].swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "a manual row must offer deletion")
        delete.tap()
        XCTAssertFalse(app.staticTexts[noteText].exists)
        app.navigationBars["Body circumferences"].buttons.firstMatch.tap()
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        // SwiftUI exposes the entire labeled row as a switch; hit its control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        settings.tap()
        let toggle = app.switches["Track left/right arms and thighs"]
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
    }

    private func openCircumferences(_ app: XCUIApplication) {
        let destination = app.buttons["Body circumferences"]
        for _ in 0..<8 where !destination.isHittable { app.swipeDown() }
        destination.tap()
        XCTAssertTrue(app.buttons["Log circumference"].waitForExistence(timeout: 5))
    }
}
