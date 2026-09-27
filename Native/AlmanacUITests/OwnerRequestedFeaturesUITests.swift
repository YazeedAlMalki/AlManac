import XCTest

/// The screens added on 2026-09-26 from the owner's requests, which until now
/// were verified by nothing.
///
/// These four features — the muscle-grouped exercise library, the religious/
/// intermittent fasting toggle, the per-domain "which source wins" preference,
/// and drink logging — were each written without a single automated check. They
/// were built against a compiler and a database, and visually confirmed by
/// hand, but a refactor could have removed any of them silently. This suite is
/// the net.
///
/// Two things these tests are shaped around:
///
/// - **They run on a virgin database.** The two lazy `Form`s in this app are
///   built from what is in the database, so a populated simulator and an empty
///   one present different screens. CI gets a fresh simulator every run; these
///   tests are written to pass there first.
/// - **They assert intent, not layout.** Row order, section order and swipe
///   counts are not part of what was asked for, so nothing here depends on
///   them. What is asserted is the thing the request was about — that the
///   library is pages inside pages, that the fasting toggle actually changes
///   what is asked for, that a preference is per domain and starts undecided.
final class OwnerRequestedFeaturesUITests: XCTestCase {
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

    // MARK: - Exercise library: muscle → method → exercise

    /// "Muscle group > method of training (bar, cable, machine, etc)."
    ///
    /// The first version was one long list of collapsible sections and the owner
    /// rejected it: it read as a wall. The point of this test is the *nesting*,
    /// so each level is checked by what pushing it reveals — a navigation bar
    /// titled with the thing you tapped, not more rows on the same screen.
    func testExerciseLibraryIsPagesInsidePages() {
        openModule("Training")
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        let browse = app.element("exercise-library-link")
        XCTAssertTrue(app.reveal(browse), "the exercise library must be reachable from Training")
        browse.tap()

        // Level 1 — the muscle list, and only that.
        XCTAssertTrue(app.navigationBars["Muscle groups"].waitForExistence(timeout: 10),
                      "the library must open on a list of muscle groups")
        let muscle = app.firstElement(identifierPrefix: "muscle-")
        XCTAssertTrue(app.reveal(muscle), "the library listed no muscle groups")
        let muscleName = String(muscle.identifier.dropFirst("muscle-".count))
        XCTAssertFalse(muscleName.isEmpty)

        // Level 2 — tapping a muscle pushes a page, it does not expand inline.
        muscle.tap()
        XCTAssertTrue(app.navigationBars[muscleName].waitForExistence(timeout: 10),
                      "tapping \(muscleName) did not push a page of methods")

        let method = app.firstElement(identifierPrefix: "method-")
        XCTAssertTrue(app.reveal(method), "\(muscleName) listed no methods of training")
        let methodName = String(method.identifier.dropFirst("method-".count))
        XCTAssertFalse(methodName.isEmpty)

        // Level 3 — a method pushes a page of exercises.
        method.tap()
        let exercise = app.firstElement(identifierPrefix: "exercise-row-")
        XCTAssertTrue(app.reveal(exercise),
                      "\(muscleName) · \(methodName) listed no exercises")

        // Level 4 — the exercise, where it can be logged and looked back on.
        exercise.tap()
        XCTAssertTrue(app.buttons["log-this-exercise"].waitForExistence(timeout: 10),
                      "an exercise must offer to log itself from its own page")
    }

