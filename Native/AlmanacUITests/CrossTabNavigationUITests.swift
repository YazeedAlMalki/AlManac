import XCTest

/// Cross-tab navigation: tapping a button that names a feature lands on that
/// feature, changing tab if it has to.
///
/// The routing *rules* are unit-tested in `TabRoutingTests` — 16 tests over the
/// pure functions, which is where the decisions actually live. What only this
/// suite can catch is the seam those rules drive: that a row on Today is a
/// button at all, what it is called, and that tapping it really changes the
/// bar's selection rather than only the pushed stack. Those are the failures
/// that look like "the button does nothing" and are invisible to anything below
/// the view layer.
final class CrossTabNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // The launch-time guards mean a broken build shows this instead of the
        // app. Fail with the reason rather than a timeout on an unrelated
        // element — the same guard the other suites use.
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - Today is not a dead end

    /// The core of the requirement. Today's "Today's record" card names four
    /// features; three of them have screens in the app, and tapping a name must
    /// take you to the screen rather than leaving you on Today.
    func testTappingAFeatureNameOnTodayLandsOnThatFeature() {
        for feature in ["Hydration", "Nutrition", "Training"] {
            app.terminate()
            app.launch()

            openToday()
            let row = todayRecordRow(feature)
            XCTAssertTrue(app.reveal(row), "\(feature) is not a tappable row on Today")
            row.tap()

            // Two things have to be true, and asserting only the first is the
            // mistake this test exists to prevent: the screen appeared, *and*
            // the bar moved to the tab that owns it. A coordinator that pushed
            // onto a path the bar was not watching produces the first and not
            // the second — you land somewhere with no bar item selected, which
            // reads as a broken app rather than as a navigation bug.
            XCTAssertTrue(app.navigationBars[feature].firstMatch.waitForExistence(timeout: 10),
                          "tapping \(feature) on Today did not open \(feature)")
            XCTAssertTrue(tab("modules").waitForExistence(timeout: 5))
            XCTAssertTrue(tab("modules").isSelected,
                          "after tapping \(feature) the Modules tab is not selected, so the "
                          + "screen was pushed without the tab changing")
        }
    }

    /// Sleep sits in the same card and is deliberately *not* a button.
    ///
    /// It is read from Apple Health and nothing in Almanac writes it, so there is
    /// nowhere to go. Pinning that it is not a button matters because the
    /// failure mode is symmetric with the test above and just as bad: a button
    /// that goes nowhere is a promise the app cannot keep, and VoiceOver
    /// announces it as actionable.
    func testSleepIsAReadingNotADoor() {
        openToday()
        XCTAssertTrue(app.reveal(app.staticTexts["Sleep"]),
                      "the Sleep row is missing from Today's record")
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Sleep")).firstMatch.exists,
                       "Sleep has no screen in Almanac, so it must not be presented as a button")
    }

    // MARK: - The tab you leave is the tab you come back to

    /// The promise that makes cross-tab navigation safe: switching tabs to
    /// follow a link does not silently reset where you were.
    ///
    /// Before this change the only way to reach a feature was the Modules tab,
    /// so this could not regress. Now that a link can move you there, it can —
    /// and "I went to Hydration from Today and Trends reset" is exactly the kind
    /// of quiet bug nobody reports until much later.
    func testFollowingACrossTabLinkDoesNotResetTheTabYouLeft() {
        // Go to Trends first, so there is a tab worth preserving.
        tab("trends").tap()
        XCTAssertTrue(tab("trends").isSelected, "the Trends tab did not become selected")
        XCTAssertTrue(isOnTrends(), "the Trends screen never appeared")

        // Leave via a cross-tab link from Today.
        openToday()
        let hydration = todayRecordRow("Hydration")
        XCTAssertTrue(app.reveal(hydration), "Hydration is not a tappable row on Today")
        hydration.tap()
        XCTAssertTrue(app.navigationBars["Hydration"].firstMatch.waitForExistence(timeout: 10))

        // Come back. Trends must still be showing its own screen, not a reset
        // spinner, a blank page, or Today's content left over from before.
        tab("trends").tap()
        XCTAssertTrue(tab("trends").isSelected, "Trends did not become selected again")
        XCTAssertTrue(isOnTrends(), "Trends did not survive being navigated away from")
    }

    // MARK: - The menu and the router are one list

    /// Every screen the Modules menu offers must be reachable by tapping it.
    ///
    /// The menu is generated from the same `AppRoute` list the router uses, so
    /// this is really a check that the *destination switch* covers every case —
    /// a route with a menu row and no screen would build cleanly (the switch is
    /// exhaustive) but push nothing, and only this catches it.
    func testEveryModulesRowOpensItsScreen() {
        for feature in ["Training", "Hydration", "Nutrition", "Fasting", "Prayer", "Laboratory", "Profile"] {
            app.terminate()
            app.launch()
            openModules()

            let row = app.buttons[feature]
            XCTAssertTrue(app.reveal(row), "\(feature) has a menu row but cannot be reached")
            row.tap()
            XCTAssertTrue(app.navigationBars[feature].firstMatch.waitForExistence(timeout: 10),
                          "tapping \(feature) in the Modules menu did not open it")
        }
    }

    // MARK: - Helpers

    /// One of the bar's three destinations, addressed by identifier.
    ///
    /// Not by label, which is the obvious choice and is wrong. The bar is
    /// hand-built, so it has no `tabBar` to scope a query to, and "Modules"
    /// names two buttons the moment a screen is pushed: this tab, and the
    /// navigation bar's back button, which is labelled with the screen it came
    /// from. Querying by label fails with "multiple matching elements" at
    /// exactly the moment the test has something interesting to say.
    /// `AppTab`'s raw value, spelled out because the UI test target does not
    /// link `AlmanacCore` and cannot read the enum. The three values are fixed
    /// by the bar's layout, so this cannot drift without the identifier scheme
    /// changing — and if it does, every test in this file fails loudly rather
    /// than quietly passing against a stale string.
    private func tab(_ name: String) -> XCUIElement {
        app.buttons["tab-\(name)"]
    }

    /// The row for `feature` in Today's record card.
    ///
    /// Matched on a *prefix* rather than the whole label, because the label
    /// carries the reading too: measured on a simulator it is
    /// "Hydration, of 2000 mL, 0 mL", and the numbers move with the day's data.
    /// An exact match would pass on an empty day and fail on a logged one —
    /// the suite has to survive both, which is the same constraint the other
    /// suites document.
    ///
    /// `BEGINSWITH` rather than `CONTAINS` on purpose. "Hydration" and
    /// "Nutrition" also appear inside every activity-ring day button's label
    /// ("Tue 1 Sep, Hydration incomplete, …"), and a contains-match would pick
    /// one of those up and tap a calendar square instead of the row.
    private func todayRecordRow(_ feature: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", feature)).firstMatch
    }

    /// True when the Trends screen's own content is on screen.
    ///
    /// Trends draws its own title and has no navigation bar at all — measured,
    /// `app.navigationBars` is empty there — so "we are on Trends" cannot be
    /// asked of a nav bar the way every other assertion in this file asks it.
    /// The sentence under the Trends heading is the right witness: it is
    /// unique to that screen, and unlike the range picker's "30 days" it does
    /// not change with the data.
    private func isOnTrends() -> Bool {
        app.waitUntil(timeout: 8) {
            app.staticTexts.allElementsBoundByIndex.contains {
                $0.label.hasPrefix("Readiness for every day")
            }
        }
    }

    private func openToday() {
        let today = tab("today")
        XCTAssertTrue(today.waitForExistence(timeout: 10), "the Today destination is missing")
        if !today.isSelected { today.tap() }
        // Today's content arrives asynchronously. Without this the reveal loop
        // below can start swiping a screen that has not drawn its cards yet, and
        // a swipe on an empty scroll view looks exactly like a screen where the
        // row is missing.
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.buttons.count > 3 },
                      "Today never finished loading")
    }

    private func openModules() {
        tab("modules").tap()
        XCTAssertTrue(app.navigationBars["Modules"].firstMatch.waitForExistence(timeout: 10),
                      "the Modules menu did not open")
    }
}
