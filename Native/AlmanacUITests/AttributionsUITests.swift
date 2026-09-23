import XCTest

/// Closes the one gap the core suite cannot: that these screens actually
/// *render*. The data behind both is unit-tested (`AttributionTests`,
/// `WorkoutGuideSeedTests`), and the bundle contents are checked by
/// `ExerciseGraphicAudit` — this drives the view layer on a real simulator,
/// which was otherwise unverified.
final class AttributionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // The launch-time guards (attribution + graphic-per-exercise) mean a
        // broken build shows this instead of the app. Fail with the reason
        // rather than a timeout on some unrelated element.
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - Attributions

    /// The requirement's criteria 1, 2 and 3: every bundled source is credited,
    /// each CC BY-SA entry carries title/author/source link/licence link, and
    /// a derived image is marked as modified with the change described.
    func testAttributionsPageCreditsEveryBundledSource() {
        openSettings()
        app.buttons["Attributions"].tap()
        XCTAssertTrue(app.navigationBars["Attributions"].waitForExistence(timeout: 10),
                      "the Attributions page never appeared")

        // Title, author, source link and licence link, for workout-guide.
        XCTAssertTrue(app.staticTexts["workout-guide exercise illustrations and exercise list"].exists)
        XCTAssertTrue(app.staticTexts["Bryl Lim"].exists)
        XCTAssertTrue(app.buttons["https://github.com/bryllim/workout-guide"].exists)
        XCTAssertTrue(app.buttons["CC BY-SA 4.0"].exists)

        // The upstream the 76 derived frames come from, credited too.
        XCTAssertTrue(app.staticTexts["Everkinetic exercise illustrations"].exists)
        XCTAssertTrue(app.buttons["https://github.com/everkinetic/data"].exists)

        // Criterion 3: a modified image says so, and says what changed.
        let modified = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "Modified:")).firstMatch
        XCTAssertTrue(modified.exists, "a derived image must be marked as modified")
        XCTAssertTrue(modified.label.contains("vector-traced"),
                      "the modification must describe the change, got: \(modified.label)")
    }

    /// The per-author list — the requirement's "alternatively" clause for
    /// row-level author attribution.
    func testAttributionsPageListsExerciseAuthors() {
        openSettings()
        app.buttons["Attributions"].tap()
        XCTAssertTrue(app.navigationBars["Attributions"].waitForExistence(timeout: 10))

        // "Bryl Lim" appears once as the source author and again in the
        // per-exercise author list.
        let authors = app.staticTexts.matching(identifier: "Bryl Lim")
        XCTAssertGreaterThanOrEqual(authors.count, 2,
                                    "the per-exercise author list is missing")
    }

    // MARK: - Graphics

    /// "Every exercise shipped in Almanac must include a demonstration
    /// graphic" — the rendering half. The rule is enforced against the bundle
    /// by `ExerciseGraphicAudit`; this checks the rows actually draw one.
    func testEveryOfferedExerciseShowsADemonstrationGraphic() {
        app.tabBars.buttons["Training"].tap()
        app.buttons["Log training"].tap()
        XCTAssertTrue(app.buttons["Choose an exercise"].waitForExistence(timeout: 10))
        app.buttons["Choose an exercise"].tap()

        XCTAssertTrue(app.navigationBars["Choose Exercise"].waitForExistence(timeout: 10),
                      "the exercise picker never appeared")

        let first = app.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "the catalogue rendered no exercises")
        XCTAssertGreaterThan(app.cells.count, 1, "expected a seeded catalogue, not one row")

        // Every visible row must draw a graphic rather than the placeholder.
        for index in 0..<min(app.cells.count, 5) {
            let cell = app.cells.element(boundBy: index)
            XCTAssertGreaterThan(cell.images.count, 0,
                                 "row \(index) ('\(cell.staticTexts.firstMatch.label)') has no graphic")
        }
    }

    // MARK: - Helpers

    /// iOS collapses a sixth tab into "More", so Settings may be one tap or two
    /// depending on width; handle both rather than pin one layout. The overflow
    /// tabs are presented outside the tab bar, hence the second lookup.
    private func openSettings() {
        let inTabBar = app.tabBars.buttons["Settings"]
        if inTabBar.exists && inTabBar.isHittable {
            inTabBar.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no tab bar to reach Settings from")
        more.tap()
        // The overflow menu is a table, so the tab shows up as a static text
        // inside a cell rather than as a tab-bar button.
        let inOverflow = app.staticTexts["Settings"]
        XCTAssertTrue(inOverflow.waitForExistence(timeout: 5),
                      "Settings is not reachable from the More menu")
        inOverflow.tap()
    }
}
