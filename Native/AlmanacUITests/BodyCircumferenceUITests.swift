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
        // Re-queried, not the `toggle` captured before `terminate()`. An element
        // from a terminated process is a snapshot of a hierarchy that no longer
        // exists, so its `value` reads back whatever it was when the app died —
        // which is why the "must be 0 after toggling off" assertion below could
        // pass or fail depending on what state the previous run left, rather
        // than on what the tap did.
        let toggleAfterRelaunch = app.switches["Track left/right arms and thighs"]
        XCTAssertTrue(toggleAfterRelaunch.waitForExistence(timeout: 5))
        XCTAssertEqual(toggleAfterRelaunch.value as? String, "1", "Side preference must persist across launch")
        tapSwitch(toggleAfterRelaunch) // Exercise the reversible toggle-off stub.
        // Waited for, not read at once: just after a launch the redraw can trail
        // the tap, and an immediate read saw "1" (CI 2026-10-17, df94ead).
        XCTAssertTrue(app.waitUntil(timeout: 5) { toggleAfterRelaunch.value as? String == "0" },
                      "the side switch did not turn off: \(String(describing: toggleAfterRelaunch.value))")
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

    /// Flips the switch and waits for its value to change. CI dropped this
    /// tap twice (lines 17 and 58, on runs where the rest passed), so a tap
    /// whose value has not moved within 2 s is retried once on the settled
    /// switch. A switch the app itself snaps back fails the same way twice,
    /// and the test's own value assertions still report it.
    private func tapSwitch(_ toggle: XCUIElement) {
        let app = XCUIApplication()
        let before = toggle.value as? String
        toggle.tapSwitchControl()
        if !app.waitUntil(timeout: 2, { toggle.value as? String != before }) {
            _ = app.waitUntilSettled(toggle)
            toggle.tapSwitchControl()
            _ = app.waitUntil(timeout: 3) { toggle.value as? String != before }
        }
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(app.reveal(settings), "Settings is not reachable from Modules")
        settings.tap()
        let toggle = app.switches["Track left/right arms and thighs"]
        XCTAssertTrue(app.reveal(toggle), "the sides toggle is not reachable")
    }

    private func openCircumferences(_ app: XCUIApplication) {
        let destination = app.buttons["Body circumferences"]
        // Upward, not downward: this is called straight after leaving Settings,
        // so the list is wherever Settings left it rather than at the top.
        XCTAssertTrue(app.reveal(destination, direction: .down),
                      "Body circumferences is not reachable from Modules")
        destination.tap()
        XCTAssertTrue(app.buttons["Log circumference"].waitForExistence(timeout: 5))
    }
}
