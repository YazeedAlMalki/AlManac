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
        XCTAssertTrue(revealAtRest(toggle), "Today offers no recovery-day switch")
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

    // MARK: - SCRATCH: diagnosis only, never merged

    /// The test as it stood at 12fd3a1 (`app.reveal` + `waitUntilSettled`),
    /// minus the retry, printing one TAP-DIAG line per tap.
    func testScratchOriginalWithoutRetry() {
        openToday()
        diag("launch", "question-card=\(app.staticTexts["Which fasts do you keep?"].exists)")
        let toggle = app.element("recovery-day-toggle")
        let before = toggle.exists ? toggle.frame : .zero
        XCTAssertTrue(app.reveal(toggle), "Today offers no recovery-day switch")
        let after = toggle.frame
        diag("reveal", "frame-before=\(before) frame-after=\(after) scrolled=\(before.midY != after.midY)")
        for wanted in [false, true, false, true, false] {
            originalTap(toggle, on: wanted)
        }
    }

    /// The proposed fix: `revealAtRest`, one tap, no retry.
    func testScratchFixed() {
        openToday()
        let toggle = app.element("recovery-day-toggle")
        XCTAssertTrue(revealAtRest(toggle), "Today offers no recovery-day switch")
        for wanted in [false, true, false, true, false] {
            let target = wanted ? "1" : "0"
            guard toggle.value as? String != target else { continue }
            XCTAssertTrue(revealAtRest(toggle))
            toggle.tapSwitchControl()
            let took = app.waitUntil(timeout: 5) { toggle.value as? String == target }
            diag("fixed-tap", "wanted=\(target) took=\(took) frame=\(toggle.frame)")
            XCTAssertTrue(took, "fixed: the switch did not move to \(target)")
        }
    }

    /// Does a coasting page eat the tap? Three ways to arrive at the switch,
    /// twelve fresh launches each, one tap each.
    func testScratchMomentumExperiment() {
        for mode in ["flick-then-settle-check", "flick-then-4s", "drag-hold"] {
            var dropped = 0, took = 0, offscreen = 0
            for trial in 0..<12 {
                app.terminate()
                app.launch()
                openToday()
                Thread.sleep(forTimeInterval: 3)
                let toggle = app.element("recovery-day-toggle")
                guard revealAtRest(toggle) else { offscreen += 1; continue }
                let page = app.scrollViews.firstMatch
                let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8))
                let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7))
                let releasedAt = Date()
                switch mode {
                case "drag-hold":
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
                default:
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 900),
                                thenHoldForDuration: 0)
                }
                if mode == "flick-then-settle-check" { _ = app.waitUntilSettled(toggle) }
                if mode == "flick-then-4s" { Thread.sleep(forTimeInterval: 4) }
                guard app.isRevealed(toggle) else { offscreen += 1; continue }
                let value = toggle.value as? String
                let frameAtTap = toggle.frame
                let sinceRelease = Date().timeIntervalSince(releasedAt)
                toggle.tapSwitchControl()
                let changed = app.waitUntil(timeout: 3) { toggle.value as? String != value }
                Thread.sleep(forTimeInterval: 1)
                let frameLater = toggle.frame
                if changed { took += 1 } else { dropped += 1 }
                diag("momentum", "mode=\(mode) trial=\(trial) changed=\(changed) "
                     + "since-release=\(String(format: "%.2f", sinceRelease))s frame-at-tap=\(frameAtTap) "
                     + "frame-1s-later=\(frameLater)")
            }
            diag("momentum-summary", "mode=\(mode) took=\(took) dropped=\(dropped) offscreen=\(offscreen)")
        }
        let toggle = app.element("recovery-day-toggle")
        if revealAtRest(toggle), toggle.value as? String == "1" { toggle.tapSwitchControl() }
    }

    private func originalTap(_ toggle: XCUIElement, on: Bool) {
        let wanted = on ? "1" : "0"
        guard toggle.value as? String != wanted else { return }
        XCTAssertTrue(app.reveal(toggle))
        let settled = app.waitUntilSettled(toggle)
        let frameAtTap = toggle.frame
        toggle.tapSwitchControl()
        let took = app.waitUntil(timeout: 3) { toggle.value as? String == wanted }
        let frameLater = toggle.frame
        diag("original-tap", "wanted=\(wanted) took=\(took) settled=\(settled) frame-at-tap=\(frameAtTap) "
             + "frame-3s-later=\(frameLater) alerts=\(app.alerts.count)")
        if !took {
            // Keep the run going so one iteration can report several taps.
            print("TAP-DIAG\ttree\t" + String(app.debugDescription.prefix(6000)).replacingOccurrences(of: "\n", with: " | "))
            _ = app.waitUntil(timeout: 3) { false }
            toggle.tapSwitchControl()
            _ = app.waitUntil(timeout: 3) { toggle.value as? String == wanted }
        }
    }

    private func diag(_ kind: String, _ detail: String) {
        print("TAP-DIAG\t\(kind)\t\(name)\t\(detail)")
    }

    // MARK: - Helpers

    private func openToday() {
        let today = app.buttons["tab-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "the Today destination is missing")
        if !today.isSelected { today.tap() }
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.buttons.count > 3 },
                      "Today never finished loading")
    }

    /// Scrolls `element` into view with drags that hold still before they
    /// let go, so Today is at rest, not coasting, when the switch is tapped.
    ///
    /// The dropped tap (76ed79b, da1da96, and once locally) was the scroll
    /// view's momentum. Today is a `ScrollView`, and `reveal` scrolls it with
    /// flicks. A flick keeps the page coasting for a second or two after it
    /// lets go, and a tap on a coasting scroll view only stops the scroll:
    /// UIKit never hands it to the switch. `waitUntilSettled` could not see
    /// that, because at the end of a coast the frame moves by less than a
    /// point between two reads. A drag that holds before lifting leaves no
    /// velocity behind, so there is nothing to coast.
    private func revealAtRest(_ element: XCUIElement) -> Bool {
        let page = app.scrollViews.firstMatch
        for _ in 0..<12 {
            if app.isRevealed(element) { return true }
            guard page.exists else { break }
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7))
                .press(forDuration: 0.05,
                       thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45)),
                       withVelocity: .slow,
                       thenHoldForDuration: 0.3)
        }
        return app.isRevealed(element)
    }

    /// Moves the switch only if it is not already where it is wanted, and
    /// waits for the value to say so: a tap that lands on the label rather than
    /// the switch does nothing, and the assertion should say that rather than
    /// fail later on the card.
    ///
    /// One tap, no retry: the page is at rest (`revealAtRest`), so a tap that
    /// does not take is a real failure.
    private func setRecoveryDay(_ toggle: XCUIElement, on: Bool) {
        let wanted = on ? "1" : "0"
        guard toggle.value as? String != wanted else { return }
        XCTAssertTrue(revealAtRest(toggle))
        toggle.tapSwitchControl()
        let card = app.staticTexts["readiness-recommendation"]
        XCTAssertTrue(app.waitUntil(timeout: 5) { toggle.value as? String == wanted },
                      "the recovery-day switch did not move to \(wanted): value \(String(describing: toggle.value)), "
                      + "frame \(toggle.frame), alerts \(app.alerts.allElementsBoundByIndex.map(\.label)), "
                      + "card \(card.exists ? card.label : "absent")")
    }
}