    /// "When an exercise is entered it should be later tracked so user can know
    /// his past performance in the exercise."
    ///
    /// `ExerciseProgressStore` has existed since 2026-09-18 but had no UI at
    /// all until `ExerciseProgressView`, so nothing checked that reaching it
    /// from a browsed exercise works, or that the page says something when
    /// there is nothing to show. A blank page would satisfy "the button works".
    ///
    /// The three honest states are: nothing logged, one session (too few for a
    /// line), or a chart with dated sessions. This accepts all three and fails
    /// on a blank page, because which one applies depends on what is in the
    /// database and that is not what is under test.
    func testAnExerciseOpensOnAHistoryThatSaysSomethingHonest() {
        openModule("Training")
        let browse = app.element("exercise-library-link")
        XCTAssertTrue(app.reveal(browse))
        browse.tap()
        XCTAssertTrue(app.navigationBars["Muscle groups"].waitForExistence(timeout: 10))

        let muscle = app.firstElement(identifierPrefix: "muscle-")
        XCTAssertTrue(app.reveal(muscle))
        muscle.tap()
        let method = app.firstElement(identifierPrefix: "method-")
        XCTAssertTrue(app.reveal(method))
        method.tap()
        let exercise = app.firstElement(identifierPrefix: "exercise-row-")
        XCTAssertTrue(app.reveal(exercise))
        exercise.tap()

        let nothingLogged = app.staticTexts["No history yet"]
        let oneSession = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "One session logged")
        ).firstMatch
        let datedSessions = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "on ")
        ).firstMatch

        XCTAssertTrue(nothingLogged.waitForExistence(timeout: 5)
                      || oneSession.exists
                      || datedSessions.exists,
                      "an exercise page must say something about the exercise's history — "
                      + "either that there is none, or which sessions there are. "
                      + "A blank page is the failure this is here to catch.")
    }

    // MARK: - Fasting toggle

    /// "Toggle (religious fasting/intermittent fasting)", where religious counts
    /// Fajr→Maghrib and intermittent takes when the user last ate.
    ///
    /// What matters is that the toggle *changes what is asked for* — that is the
    /// whole request, since before it every screen assumed religious.
    func testFastingTogglesBetweenReligiousAndIntermittent() {
        openModule("Fasting")
        XCTAssertTrue(app.navigationBars["Fasting"].waitForExistence(timeout: 10))

        let toggle = app.element("fasting-mode")
        XCTAssertTrue(app.reveal(toggle), "the fasting mode toggle is missing")

        // Religious is the default, and it reports a Fajr→Maghrib window — or,
        // with no location configured, says the window cannot be computed rather
        // than inventing one.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "prayer")
            ).firstMatch.exists,
            "religious mode must talk about prayer times, and must say so when they are not cached")

        // Switching to intermittent asks for a time the user supplies, not for
        // a prayer.
        let intermittent = app.buttons["Intermittent"]
        XCTAssertTrue(app.reveal(intermittent), "the toggle must offer intermittent fasting")
        intermittent.tap()

        let lastAte = app.element("last-ate-at")
        XCTAssertTrue(app.reveal(lastAte),
                      "intermittent mode must ask when the user last ate")
        let start = app.buttons["start-intermittent"]
        XCTAssertTrue(app.reveal(start),
                      "intermittent mode must offer to start the fast from that time")
    }

    // MARK: - Which source wins

    /// "User gets to pick when setting up their profile and can change it later
    /// from settings."
    ///
    /// Per domain, and undecided until asked — those are the two decisions that
    /// were actually made, and both are per-domain rather than global because
    /// there is no defensible global answer.
    func testSyncSourcePreferenceIsPerDomainAndStartsUndecided() {
        openSettings()

        let link = app.element("sync-source-preference-link")
        XCTAssertTrue(app.reveal(link), "the source preference must be reachable from Settings")
        link.tap()
        XCTAssertTrue(app.navigationBars["Which source wins"].waitForExistence(timeout: 10))

        // Every domain is offered, not a subset.
        for domain in ["sleep", "heartRate", "hrv", "steps", "energy",
                       "bodyComposition", "workouts"] {
            XCTAssertTrue(app.reveal(app.element("sync-source-\(domain)")),
                          "the \(domain) domain is not offered a source preference")
        }

        // Nothing is pre-decided. `allPreferences()` is empty on a fresh
        // install, and every row must read as undecided rather than defaulting
        // to a side the user was never asked about.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label == %@", "Undecided")
            ).firstMatch.exists,
            "an unasked domain must read as undecided, not carry a default")

        // Choosing one domain must not decide another — that is the whole
        // reason the preference is per domain.
        let sleep = app.element("sync-source-sleep")
        XCTAssertTrue(app.reveal(sleep))
        sleep.tap()
        let appleHealth = app.buttons["Apple Health"]
        XCTAssertTrue(appleHealth.waitForExistence(timeout: 5),
                      "choosing a source must offer the built-in sources")
        appleHealth.tap()

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Undecided")
        ).firstMatch.exists,
        "deciding sleep must leave the other domains undecided")
    }

    // MARK: - Drink logging

    /// "Water logging: add other drinks, counted with his calories."
    ///
    /// A drink has to be pickable, loggable, and then counted — a screen that
    /// accepts a drink and never reports its calories anywhere would pass a
    /// test that only checked the first half.
    ///
    /// Pepsi specifically, not "the first drink": the catalogue is ordered with
    /// `catalog_water` first, and water is 0 kcal, so water is legitimately
    /// absent from a calorie total. Picking the first row and then asserting one
    /// would have been a test that could only ever fail.
    func testLoggingADrinkShowsItOnTheDashboardWithCalories() {
        openModule("Hydration")
        XCTAssertTrue(app.navigationBars["Hydration"].waitForExistence(timeout: 10))

        let log = app.buttons["Log a drink"]
        XCTAssertTrue(app.reveal(log), "logging a drink must be reachable from Hydration")
        log.tap()
        XCTAssertTrue(app.navigationBars["Log a drink"].waitForExistence(timeout: 10),
                      "the drink logger did not open")

        // 355 mL, 150 kcal in `DrinkCatalog` — a drink that carries calories, so
        // the request's "counted with his calories" is actually exercised.
        let drink = app.element("drink-row-catalog_pepsi")
        XCTAssertTrue(app.reveal(drink), "the drink catalogue did not offer Pepsi")
        drink.tap()

        // The amount section only exists once a drink is chosen, and the
        // nutrition summary with it.
        let logButton = app.buttons["Log"]
        XCTAssertTrue(app.reveal(logButton), "the Log button must appear once a drink is chosen")
        logButton.tap()

        // The sheet dismisses itself *only* when the service returned no
        // warnings (`HydrationLoggingView`, line 212) — and on a re-run it will
        // warn "Similar drink logged Ns ago", so it deliberately stays open to
        // be read. Asserting a dismissal that may not happen was a test that
        // passed on a fresh simulator and failed on the second run.
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        XCTAssertTrue(app.navigationBars["Log a drink"].waitForNonExistence(timeout: 10),
                      "the drink logger did not close, so the dashboard cannot be read")

        // And the drink itself is listed by name, not just rolled into a number.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "Pepsi")
            ).firstMatch.exists,
            "the logged drink must be listed on the dashboard by name")

        // The separate line is gone from *this* screen. Checked here, while
        // Hydration is still on screen: after navigating to Today the query
        // would answer trivially, and an assertion that cannot fail is not one.
        // This is the only check in the test that can only pass after the
        // 2026-09-27 change, so it is what catches the section being restored.
        XCTAssertFalse(app.staticTexts["From drinks"].exists,
                       "the separate drink-calorie line was superseded and must not come back")

        // The drink's calories are part of the day's *one* energy total, on
        // Today, rather than a second figure here. So the assertion has to go
        // there: a drink this screen accepts but that never reaches the day's
        // total would pass a check that only looked at Hydration.
        //
        // This is the reverse of what the test asserted until 2026-09-27, when
        // a "From drinks" line kept the two apart on purpose.
        // `owner-decisions` §6 argued for that on the grounds that a catalog
        // drink is an uncited estimate and food is a cited figure, so summing
        // them would launder one into the other. The owner chose the other
        // branch. The reasoning still describes the data — the qualifier is
        // still written per row to `hydration_log.value_qualifier` and the
        // per-drink labels in the logger are untouched — so what the total
        // gives up is only the visible separation, and says so in words instead.
        //
        // Getting there by tapping the "Today" tab works, and not for the
        // reason a `TabView` usually does: Hydration is a `NavigationLink`
        // pushed inside the Today destination's own `NavigationStack`, so
        // tapping the already-selected tab is normally a no-op that leaves the
        // stack pushed. Here it is not — the tap comes back to the Today root
        // with the stack unwound. Recorded because it reads as a bug, and the
        // obvious "fix" (relaunching, or unwinding by hand) swaps working
        // navigation for something slower and just as easy to get wrong.
        let todayTab = app.buttons["Today"].firstMatch
        XCTAssertTrue(todayTab.waitForExistence(timeout: 10),
                      "the Today tab must be reachable from a logged module")
        todayTab.tap()

        // The metric rows sit at the top of Today, so come back up before
        // reading them.
        for _ in 0..<8 { app.swipeDown() }

        // So ask the question of the screen's own words rather than of a query
        // for one of them. XCTest keeps off-screen rows in the tree either way,
        // which is the point: an assertion phrased as "scroll to this text"
        // cannot report the case where the text is absent, because walking to
        // the end of the page still ends in a failure that reads like "not on
        // this screen" rather than "not on any screen" — and takes twenty-four
        // swipes to say it.
        //
        // Matched on the whole shape, not the exact string, because two things
        // vary and neither is what is being tested: whether food is also logged
        // turns "1 drink counted" into "3 foods and 1 drink counted", and a
        // re-run logs a second Pepsi, so the count is not always one. This suite
        // has to pass on a virgin and a populated database alike.
        //
        // Both words are required. Bare "drink" would also match a stray mention
        // elsewhere on the screen and pass on a day where the drink had not been
        // counted at all — the failure this test exists to catch. "counted" is
        // `DayEnergy.summary`'s word and nothing else's.
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(
            labels.contains {
                $0.localizedCaseInsensitiveContains("drink")
                    && $0.localizedCaseInsensitiveContains("counted")
            },
            """
            a logged drink's calories must reach the day's energy total and be \
            named in it on Today
            on screen: \(labels)
            """)
    }

    // MARK: - Helpers

    private func openModule(_ name: String) {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 15), "the Modules destination is missing")
        modules.tap()
        let link = app.buttons[name]
        XCTAssertTrue(app.reveal(link), "\(name) is not reachable from Modules")
        link.tap()
    }

    private func openSettings() {
        openModule("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10),
                      "Settings did not open")
    }
}
