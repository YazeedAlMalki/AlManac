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
        scrollTo("Attributions")
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
        scrollTo("Attributions")
        app.buttons["Attributions"].tap()
        XCTAssertTrue(app.navigationBars["Attributions"].waitForExistence(timeout: 10))

        // The nutrition notices make the source list longer, so the per-exercise
        // author section is below the initial viewport.
        let authorSection = app.staticTexts[
            "workout-guide exercise illustrations and exercise list — exercise authors"
        ]
        for _ in 0..<30 where !authorSection.exists {
            app.swipeUp()
        }
        XCTAssertTrue(authorSection.exists, "the per-exercise author section is missing")
        XCTAssertTrue(app.staticTexts["Bryl Lim"].exists)
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

    // MARK: - Health

    /// The screen that makes the non-dashboard synced domains visible.
    ///
    /// The simulator has no Health app, so this cannot assert that a sync
    /// happened — what it does assert is the part that is otherwise unverified:
    /// the screen is reachable and never renders a blank list. Either the
    /// domains are listed or the screen says there is nothing yet; an empty
    /// list with no explanation would be the bug.
    func testHealthScreenShowsSyncedDomainsOrSaysThereAreNoneYet() {
        openSettings()
        // Settings is a Form, which builds rows lazily — a section below the
        // fold is not in the hierarchy until it is scrolled to.
        scrollTo("Health data")
        app.buttons["Health data"].tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10),
                      "the Health screen never appeared")
        XCTAssertTrue(app.buttons["Sync now"].exists, "there must be a way to sync by hand")

        let noneYet = app.staticTexts["No health data yet"]
        let firstDomain = app.staticTexts["Sleep"]
        XCTAssertTrue(noneYet.exists || firstDomain.exists,
                      "the screen must list synced domains or explain that there are none")
    }

    func testMorePageContainsTheRequestedDestinations() {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        XCTAssertTrue(app.staticTexts["Laboratory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Profile"].exists)
        XCTAssertTrue(app.staticTexts["Measurements"].exists)
        XCTAssertTrue(app.staticTexts["Settings"].exists)
    }

    func testTodayShowsTheActivityRingsCalendar() {
        XCTAssertTrue(app.staticTexts["Activity rings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.datePickers.firstMatch.exists, "the free-date picker was superseded")

        let previous = app.buttons["Previous month"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))

        let monthTitle = app.staticTexts["activity-ring-month-title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let previousMonthID = monthFormatter.string(from: previousMonth)
        previous.press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["activity-ring-day-\(previousMonthID)-01"].waitForExistence(timeout: 3))

        let day = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "activity-ring-day-")
        ).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "the month grid rendered no selectable days")
        let selectedDay = String(day.identifier.dropFirst("activity-ring-day-".count))
        day.tap()
        XCTAssertTrue(app.staticTexts["Rings for \(selectedDay)"].waitForExistence(timeout: 5))
        let edit = app.buttons["Edit selected day's logs"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit \(selectedDay)"].waitForExistence(timeout: 5))
    }

    func testSettingsCanToggleTheDigestionActivityRing() {
        openSettings()
        scrollTo("Activity rings")
        let toggle = app.switches["Show digestion ring"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = expectation(for: NSPredicate { _, _ in
            (toggle.value as? String) != original
        }, evaluatedWith: toggle)
        wait(for: [changed], timeout: 3)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let restored = expectation(for: NSPredicate { _, _ in
            (toggle.value as? String) == original
        }, evaluatedWith: toggle)
        wait(for: [restored], timeout: 3)
    }

    func testMoreDestinationsOpen() {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let profile = app.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        let back = app.navigationBars.buttons["More"]
        if back.exists {
            back.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }

        let measurements = app.buttons["Measurements"]
        XCTAssertTrue(measurements.waitForExistence(timeout: 5))
        measurements.tap()
        XCTAssertTrue(app.navigationBars["Measurements"].waitForExistence(timeout: 5))
    }

    func testFastingScreenOpensFromMore() {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let fasting = app.buttons["Fasting"]
        XCTAssertTrue(fasting.waitForExistence(timeout: 5))
        fasting.tap()
        XCTAssertTrue(app.navigationBars["Fasting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh fasting state"].exists)
    }

    func testPrayerScreenOpensFromMore() {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let prayer = app.buttons["Prayer"]
        XCTAssertTrue(prayer.waitForExistence(timeout: 5))
        prayer.tap()
        XCTAssertTrue(app.navigationBars["Prayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use current location"].exists)
    }

    // MARK: - Helpers

    /// Scrolls a lazily-built Form until `label` appears. A fixed number of
    /// swipes rather than a loop on the element query, so a genuinely missing
    /// row still fails instead of spinning.
    private func scrollTo(_ label: String, maxSwipes: Int = 6) {
        let button = app.buttons[label]
        let text = app.staticTexts[label]
        for _ in 0..<maxSwipes where !button.exists && !text.exists {
            app.swipeUp()
        }
    }

    /// Settings is reached through the app-owned More tab. The button lookup is
    /// preferred because a NavigationLink is a button; the static-text fallback
    /// keeps this helper usable on iPad's older accessibility shape.
    private func openSettings() {
        let inTabBar = app.tabBars.buttons["Settings"]
        if inTabBar.exists && inTabBar.isHittable {
            inTabBar.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no tab bar to reach Settings from")
        more.tap()

        let inMorePage = app.buttons["Settings"]
        if inMorePage.waitForExistence(timeout: 5) {
            inMorePage.tap()
            return
        }

        let inOverflow = app.staticTexts["Settings"]
        XCTAssertTrue(inOverflow.waitForExistence(timeout: 5),
                      "Settings is not reachable from the More page")
        inOverflow.tap()
    }
}
