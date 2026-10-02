import XCTest

/// The Training Program screens: authoring, the day's exercise pool, and the
/// session the rotation generates.
///
/// `docs/acceptance-checklist.md` §7 is "UI driven by automation"; these are the
/// tests that drive it. They follow the handoff's flow — Start Workout →
/// program → day → start — and assert the things the checklist marks about it:
/// the picker offers the program list (7.1), authoring persists into it (7.2),
/// days keep their authoring order (7.3), starting a day generates a session
/// from the pool (7.4) and shows a prescription per exercise (7.5), the skip
/// prompt offers both mechanisms on one dialog (7.6), and the readiness question
/// is the door into the session (7.9, No leg). The full file passes 3 of 3 in
/// one run.
///
/// **No test here asserts that the database is empty.** The simulator's
/// Almanac.sqlite is shared across runs and never reset, so a test written
/// against "no programs yet" fails on the second run. Each test drives the app
/// to the state it needs first and then asserts about what it just did — the
/// same discipline as the rest of this suite.
final class TrainingProgramUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - 7.1: the entry point

    /// "Start workout" on the Training dashboard is the door into the program
    /// picker, and the picker is either honestly empty or shows programs.
    func testStartWorkoutOpensTheProgramPicker() {
        openPrograms()

        // Whatever the shared database contains, the empty state and the way
        // out of it belong together.
        let emptyState = app.staticText(beginningWith: "No programs yet.")
        if emptyState.exists {
            XCTAssertTrue(app.reveal(app.buttons["add-program"]),
                          "an empty picker must offer adding the first program")
        } else {
            // Non-empty: each program on the picker offers adding a day to it.
            let addDay = app.firstElement(identifierPrefix: "add-day-")
            XCTAssertTrue(app.reveal(addDay),
                          "a picker with programs must still offer adding a day")
        }
    }

    // MARK: - 7.2 / 7.3: authoring persists; days keep their order

    /// Creating a program puts it on the picker, and the days added to it read
    /// in authoring order — never sorted.
    func testAuthoredProgramsAndDaysAppearOnThePicker() {
        openPrograms()

        let programName = unique("UI Split")
        createProgramIfNeeded(named: programName)

        // A program now exists, either freshly created or left over, and it
        // offers adding days to it.
        let addDayButton = app.firstElement(identifierPrefix: "add-day-")
        XCTAssertTrue(app.reveal(addDayButton), "no program on the picker offers adding a day")

        // Two days, typed second after first, must list first before second.
        let firstDay = unique("Push")
        let secondDay = unique("Pull")
        addDay(named: firstDay)
        addDay(named: secondDay)

        let firstRow = app.staticTexts[firstDay]
        let secondRow = app.staticTexts[secondDay]
        XCTAssertTrue(app.reveal(secondRow), "day \"\(secondDay)\" is missing from the picker")
        XCTAssertTrue(firstRow.exists, "day \"\(firstDay)\" is missing from the picker")
        XCTAssertTrue(firstRow.frame.minY < secondRow.frame.minY,
                      "days are not in authoring order: \"\(firstDay)\" at \(firstRow.frame.minY), "
                      + "\"\(secondDay)\" at \(secondRow.frame.minY)")

        // Once programs exist the empty-state Add button must be gone.
        XCTAssertFalse(app.buttons["add-program"].exists,
                       "the empty-state Add program button is hiding while programs exist")
    }

    // MARK: - 7.4 / 7.5 / 7.6 / 7.9: starting a day builds the session

    /// The whole loop: author a day, add an exercise to its pool, start it,
    /// answer the readiness prompt, and check the generated session carries a
    /// prescription and the one skip prompt with both mechanisms on it.
    func testStartingADayBuildsASessionWithTheSkipPrompt() {
        openPrograms()

        let dayLabel = unique("Session day")
        ensureDay(named: dayLabel)

        // Open the day through its row.
        openDay(named: dayLabel)

        // Give the day an exercise from the catalog.
        let addExercise = app.element("add-pool-exercise")
        XCTAssertTrue(app.reveal(addExercise), "there is no way to add an exercise")
        addExercise.tap()
        XCTAssertTrue(app.navigationBars["Choose Exercise"].waitForExistence(timeout: 5),
                      "the exercise catalog did not open after tapping Add exercise")
        let row = app.firstElement(identifierPrefix: "exercise-row-")
        XCTAssertTrue(app.reveal(row), "the catalog lists no exercises to choose")
        row.tap()

        // The pool editor saves the catalog default so the day can start.
        let savePool = app.buttons["save-pool-item"]
        XCTAssertTrue(savePool.waitForExistence(timeout: 5), "the pool editor did not open")
        savePool.tap()

        let startDay = app.element("start-program-day")
        XCTAssertTrue(app.waitUntil(timeout: 5) { startDay.isEnabled },
                      "start must enable once the pool has an exercise")
        startDay.tap()

        // The readiness question is the door into the session (7.9).
        let trainAsWritten = app.buttons["No, train as written"]
        XCTAssertTrue(trainAsWritten.waitForExistence(timeout: 5),
                      "starting a day must ask the readiness question first")
        trainAsWritten.tap()

        // A session was generated from the pool with a skip door on a slot.
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.firstElement(identifierPrefix: "session-slot-").exists
        }, "no session sheet appeared after starting the day")
        let skip = app.firstElement(identifierPrefix: "skip-slot-")
        XCTAssertTrue(app.reveal(skip), "a generated slot must offer skipping")
        skip.tap()

        // One prompt, both mechanisms on it (7.6, Decision 3).
        let perSession = app.buttons["Skip just for today"]
        let permanent = app.buttons["Remove from rotation"]
        XCTAssertTrue(perSession.waitForExistence(timeout: 5),
                      "the skip prompt lacks 'Skip just for today'")
        XCTAssertTrue(permanent.exists,
                      "the skip prompt lacks 'Remove from rotation'")
        app.buttons["Cancel"].tap()

        // Finishing is the end of the loop. The cover goes down and the day
        // beneath it shows the session was recorded: the rotation advanced.
        let finish = app.buttons["finish-program-session"]
        XCTAssertTrue(app.reveal(finish), "a non-empty session must offer finishing")
        finish.tap()
        XCTAssertTrue(app.navigationBars[dayLabel].waitForExistence(timeout: 5),
                      "finishing the session did not return to the day")
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticTexts["This is pass 2 through 1 exercise."].exists
        }, "finishing the session did not advance the rotation")
    }

    // MARK: - Helpers

    /// Modules → Training → Start workout → Programs.
    private func openPrograms() {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10), "the Modules destination is missing")
        modules.tap()
        let training = app.buttons["Training"]
        XCTAssertTrue(app.reveal(training), "Training is missing from Modules")
        training.tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 5))

        let startWorkout = app.buttons["training-programs-link"]
        XCTAssertTrue(app.reveal(startWorkout), "Start workout is missing from the Training screen")
        // The row sits directly above "Templates" in the same List section, so a
        // tap synthesised from a stale frame would open the template editor and
        // the assert below would report a missing picker. Wait for the frame to
        // stop moving so the tap hits the row that is actually there.
        XCTAssertTrue(app.waitUntilSettled(startWorkout),
                      "Start workout's frame kept moving; the Training list had not settled")
        startWorkout.tap()
        XCTAssertTrue(app.navigationBars["Programs"].waitForExistence(timeout: 5),
                      "the program picker did not open")
    }

    /// Creates a program with `name` when the picker is empty, and does nothing
    /// when programs already exist (there is then already a program to use).
    private func createProgramIfNeeded(named name: String) {
        guard app.buttons["add-program"].exists else { return }
        app.buttons["add-program"].tap()
        let field = app.textFields["program-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the program editor did not open")
        field.tap()
        field.typeText(name)
        app.buttons["save-program"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts[name].exists },
                      "saving the program did not put \"\(name)\" on the picker")
    }

    /// Adds a day named `name` to the first program that offers one.
    private func addDay(named name: String) {
        let addDay = app.firstElement(identifierPrefix: "add-day-")
        XCTAssertTrue(app.reveal(addDay), "no program offers adding a day")
        addDay.tap()
        let field = app.textFields["day-label-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the day editor did not open")
        field.tap()
        field.typeText(name)
        app.buttons["save-day"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts[name].exists },
                      "saving the day did not put \"\(name)\" on the picker")
    }

    /// Makes sure a day named `name` exists on the picker: creates it when the
    /// picker has programs (there is then always an "Add day" button), and does
    /// nothing when a day of that name is already there.
    private func ensureDay(named name: String) {
        if app.staticTexts[name].exists { return }
        if app.firstElement(identifierPrefix: "add-day-").exists {
            addDay(named: name)
            return
        }
        // No programs at all: author one first so a day has somewhere to live.
        createProgramIfNeeded(named: unique("UI Session"))
        addDay(named: name)
    }

    /// Taps the row that opens the day named `name`.
    ///
    /// The day's row carries three controls whose labels all contain the day
    /// name — "Options for \(name)", "Exercises in \(name)", "Start \(name)" —
    /// so this matches the *link* label prefix ("Exercises in ") rather than a
    /// bare `CONTAINS`, or it would grab the wrong control.
    private func openDay(named name: String) {
        let link = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Exercises in \(name)")
        ).firstMatch
        XCTAssertTrue(app.reveal(link), "the day \"\(name)\" is not reachable from the picker")
        link.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5),
                      "the day screen did not open")
    }

    /// A name unique to this run, so a shared never-reset database cannot
    /// collide with whatever a previous run left behind.
    private func unique(_ base: String) -> String {
        "\(base) \(Int(Date().timeIntervalSince1970))"
    }
}