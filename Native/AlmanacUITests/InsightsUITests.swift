import XCTest

/// The Insights screen — the first consumer any of `CorrelationEngine`,
/// `CorrelationPairStore`, `TrendSnapshotStore`, `AchievementEngine` or
/// `AchievementRecordStore` has ever had.
///
/// What is asserted here is the honesty of the wording, not the arithmetic
/// (that is `InsightsQueryTests`): the screen must state its window, must say
/// how many days it actually had, and must not print a correlation number for a
/// pair that has not cleared the 14-day gate.
final class InsightsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testInsightsOpensFromTrends() {
        let trends = app.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10))
        trends.tap()

        let link = app.buttons["insights-link"]
        XCTAssertTrue(app.reveal(link), "Trends does not offer Insights")
        link.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
    }

    /// A virgin database has no series, so the screen must say so rather than
    /// showing a screen of empty sections. And the association caveat has to be
    /// on the screen, not only in a comment.
    ///
    /// The caveat is the Associations section's footer, which sits below the
    /// fold on a short screen, so it is scrolled to rather than merely queried.
    /// Its presence is the assertion; a caveat that is present but unreachable
    /// is a caveat nobody reads.
    func testInsightsStatesItsWindowAndItsCaveat() {
        openInsights()
        let window = app.element("insights-window")
        XCTAssertTrue(app.reveal(window), "the window control is not offered")
        XCTAssertTrue(app.staticTexts["Trends"].exists, "the trends section is not shown")

        let caveat = app.staticText(beginningWith: "A number below says two measurements")
        XCTAssertTrue(app.reveal(caveat), "the association caveat is missing; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// The insufficient state has to be worded, not dashed. A pair with no
    /// paired days says how many it has and how many it needs.
    func testAPairWithNoDataSaysHowManyItNeeds() {
        openInsights()
        let insufficient = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Not enough paired days")).firstMatch
        if insufficient.exists {
            XCTAssertTrue(insufficient.label.contains("of 14"),
                          "the gate size is not stated: \(insufficient.label)")
        }
        // A virgin database has no pairs at all, in which case the section must
        // say so rather than render an empty list.
        let empty = app.staticTexts["No pairs to compare yet."]
        XCTAssertTrue(insufficient.exists || empty.exists,
                      "neither an insufficient state nor an empty state; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// Widening the window must take. An insight screen whose window control
    /// does nothing is worse than one without a control.
    func testWideningTheWindowTakes() {
        openInsights()
        let window = app.element("insights-window")
        XCTAssertTrue(app.reveal(window))
        window.tap()
        app.buttons["90 days"].tap()
        XCTAssertTrue(app.staticTexts["90 days"].waitForExistence(timeout: 5), "the window did not take")
    }

    /// The screen must never be blank, whatever the database holds.
    func testInsightsIsNeverBlank() {
        openInsights()
        let window = app.element("insights-window")
        XCTAssertTrue(app.reveal(window))
        XCTAssertTrue(app.cells.count > 1,
                      "the screen rendered no rows; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - Helpers

    private func openInsights() {
        let trends = app.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10))
        trends.tap()
        let link = app.buttons["insights-link"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
    }
}
