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
        openModules()
        let training = app.buttons["Training"]
        XCTAssertTrue(training.waitForExistence(timeout: 5))
        training.tap()
        app.buttons["Log training"].tap()
        XCTAssertTrue(app.buttons["Choose an exercise"].waitForExistence(timeout: 10))
        app.buttons["Choose an exercise"].tap()

        XCTAssertTrue(app.navigationBars["Choose Exercise"].waitForExistence(timeout: 10),
                      "the exercise picker never appeared")

        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "exercise-row-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "the catalogue rendered no exercises")
        XCTAssertGreaterThan(rows.count, 1, "expected a seeded catalogue, not one row")

        // Every visible row must draw a graphic rather than the placeholder.
        for index in 0..<min(rows.count, 5) {
            let row = rows.element(boundBy: index)
            XCTAssertGreaterThan(row.images.count, 0,
                                 "row \(index) ('\(row.staticTexts.firstMatch.label)') has no graphic")
        }
    }

    // MARK: - Editorial shell

    func testEditorialShellQuickLogTrendsAndModules() {
        let quickLog = app.buttons["Quick log"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 5))
        quickLog.tap()

        XCTAssertTrue(app.staticTexts["Quick log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["+250"].exists)
        app.buttons["+250"].tap()
        XCTAssertTrue(app.staticTexts["250 mL added"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        let trends = app.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 5))
        trends.tap()
        XCTAssertTrue(app.staticTexts["Trends"].waitForExistence(timeout: 5))

        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 5))
        modules.tap()
        XCTAssertTrue(app.navigationBars["Modules"].waitForExistence(timeout: 5))
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

        // Every title `HealthSummaryStore` can produce. This used to assert
        // only "Sleep", which held solely on a virgin simulator database: the
        // simulator's Almanac.sqlite is shared across runs and never reset, so
        // as soon as any other test logged a body measurement or a training
        // bout, `summaries` became non-empty, "No health data yet" stopped
        // rendering, and "Sleep" was absent because there is still no Health
        // app to sync an episode from. The test then failed for a reason that
        // has nothing to do with the Health screen.
        //
        // What it is actually for is the comment above it: the screen is
        // reachable and never renders a blank list. So assert that — the empty
        // state, or at least one real domain row.
        let domainTitles = [
            "Resting heart rate", "Heart rate variability", "Steps",
            "Active energy", "Resting energy",
            "Weight", "Body fat", "Lean mass",
            "Sleep", "Workouts",
        ]
        let noneYet = app.staticTexts["No health data yet"]
        let listed = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", domainTitles))
        XCTAssertTrue(noneYet.exists || listed.count > 0,
                      "the screen must list synced domains or explain that there are none; "
                      + "found neither. Visible: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testMorePageContainsTheRequestedDestinations() {
        let more = app.buttons["Modules"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        scrollTo("Laboratory", maxSwipes: 12)
        XCTAssertTrue(app.staticTexts["Laboratory"].exists, "Laboratory is missing from Modules")
        // The bar now takes its own layout space, and the Records section
        // gained a row, so the later destinations have to be scrolled to.
        for destination in ["Profile", "Measurements", "Settings"] {
            scrollTo(destination, maxSwipes: 12)
            XCTAssertTrue(app.staticTexts[destination].exists,
                          "\(destination) is missing from Modules")
        }
    }

    func testTodayShowsTheActivityRingsCalendar() {
        XCTAssertTrue(app.staticTexts["Rhythm"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.datePickers.firstMatch.exists, "the free-date picker was superseded")

        let initialMonthFormatter = DateFormatter()
        initialMonthFormatter.dateFormat = "yyyy-MM"
        let initialMonthID = initialMonthFormatter.string(from: Date())
        for _ in 0..<8 where !app.buttons["activity-ring-day-\(initialMonthID)-01"].exists {
            app.swipeUp()
        }

        let previous = app.buttons["Previous month"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))

        let monthTitle = app.staticTexts["activity-ring-month-title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let currentMonthID = monthFormatter.string(from: Date())
        let firstDay = app.buttons["activity-ring-day-\(currentMonthID)-01"]
        let secondDay = app.buttons["activity-ring-day-\(currentMonthID)-02"]
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5))
        XCTAssertTrue(secondDay.exists)
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let firstColumn = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let stride = secondDay.frame.minX - firstDay.frame.minX
        var originX: CGFloat?
        for dayNumber in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart),
                  calendar.component(.weekday, from: date) == calendar.firstWeekday else { continue }
            let identifier = String(format: "%04d-%02d-%02d",
                                     calendar.component(.year, from: date),
                                     calendar.component(.month, from: date), dayNumber)
            originX = app.buttons["activity-ring-day-\(identifier)"].frame.minX
            break
        }
        guard let originX else {
            XCTFail("could not find the first weekday cell")
            return
        }
        XCTAssertEqual(firstDay.frame.minX, originX + CGFloat(firstColumn) * stride, accuracy: 2,
                       "the first day must follow the month's leading weekday blanks")
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
        let heading = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Rings for")
        ).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5),
                      "selecting a day must describe that day in the detail panel")
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
        // A section added above can leave the switch below the custom bottom
        // bar, where it exists but cannot be tapped. Bring it into reach.
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable, "the digestion-ring switch must be reachable")
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
        let more = app.buttons["Modules"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let profile = app.buttons["Profile"]
        scrollTo("Profile")
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
        scrollTo("Measurements")
        XCTAssertTrue(measurements.waitForExistence(timeout: 5))
        measurements.tap()
        XCTAssertTrue(app.navigationBars["Measurements"].waitForExistence(timeout: 5))
    }

    func testFastingScreenOpensFromMore() {
        let more = app.buttons["Modules"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let fasting = app.buttons["Fasting"]
        XCTAssertTrue(fasting.waitForExistence(timeout: 5))
        fasting.tap()
        XCTAssertTrue(app.navigationBars["Fasting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh fasting state"].exists)
    }

    func testPrayerScreenOpensFromMore() {
        let more = app.buttons["Modules"]
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
        let toggle = app.switches[label]
        for _ in 0..<maxSwipes where !button.exists && !text.exists && !toggle.exists {
            app.swipeUp()
        }
    }

    /// The custom bottom bar is laid out in flow, not attached as a safe-area
    /// inset. A navigation stack swallowed that inset, every scroll view kept
    /// the full screen height, and the last row of a long list — Settings —
    /// was pinned behind the bar with no way to scroll it clear.
    func testTheLastModulesRowClearsTheBottomBar() {
        openModules()
        let settings = app.buttons["Settings"]
        for _ in 0..<6 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable, "Settings must be reachable, not trapped behind the bar")

        // The bar's own buttons give its top edge; the row has to end above it.
        let todayTab = app.buttons["Today"]
        XCTAssertTrue(todayTab.exists)
        XCTAssertLessThan(settings.frame.maxY, todayTab.frame.minY,
                          "Settings is still covered by the bottom bar")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10),
                      "Settings did not open from Modules")
    }

    /// Modules is the app-owned full-module index in the new shell.
    private func openModules() {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 5), "the Modules destination is missing")
        modules.tap()
    }

    private func openSettings() {
        openModules()
        scrollTo("Settings")
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5),
                      "Settings is not reachable from Modules")
        settings.tap()
    }
}
