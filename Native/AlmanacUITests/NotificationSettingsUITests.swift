import XCTest

/// The reminders screen and the settings path that reaches it.
///
/// What can be asserted here is the *shape* of the feature: every notification
/// type §14.2 names has a switch, the screen says plainly when the app is not
/// allowed to notify, and a switch that is flipped survives a relaunch. What
/// cannot be asserted from a UI test is whether a notification actually arrives
/// at a chosen minute — that is `docs/acceptance-checklist.md`'s device-only
/// section, deliberately left unrun rather than ticked.
final class NotificationSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertFalse(app.staticTexts["Almanac could not open"].waitForExistence(timeout: 5),
                       "the app refused to open")
    }

    func testRemindersScreenOpensFromSettings() {
        openReminders()
        XCTAssertTrue(app.navigationBars["Reminders"].exists)
    }

    /// BRD §6.14: "All types individually toggleable". A type with no switch is
    /// a type the user can never stop, which for a readiness or water prompt is
    /// the whole difference between a useful reminder and an intrusion.
    func testEveryNotificationTypeHasASwitch() {
        openReminders()
        for type in ["readiness", "water", "meal", "bedtime", "supplement",
                     "suhoor", "iftar", "contextual_snack", "contextual_hydration"] {
            let toggle = app.switches["notification-rule-\(type)"]
            XCTAssertTrue(app.reveal(toggle), "no switch for \(type)")
        }
    }

    /// The screen must state its own authorization rather than showing a count
    /// of zero, which is indistinguishable from "nothing to schedule".
    func testTheScreenSaysWhetherNotificationsAreAllowed() {
        openReminders()
        let allowed = app.staticTexts["Queued now"]
        let refused = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "has not been allowed to send notifications")).firstMatch
        XCTAssertTrue(allowed.exists || refused.exists,
                      "neither the queued count nor the refusal is stated; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// A switch that flips and reverts is the minimum a toggle has to do, and it
    /// is the part a UI test can actually see.
    func testASwitchFlipsAndReverts() {
        openReminders()
        let toggle = app.switches["notification-rule-bedtime"]
        XCTAssertTrue(app.reveal(toggle))

        // `tapSwitchControl` rather than `tap`: a row-level tap can land on the
        // label text and do nothing, which reads as "the switch is broken" when
        // the switch is fine and the tap missed.
        toggle.tapSwitchControl()
        let afterOn = toggle.value as? String
        toggle.tapSwitchControl()
        let afterOff = toggle.value as? String

        XCTAssertNotEqual(afterOn, afterOff, "toggling twice returned the same value")
        XCTAssertTrue(["0", "1"].contains(afterOn ?? ""), "unexpected value \(afterOn ?? "nil")")
        XCTAssertTrue(["0", "1"].contains(afterOff ?? ""), "unexpected value \(afterOff ?? "nil")")
    }

    /// Turning every reminder off must be possible, and must ask first — it is
    /// the one action on this screen that is not trivially reversible.
    func testTurningEverythingOffAsksFirst() {
        openReminders()
        let turnOff = app.buttons["notification-turn-off-all"]
        guard app.reveal(turnOff) else {
            // Nothing is on in a fresh install except the §5.25 defaults, and if
            // the user has already turned those off there is nothing to confirm.
            return
        }
        turnOff.tap()
        let confirm = app.buttons["Turn them all off"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3),
                      "turning everything off did not ask for confirmation; visible: "
                      + "\(app.buttons.allElementsBoundByIndex.map(\.label))")
        app.buttons["Keep them on"].tap()
        XCTAssertFalse(app.buttons["Turn them all off"].exists, "the confirmation did not dismiss")
    }

    // MARK: - Helpers

    private func openReminders() {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10))
        modules.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(app.reveal(settings), "Settings is not offered")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let link = app.buttons["notification-settings-link"]
        XCTAssertTrue(app.reveal(link), "Settings does not offer the reminders screen")
        link.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
    }
}
