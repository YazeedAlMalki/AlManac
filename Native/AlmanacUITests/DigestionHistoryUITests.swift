import XCTest

/// Digestion history, reached from Modules → Digestion (BRD §6.3's read side).
///
/// What this covers that `DigestionHistoryTests` cannot: that the screen is
/// reachable, that an entry logged through Quick Log is counted under its type,
/// and that every count row carries its number and its name in words (§6.20),
/// never a colour alone.
///
/// Written against an accumulating database. The tests share one installed
/// app, so the count is read before logging and compared after, rather than
/// assumed to start at zero.
final class DigestionHistoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// The screen opens, offers three ranges, and states that it does not
    /// interpret what it shows.
    func testHistoryOpensWithRangesAndNoInterpretation() {
        openHistory()
        let range = app.element("digestion.history.range")
        XCTAssertTrue(range.waitForExistence(timeout: 5), "the range control is missing")
        for title in ["7 days", "30 days", "90 days"] {
            XCTAssertTrue(app.buttons[title].exists, "the \(title) range is not offered")
        }
        XCTAssertTrue(app.staticTexts["Almanac records what you saw and does not interpret it."].exists)
    }

    /// Logging a Type 4 through Quick Log raises the Type 4 count by one, and the
    /// row reads its number and its name in words.
    func testALoggedBowelMovementIsCountedUnderItsTypeInWords() {
        openHistory()
        let before = typeFourCount()

        logDefaultBowelMovement()

        openHistory()
        let row = countRow("digestion.history.bristol.4")
        XCTAssertTrue(app.reveal(row), "the Type 4 row is missing")
        XCTAssertTrue(row.label.contains("Type 4, Smooth, soft sausage"),
                      "the Type 4 row does not carry its number and name: \(row.label)")
        XCTAssertEqual(count(in: row.label), before + 1,
                       "the logged entry was not counted under Type 4: \(row.label)")

        // Grades carry their number, the scale and words, never colour alone.
        let darkest = countRow("digestion.history.grade.8")
        XCTAssertTrue(app.reveal(darkest), "the grade 8 row is missing")
        XCTAssertTrue(darkest.label.contains("Colour grade 8 of 8"), darkest.label)
        XCTAssertTrue(darkest.label.contains("dark brown"), darkest.label)

        // The range control changes what is counted without losing the entry.
        let month = app.buttons["30 days"]
        XCTAssertTrue(app.reveal(month, direction: .down))
        month.tap()
        let monthRow = countRow("digestion.history.bristol.4")
        XCTAssertTrue(app.reveal(monthRow))
        XCTAssertGreaterThanOrEqual(count(in: monthRow.label), before + 1)
    }

    // MARK: - Helpers

    /// The trailing number of a combined count row ("Type 4, Smooth, soft
    /// sausage, 3"). Zero when the row is absent, because then nothing was
    /// logged in the range and the screen shows its empty state instead.
    private func typeFourCount() -> Int {
        let row = countRow("digestion.history.bristol.4")
        guard row.waitForExistence(timeout: 3), app.reveal(row) else { return 0 }
        return count(in: row.label)
    }

    /// A count row by identifier, of whatever element type the combined row
    /// becomes. Not `app.element(_:)`: that picks a query type once, at the
    /// moment it is called, and the history loads just after the screen
    /// appears — so it fell back to a button query that never matches a row.
    private func countRow(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func count(in label: String) -> Int {
        let digits = label.split(separator: ",").last?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return Int(digits) ?? -1
    }

    private func logDefaultBowelMovement() {
        let quickLog = app.buttons["quick-log"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 10))
        quickLog.tap()
        XCTAssertTrue(app.staticTexts["Quick log"].waitForExistence(timeout: 5))
        let card = app.buttons["quicklog-destination-digestion"]
        XCTAssertTrue(app.reveal(card), "Quick Log does not offer digestion")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.navigationBars["Log digestion"].waitForExistence(timeout: 5))
        // The form opens on Type 4, so saving as-is logs a Type 4.
        XCTAssertTrue(app.buttons["bristol-link"].label.contains("Type 4"),
                      "the form did not open on Type 4: \(app.buttons["bristol-link"].label)")
        app.navigationBars["Log digestion"].buttons["Save"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !self.app.navigationBars["Log digestion"].exists },
                      "the digest sheet did not close after saving")
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        XCTAssertTrue(app.waitUntil(timeout: 5) { !self.app.staticTexts["Quick log"].exists },
                      "Quick Log did not close")
    }

    private func openHistory() {
        // Already on Digestion from an earlier visit: its back button is also
        // labelled "Modules", so a bare "Modules" query matches two buttons.
        // Go back with the navigation bar's own button instead.
        let digestionBar = app.navigationBars["Digestion"]
        if digestionBar.exists {
            digestionBar.buttons.firstMatch.tap()
        } else {
            let modules = app.buttons["Modules"].firstMatch
            XCTAssertTrue(modules.waitForExistence(timeout: 10))
            modules.tap()
        }
        XCTAssertTrue(app.navigationBars["Modules"].waitForExistence(timeout: 5))
        let link = app.buttons["Digestion"]
        XCTAssertTrue(app.reveal(link), "Modules does not offer Digestion")
        link.tap()
        XCTAssertTrue(app.navigationBars["Digestion"].waitForExistence(timeout: 5))
        // The counts load just after the screen appears; wait for them.
        XCTAssertTrue(countRow("digestion.history.totals").waitForExistence(timeout: 5)
                      || countRow("digestion.history.empty").waitForExistence(timeout: 1),
                      "the history did not load")
    }
}
