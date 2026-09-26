import XCTest

/// Guards the boundary between "there is nothing here" and "the read failed".
///
/// `HydrationModel`, `TrainingModel` and `ReadinessModel` each gained a
/// `readProblem` channel, because their `catch` blocks used to carry a comment
/// promising the figures would be "stale until the next refresh() succeeds" —
/// a self-heal with no mechanism behind it, since the next refresh fails
/// identically. Now the failure is stated.
///
/// That fix introduces the opposite risk, and this suite is what catches it: a
/// note that is wired into the wrong branch turns every empty dashboard into
/// "could not read your log", which is a worse lie than the one it replaced.
/// A healthy database must never produce one of these three strings.
///
/// This is a negative test on purpose. The positive case — a genuine read
/// failure — needs a database that fails to open mid-session, which no test
/// harness here can arrange without deleting the user's data to find out. So
/// the cheap half is asserted on every run and the expensive half is left to a
/// human with a broken database.
final class ProblemChannelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 10),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// The read that backs this screen demonstrably succeeds — the test writes a
    /// drink first — so a problem note here would be unambiguously wrong rather
    /// than a race.
    func testHydrationWithASuccessfulWriteDoesNotClaimItCouldNotRead() {
        openModule("Hydration")
        let log = app.buttons["Log a drink"]
        XCTAssertTrue(app.reveal(log))
        log.tap()
        XCTAssertTrue(app.navigationBars["Log a drink"].waitForExistence(timeout: 10))

        let drink = app.element("drink-row-catalog_water")
        XCTAssertTrue(app.reveal(drink))
        drink.tap()
        let logButton = app.buttons["Log"]
        XCTAssertTrue(app.reveal(logButton))
        logButton.tap()

        // The sheet stays open when the service returns warnings (it does here,
        // on any re-run), so close it rather than assuming a dismissal.
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        XCTAssertTrue(app.navigationBars["Log a drink"].waitForNonExistence(timeout: 10))

        assertNoProblemReported("Could not read today's hydration log.")
        assertNoProblemReported("Apple Health sync is not going through.")
    }

    func testTrainingWithAHealthyDatabaseDoesNotClaimItCouldNotRead() {
        openModule("Training")
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        assertNoProblemReported("Could not read today's training log.")
    }

    /// Readiness gained two channels, not one. `readProblem` covers a failed
    /// read; `saveProblem` covers a score that was worked out correctly and
    /// then could not be written down. They are separate because the number on
    /// screen is trustworthy in the second case and missing in the first, so a
    /// single message would misdescribe one of them.
    func testReadinessWithAHealthyDatabaseReportsNeitherAFailedReadNorAFailedSave() {
        let today = app.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        today.tap()
        assertNoProblemReported("Could not read today's readiness data.")
        assertNoProblemReported("Today's readiness was worked out, but Almanac could not save it.")
    }

    // MARK: - Helpers

    /// Fails if `message` is anywhere on screen, reporting everything that *is*
    /// there so a failure names the real problem rather than just the expected
    /// one.
    private func assertNoProblemReported(_ message: String,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        // The note is a lazily-built row on a `List`, so scrolling is needed
        // before "it is not there" means anything. `reveal` returning false is
        // the pass condition, and it scrolls exactly as far as it would to find
        // the element. Prefix-matched, because the note's published label also
        // carries its advice.
        if app.reveal(app.staticText(beginningWith: message)) {
            XCTFail("""
                "\(message)" was shown, but nothing failed.
                on screen: \(app.staticTexts.allElementsBoundByIndex.map(\.label))
                """, file: file, line: line)
        }
    }

    private func openModule(_ name: String) {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 15), "the Modules destination is missing")
        modules.tap()
        let link = app.buttons[name]
        XCTAssertTrue(app.reveal(link), "\(name) is not reachable from Modules")
        link.tap()
    }
}
