import XCTest

/// §9.6's "manually selected recovery day (user set via UI)", driven on Today.
///
/// The core suites pin the precedence and the one-day scope
/// (`ReadinessEngineTests`, `RecoveryDayStoreTests`). What only a screen can
/// show is that the switch is there, that moving it changes the "For this
/// cycle" card and nothing in the score above it, and that it can be moved back
/// and forth without leaving the screen.
///
/// **The day has a real score to compare against.** Three prior days at
/// rhr 52 / hrv 55 and today's pair at 51 / 53 are planted with
/// `-AlmanacSeedVitals` (`XCUIApplication.seedVitals`), the same arrangement as
/// checklist rows 7.10/7.11, so the recommendation with the switch off is a band
/// sentence rather than nothing. Which band is not asserted: the simulator's
/// database is shared and never reset, so other suites' history moves the
/// baseline. The test reads the sentence off the screen first and asks for it
/// back.
///
/// **It starts from whatever the last run left.** A run that failed half-way
/// leaves today declared, so the switch is turned off before anything is read,
/// and turned off again at the end.
///
/// The wording is repeated here rather than imported: this target does not link
/// `AlmanacCore`.
final class ReadinessRecoveryDayUITests: XCTestCase {
    private var app: XCUIApplication!

    private let recoveryText = "Recovery day: rest as planned."

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCTAssertTrue(app.seedVitals("rhr=52@-3,hrv=55@-3,rhr=52@-2,hrv=55@-2,rhr=52@-1,hrv=55@-1,rhr=51@0,hrv=53@0"),
                      "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testDeclaringARecoveryDayChangesTheRecommendationAndCanBeTakenBack() {
        openToday()

        let toggle = app.element("recovery-day-toggle")
        XCTAssertTrue(app.reveal(toggle), "Today offers no recovery-day switch")
        setRecoveryDay(toggle, on: false)

        // The day as it reads with no declaration: a score, and a band sentence.
        let score = app.staticTexts["readiness-score"]
        XCTAssertTrue(score.waitForExistence(timeout: 10),
                      "the seeded readings produced no score, so there is nothing to hold steady")
        let scoreBefore = score.label
        let card = app.staticTexts["readiness-recommendation"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "with a baseline and a score there should be a band sentence for this cycle")
        let bandSentence = card.label
        XCTAssertNotEqual(bandSentence, recoveryText)

        // Declared: the card is replaced, the score is not.
        setRecoveryDay(toggle, on: true)
        XCTAssertTrue(app.waitUntil(timeout: 5) { card.label == self.recoveryText },
                      "declaring a recovery day did not change the recommendation (now: \(card.label))")
        XCTAssertEqual(score.label, scoreBefore, "declaring a recovery day moved the score")
        XCTAssertFalse(app.staticTexts["Rest day as planned."].exists,
                       "a recovery day the person declared was presented as a planned rest day")

        // Taken back on the same screen: the band sentence returns.
        setRecoveryDay(toggle, on: false)
        XCTAssertTrue(app.waitUntil(timeout: 5) { card.label == bandSentence },
                      "clearing the recovery day did not restore the band sentence (now: \(card.label))")
        XCTAssertEqual(score.label, scoreBefore)

        // And again, so "changeable while the screen is open" means more than once.
        setRecoveryDay(toggle, on: true)
        XCTAssertTrue(app.waitUntil(timeout: 5) { card.label == self.recoveryText },
                      "the second declaration did not take")
        setRecoveryDay(toggle, on: false)
        XCTAssertTrue(app.waitUntil(timeout: 5) { card.label == bandSentence })
    }

    // MARK: - Helpers

    private func openToday() {
        let today = app.buttons["tab-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "the Today destination is missing")
        if !today.isSelected { today.tap() }
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.buttons.count > 3 },
                      "Today never finished loading")
    }

    /// Moves the switch only if it is not already where it is wanted, and
    /// waits for the value to say so: a tap that lands on the label rather than
    /// the switch does nothing, and the assertion should say that rather than
    /// fail later on the card.
    private func setRecoveryDay(_ toggle: XCUIElement, on: Bool) {
        let wanted = on ? "1" : "0"
        guard toggle.value as? String != wanted else { return }
        XCTAssertTrue(app.reveal(toggle))
        // Twice in CI (76ed79b, da1da96) one tap left the switch at 0 for the
        // whole wait, on a Today screen whose list XCTest was still re-finding:
        // a tap synthesised from a frame that then moved. Settle first, as the
        // Training test does before its tap.
        XCTAssertTrue(app.waitUntilSettled(toggle),
                      "the recovery-day switch's frame kept moving; Today had not settled")
        toggle.tapSwitchControl()
        // One retry, for a tap that is dropped even on a settled screen. If
        // the app itself snapped the switch back, the second tap fails the
        // same way and the assertion below still reports it.
        if !app.waitUntil(timeout: 2, { toggle.value as? String == wanted }) {
            _ = app.waitUntilSettled(toggle)
            toggle.tapSwitchControl()
        }
        let card = app.staticTexts["readiness-recommendation"]
        XCTAssertTrue(app.waitUntil(timeout: 5) { toggle.value as? String == wanted },
                      "the recovery-day switch did not move to \(wanted): value \(String(describing: toggle.value)), "
                      + "frame \(toggle.frame), alerts \(app.alerts.allElementsBoundByIndex.map(\.label)), "
                      + "card \(card.exists ? card.label : "absent")")
    }
}
