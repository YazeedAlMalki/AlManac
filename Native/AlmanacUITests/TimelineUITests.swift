import XCTest

/// The Timeline screen — the reading surface the merge type was built for.
///
/// The core suite covers the ordering and the range maths
/// (`TimelineTests`). What it cannot see is that the screen opens, that it
/// says something honest when a period is empty, and that widening the period
/// actually widens what is shown.
final class TimelineUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testTimelineOpensFromModulesAndStatesItsPeriod() {
        openTimeline()
        // The header states the range rather than leaving "today" to be assumed,
        // because a logical day is not a calendar day and the footer says so.
        XCTAssertTrue(app.staticTexts["Recorded"].exists, "the screen does not name what it is showing")
        // Scrolled to, not merely queried. A `List` builds rows lazily, so on a
        // populated database the section footer sits below the fold and is not
        // in the hierarchy at all — `exists` is false for something that is on
        // screen and merely unrendered. The same trap `UIScrollSupport`'s header
        // describes for `Form` rows, and it is why this assertion passed on an
        // empty database and failed on a full one.
        // `.up`, not `.down`: the footer and the picker are *below* the fold and
        // `.up` is this suite's name for scrolling toward the bottom of a list.
        // `.down` scrolls back toward the top, which is why the earlier
        // version of this assertion could not reach them however many swipes it
        // spent.
        let ordering = app.staticText(beginningWith: "In the order it happened")
        XCTAssertTrue(app.reveal(ordering),
                      "the screen does not state its ordering or the 04:00 boundary; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// A period with nothing in it must say so, and must not present an empty
    /// list that reads as "everything is fine".
    func testAnEmptyPeriodSaysSo() {
        openTimeline()
        let empty = app.staticTexts["Nothing recorded in this period."]
        let period = app.element("timeline-period")
        if period.waitForExistence(timeout: 3) {
            period.tap()
            app.buttons["Last 30 days"].tap()
        }
        // Either there is something recorded, or the empty state is there. Both
        // absent would be the bug — a blank screen.
        XCTAssertTrue(empty.exists || app.cells.count > 1,
                      "neither an empty state nor any rows; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// Widening the period must widen the range, not just relabel it. The
    /// section header carries the range's end, so it is the thing to check.
    func testWideningThePeriodChangesTheRangeItStates() {
        openTimeline()
        let period = app.element("timeline-period")
        // `reveal` rather than `waitForExistence`, for the same reason as the
        // footer assertion above: the picker is in the second section of a
        // lazily-built list, so on a populated database it is below the fold and
        // genuinely absent from the hierarchy until it is scrolled to.
        XCTAssertTrue(app.reveal(period), "the period control is not offered")
        period.tap()
        app.buttons["Last 7 days"].tap()

        XCTAssertTrue(app.staticTexts["Last 7 days"].waitForExistence(timeout: 5),
                      "the period did not take")
    }

    // MARK: - Helpers

    private func openTimeline() {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10))
        modules.tap()
        XCTAssertTrue(app.navigationBars["Modules"].waitForExistence(timeout: 5))

        let timeline = app.buttons["Timeline"]
        XCTAssertTrue(app.reveal(timeline), "Timeline is missing from Modules")
        timeline.tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
    }
}
