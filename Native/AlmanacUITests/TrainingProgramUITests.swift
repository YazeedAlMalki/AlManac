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
/// is the door into the session (7.9, No leg). Then the rest of the rotation's
/// mechanics, all driven rather than core-read: skip-for-today re-offers the
/// exercise next session (7.7), permanent removal drops it and re-adding
/// restores it (7.8), the variant selector offers the five answers (7.12),
/// entering actuals updates both graphs (7.13), the separate/combined toggle
/// applies to both graphs with its comparability note (7.14/7.15), nil-variant
/// history still draws a series in separate mode (7.16), and abandoning or
/// deleting a session consumes no rotation step (7.17). The full file passes
/// these over the shared never-reset simulator database.
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

    // MARK: - 7.7 / 7.8: the two skip mechanisms, beyond one dialog

    /// "Skip just for today" holds a slot for this session only. The next pass
    /// of the day offers the exercise again (7.7, Decision 3's per-session leg).
    func testSkippingForTodayReoffersTheExerciseNextSession() {
        openPrograms()

        let dayLabel = unique("Skip day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        addExercise(1)
        addExercise(69)

        startCurrentDay()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Bench Press"].exists },
                      "Bench Press is missing from the first session")
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Ab Wheel Rollout"].exists },
                      "Ab Wheel Rollout is missing from the first session")

        // Skip just today: the slot is held, with a way back out.
        let skip = app.firstElement(identifierPrefix: "skip-slot-")
        XCTAssertTrue(app.reveal(skip), "a generated slot must offer skipping")
        skip.tap()
        let perSession = app.buttons["Skip just for today"]
        XCTAssertTrue(perSession.waitForExistence(timeout: 5), "the skip prompt has no per-session answer")
        perSession.tap()

        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Held this session"].exists },
                      "a per-session skip must show the held slot")
        let undo = app.buttons["undo-skip-slot-0"]
        // The held row sits below the fold of the sheet's lazy list, so it has
        // to be scrolled into existence before it can be checked or tapped.
        XCTAssertTrue(app.reveal(undo), "a held slot must be undoable")
        XCTAssertTrue(undo.label.contains("Undo"),
                      "the held row must offer undoing the skip")

        finishCurrentSession(returningToDay: dayLabel)
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticText(beginningWith: "This is pass 2").exists
        }, "finishing the skipped session did not advance the rotation")

        // Next pass: the held exercise is offered again.
        startCurrentDay()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Pass 2"].exists },
                      "the second pass of the day is not labelled pass 2")
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Bench Press"].exists },
                      "skip-for-today did not re-offer the exercise next session")
        abandonCurrentSession(dayLabel: dayLabel)
    }

    /// "Remove from rotation" drops the exercise until it is put back, and
    /// re-adding restores its position (7.8, Decision 3's permanent leg).
    func testRemovingFromRotationThenRestoringItsPosition() {
        openPrograms()

        let dayLabel = unique("Drop day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        addExercise(1)
        addExercise(69)

        startCurrentDay()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Bench Press"].exists },
                      "Bench Press is missing from the first session")

        // Remove permanently. The sheet that is already open keeps the plan it
        // was built with, so the removal is judged on the day and on a *fresh*
        // session, never on that sheet.
        let skip = app.firstElement(identifierPrefix: "skip-slot-")
        XCTAssertTrue(app.reveal(skip), "a generated slot must offer skipping")
        skip.tap()
        let permanent = app.buttons["Remove from rotation"]
        XCTAssertTrue(permanent.waitForExistence(timeout: 5), "the skip prompt has no permanent answer")
        permanent.tap()
        abandonCurrentSession(dayLabel: dayLabel)

        // The day says so: the item is greyed as removed and back-able.
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticText(beginningWith: "Removed from rotation").exists
        }, "the day does not show the removed exercise as out of rotation")
        XCTAssertTrue(app.staticTexts["1 of 2 in rotation"].exists,
                      "the rotation summary does not count the removed exercise as out")
        let putBack = app.firstElement(identifierPrefix: "restore-pool-item-")
        XCTAssertTrue(app.reveal(putBack), "a removed exercise must offer putting it back")

        // A fresh start never offers the removed exercise. The assertion is scoped
        // to the session's slot; the day's pool text still shows the removed
        // row under the presented sheet, so a whole-app absence check cannot hold.
        startCurrentDay()
        let removedSlot = app.firstElement(identifierPrefix: "session-slot-")
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            removedSlot.exists && !removedSlot.label.contains("Bench Press")
        }, "a removed exercise must not be offered again until re-added")
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.firstElement(identifierPrefix: "session-slot-").label.contains("Ab Wheel Rollout")
        }, "the fresh session must offer the remaining exercise in its place")
        abandonCurrentSession(dayLabel: dayLabel)

        // ...and putting it back restores it: it appears again next session.
        putBack.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            !app.staticText(beginningWith: "Removed from rotation").exists
        }, "putting an exercise back did not re-activate it")
        XCTAssertTrue(app.staticTexts["2 in rotation"].exists,
                      "putting the exercise back did not restore the rotation count")

        startCurrentDay()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Bench Press"].exists },
                      "re-adding an exercise did not restore it to the rotation")
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Ab Wheel Rollout"].exists },
                      "the day lost its other exercise after re-adding")
        abandonCurrentSession(dayLabel: dayLabel)
    }

    // MARK: - 7.12: the equipment variant selector

    /// The selector on a generated slot offers exactly the five answers
    /// Decision 1 allows — "Not recorded" plus the four equipment variants —
    /// and records which one was chosen.
    func testEquipmentVariantPickerOffersTheFiveAnswers() {
        openPrograms()

        let dayLabel = unique("Variant day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        addExercise(1)

        startCurrentDay()
        let picker = app.firstElement(identifierPrefix: "variant-picker-")
        XCTAssertTrue(app.reveal(picker), "a generated slot must carry an equipment selector")
        picker.tap()

        // One prompt, five answers.
        for answer in ["Not recorded", "Barbell", "Dumbbell", "Cable", "Machine"] {
            let option = app.buttons[answer]
            XCTAssertTrue(option.waitForExistence(timeout: 5),
                          "the variant selector does not offer \"\(answer)\"")
        }

        // Choosing one records it on the control.
        app.buttons["Barbell"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            let valueText = (picker.value as? String) ?? ""
            return picker.label.contains("Barbell") || valueText.contains("Barbell")
        }, "selecting a variant did not record it on the selector (now: \(picker.label))")
        abandonCurrentSession(dayLabel: dayLabel)
    }

    // MARK: - 7.13 / 7.16: actuals reach the graphs

    /// Entering actuals updates the two graphs: the finished bout appears on
    /// the Load graph (its recorded load) and on the Reps-performed graph
    /// (its sets × reps) (7.13).
    func testEnteringActualsUpdatesBothGraphs() {
        openPrograms()

        let dayLabel = unique("Graph day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        // A load-bearing exercise with a prescription load, so both graphs have
        // a measure to plot: weight takes the load, volume takes sets × reps.
        addExercise(1, withLoad: 4)

        startCurrentDay()
        let markDone = app.firstElement(identifierPrefix: "mark-done-")
        XCTAssertTrue(app.reveal(markDone), "a generated slot must offer marking its bout done")
        markDone.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !markDone.isEnabled },
                      "marking the bout done did not register its actuals")
        finishCurrentSession(returningToDay: dayLabel)

        openExerciseHistory(1, named: "Bench Press")

        XCTAssertNotNil(loggedDetail(ofGraph: "weight-graph"),
                        "the Load graph gained no point from the recorded load")
        XCTAssertNotNil(loggedDetail(ofGraph: "volume-graph"),
                        "the Reps-performed graph gained no point from the recorded actuals")
    }

    /// An exercise whose history is all pre-migration — nil variant, and a
    /// bodyweight movement at that — still draws a series in the default
    /// separate mode (7.16). The volume graph counts its reps; the weight
    /// graph honestly says there is no load rather than plotting zero.
    func testPreMigrationHistoryStillDrawsASeriesInSeparateMode() {
        openPrograms()

        let dayLabel = unique("Bodyweight day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        addExercise(69)

        startCurrentDay()
        // Finished without touching the variant selector: the bout records no
        // equipment variant, exactly like pre-Migration049 history.
        let markDone = app.firstElement(identifierPrefix: "mark-done-")
        XCTAssertTrue(app.reveal(markDone), "a generated slot must offer marking its bout done")
        markDone.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !markDone.isEnabled },
                      "marking the bout done did not register its actuals")
        finishCurrentSession(returningToDay: dayLabel)

        openExerciseHistory(69, named: "Ab Wheel Rollout")

        // Separate mode is the default, and the nil-variant series has points.
        XCTAssertNotNil(loggedDetail(ofGraph: "volume-graph"),
                        "the volume graph drew no series for the nil-variant history")
        XCTAssertTrue(app.staticTexts["No logged load for this exercise. A bodyweight movement has none to plot."].exists,
                      "the weight graph must say there is no load, not plot one")

        // The mode toggle reads the same nil-variant history in both directions.
        XCTAssertTrue(app.reveal(app.buttons["Combined"]), "the separate/combined toggle is missing")
        app.buttons["Combined"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { loggedDetail(ofGraph: "volume-graph") != nil },
                      "combined mode lost the nil-variant series")
        app.buttons["Separate"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { loggedDetail(ofGraph: "volume-graph") != nil },
                      "separate mode lost the nil-variant series")
    }

    // MARK: - 7.14 / 7.15: the separate/combined radio

    /// The separate/combined toggle governs both graphs at once (7.14), and
    /// combined mode is the only one that carries the comparability note
    /// (7.15). The toggle is a read — it never rewrites the log — so the same
    /// bout list is what both modes draw.
    func testVariantModeToggleAppliesToBothGraphsAndShowsTheNote() {
        openPrograms()

        let dayLabel = unique("Toggle day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        addExercise(1)

        // The graphs only render once the exercise has logged history.
        startCurrentDay()
        let markDone = app.firstElement(identifierPrefix: "mark-done-")
        XCTAssertTrue(app.reveal(markDone), "a generated slot must offer marking its bout done")
        markDone.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !markDone.isEnabled },
                      "marking the bout done did not register its actuals")
        finishCurrentSession(returningToDay: dayLabel)
        openExerciseHistory(1, named: "Bench Press")

        let combined = app.buttons["Combined"]
        let separate = app.buttons["Separate"]
        XCTAssertTrue(app.reveal(combined), "the separate/combined toggle is missing")
        let footnote = app.staticTexts["Equipment variants may not be directly comparable."]

        // Default is separate: no note.
        XCTAssertFalse(footnote.exists, "separate mode must not show the comparability note")

        // Combined applies to both graphs and shows the note.
        combined.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { footnote.exists },
                      "combined mode must carry the comparability note")
        XCTAssertNotNil(loggedDetail(ofGraph: "weight-graph"),
                        "the Load graph disappeared in combined mode")
        XCTAssertNotNil(loggedDetail(ofGraph: "volume-graph"),
                        "the Reps-performed graph disappeared in combined mode")

        // Back to separate: the note is gone again.
        separate.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !footnote.exists },
                      "leaving combined mode must drop the comparability note")
    }

    // MARK: - 7.17: a dropped session consumes no rotation step

    /// The rotation counts *live* session rows: nothing is written when the
    /// sheet is put down, so the pass is untouched; and deleting a recorded
    /// session (from the day's log in the Rhythm editor) frees its step, so
    /// the next session is pass 1 again.
    func testDeletingOrAbandoningASessionDoesNotConsumeARotationStep() {
        openPrograms()

        let dayLabel = unique("Rotate day")
        ensureDay(named: dayLabel)
        openDay(named: dayLabel)
        addExercise(1)

        // Putting the sheet down records nothing, so it cannot consume a pass.
        startCurrentDay()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Pass 1"].exists },
                      "the first session through a fresh day is not pass 1")
        abandonCurrentSession(dayLabel: dayLabel)
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticText(beginningWith: "This is pass 1").exists
        }, "putting a session down advanced the rotation it never recorded")

        // Deleting a recorded session frees its step. Record one first...
        startCurrentDay()
        finishCurrentSession(returningToDay: dayLabel)
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticText(beginningWith: "This is pass 2").exists
        }, "finishing the session did not advance the rotation")

        // ...then remove it from today's log in the Rhythm editor. The shared
        // database holds many days' sessions for today, so every training row
        // is deleted — ours is among them, and the rest belong to days no test
        // here asserts about.
        app.buttons["Today"].firstMatch.tap()
        let dayCell = app.buttons[todayIdentifier]
        XCTAssertTrue(app.reveal(dayCell), "today's rhythm day is not reachable from the Today tab")
        dayCell.tap()
        let editLogs = app.buttons["Edit selected day's logs"]
        XCTAssertTrue(app.reveal(editLogs), "the selected day's log editor is not reachable")
        editLogs.tap()
        XCTAssertTrue(app.navigationBars["Edit \(todayDateString)"].waitForExistence(timeout: 5),
                      "the day log editor did not open")

        // A training row is one merged link button ("Training, 1 min"); the
        // duration sub-text is the fallback when it is not. Today's log holds
        // the whole shared database for this date and ours is among them, so
        // drain the list until no training row remains.
        var deleted = 0
        for _ in 0..<40 {
            guard let row = firstTrainingRow() else { break }
            row.swipeLeft()
            let delete = app.buttons["Delete"]
            guard delete.waitForExistence(timeout: 2) else { break }
            delete.tap()
            deleted += 1
            let rowLeft = app.waitUntil(timeout: 3) { !delete.exists }
            guard rowLeft else { break }
        }
        XCTAssertGreaterThan(deleted, 0, "no training session was deletable")
        XCTAssertNil(firstTrainingRow(),
                     "today's training sessions did not all delete")

        // Back to the day: the deleted session's pass is free again. The Programs→Day
        // stack is pushed inside the Modules tab, and switching tabs resets that
        // inner stack — returning resumes on the pushed Training screen, never
        // on the day — so the route is re-driven from the tab's home.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let modules = app.buttons["Modules"].firstMatch
        XCTAssertTrue(modules.waitForExistence(timeout: 5), "the Modules destination is missing")
        modules.tap()
        settleModulesHome()
        openPrograms()
        openDay(named: dayLabel)
        startCurrentDay()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts["Pass 1"].exists },
                      "deleting the recorded session did not free its rotation step")
        abandonCurrentSession(dayLabel: dayLabel)
    }

    // MARK: - Helpers

    /// Modules → Training → Start workout → Programs.
    private func openPrograms() {
        let modules = app.buttons["Modules"].firstMatch
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

    /// Puts the Modules stack back at its home screen.
    ///
    /// The Programs→Day stack is pushed *inside* the Modules tab, and switching
    /// tabs resets that inner stack, so returning to Modules can resume on a
    /// pushed screen (usually Training) rather than the home. Popping until the
    /// home's "Training" card is visible makes the normal route re-drivable.
    private func settleModulesHome() {
        for _ in 0..<4 {
            if app.buttons["Training"].firstMatch.exists { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap()
            XCTAssertTrue(app.waitUntil(timeout: 5) { !back.exists },
                          "a back tap out of the Modules stack did not settle")
        }
        XCTAssertTrue(app.buttons["Training"].firstMatch.waitForExistence(timeout: 5),
                      "the Modules home is unreachable after returning to the tab")
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

    /// Adds exercise `id` to the open day's pool through the picker and pool
    /// editor, optionally stepping the Load stepper up to `loadKg` first. The
    /// pool editor is where a prescription load is entered — the session sheet
    /// only offers a load stepper where the prescription already has one.
    private func addExercise(_ id: Int64, withLoad loadKg: Int? = nil) {
        let addExercise = app.element("add-pool-exercise")
        XCTAssertTrue(app.reveal(addExercise), "the day offers no way to add an exercise")
        addExercise.tap()
        XCTAssertTrue(app.navigationBars["Choose Exercise"].waitForExistence(timeout: 5),
                      "the exercise catalog did not open")
        let row = app.buttons["exercise-row-\(id)"]
        XCTAssertTrue(app.reveal(row), "exercise \(id) is missing from the catalog")
        row.tap()
        let save = app.buttons["save-pool-item"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the pool editor did not open")
        if let loadKg { setLoadInEditor(to: loadKg) }
        save.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !save.exists },
                      "saving the pool item did not close the editor")
    }

    /// Steps the pool editor's Load stepper up to `kg`. In the editor for a
    /// load-bearing exercise the Load row is the only stepper whose value
    /// starts blank ("—" — the kg value is hidden until it is above zero), so it
    /// is found by that marker rather than by position. There is no
    /// `increment()` action on `XCUIElement`, so the row's own "+" (its
    /// "Increment" child button, or the right edge as a fallback) is tapped.
    private func setLoadInEditor(to kg: Int) {
        let steppers = app.steppers.allElementsBoundByIndex
        let load = steppers.first { stepper in
            let text = (stepper.value as? String) ?? stepper.label
            return text.contains("—")
        } ?? (steppers.count > 2 ? steppers[2] : nil)
        guard let load else {
            XCTFail("no Load stepper in the pool editor; found \(steppers.count) steppers: "
                    + steppers.map { "\($0.label) [\($0.value as? String ?? "")]" }.joined(separator: ", "))
            return
        }
        let tapPlus: () -> Void
        if load.buttons["Increment"].exists {
            let button = load.buttons["Increment"]
            tapPlus = { button.tap() }
        } else {
            let rightEdge = load.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
            tapPlus = { rightEdge.tap() }
        }
        for _ in 0..<kg { tapPlus() }
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            let valueText = (load.value as? String) ?? ""
            return load.label.contains("\(kg) kg") || valueText.contains("\(kg) kg")
        }, "incrementing the Load stepper did not reach \(kg) kg (now: \(load.label))")
    }

    /// Starts the open day. The readiness question is always asked first; the
    /// No leg runs the day as written. The simulator writes no readiness score,
    /// so there is nothing to scale by either way — which is why the answer is
    /// deterministically "as written".
    private func startCurrentDay() {
        let startDay = app.element("start-program-day")
        XCTAssertTrue(app.waitUntil(timeout: 5) { startDay.isEnabled },
                      "start must enable once the pool has an exercise")
        XCTAssertTrue(app.waitUntilSettled(startDay), "Start's frame kept moving")
        startDay.tap()
        let trainAsWritten = app.buttons["No, train as written"]
        XCTAssertTrue(trainAsWritten.waitForExistence(timeout: 5),
                      "starting a day must ask the readiness question first")
        trainAsWritten.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.firstElement(identifierPrefix: "session-slot-").exists
        }, "no session sheet appeared after starting the day")
    }

    /// Finishes the session and follows it back to the day screen.
    private func finishCurrentSession(returningToDay dayLabel: String) {
        let finish = app.buttons["finish-program-session"]
        XCTAssertTrue(app.reveal(finish), "a non-empty session must offer finishing")
        finish.tap()
        XCTAssertTrue(app.navigationBars[dayLabel].waitForExistence(timeout: 5),
                      "finishing the session did not return to the day")
    }

    /// Puts the session down without recording anything, and follows it back to
    /// the day screen.
    private func abandonCurrentSession(dayLabel: String) {
        let putDown = app.buttons["abandon-program-session"]
        XCTAssertTrue(app.reveal(putDown), "the session sheet must offer putting the session down")
        putDown.tap()
        XCTAssertTrue(app.navigationBars[dayLabel].waitForExistence(timeout: 5),
                      "putting the session down did not return to the day")
    }

    /// Opens the progress screen for exercise `id` through the Add exercise
    /// sheet's history chevron — the one place the graphs live.
    private func openExerciseHistory(_ id: Int64, named name: String) {
        let addExercise = app.element("add-pool-exercise")
        XCTAssertTrue(app.reveal(addExercise), "the day offers no way to add an exercise")
        addExercise.tap()
        XCTAssertTrue(app.navigationBars["Choose Exercise"].waitForExistence(timeout: 5),
                      "the exercise catalog did not open")
        let history = app.buttons["exercise-history-\(id)"]
        XCTAssertTrue(app.reveal(history), "the catalog offers no history chevron for \"\(name)\"")
        history.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5),
                      "the progress screen for \"\(name)\" did not open")
    }

    /// The "N logged" detail under one graph's heading, or nil when the graph or
    /// its counter is not on screen.
    private func loggedDetail(ofGraph identifier: String) -> String? {
        for query in [app.otherElements, app.staticTexts, app.buttons] {
            let group = query[identifier]
            guard group.exists else { continue }
            let detail = group.descendants(matching: .staticText)
                .matching(NSPredicate(format: "label LIKE %@", "* logged"))
                .firstMatch
            if detail.exists { return detail.label }
            // A container may fold its children's text into its own label.
            let text = (group.value as? String) ?? group.label
            if text.hasSuffix(" logged") { return text }
        }
        return nil
    }

    /// The first training row in the day-log editor, or nil when the section is
    /// empty. A NavigationLink row is exposed as one merged button ("Training,
    /// 1 min") in most layouts; the duration sub-text is the fallback.
    private func firstTrainingRow() -> XCUIElement? {
        let merged = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Training"))
            .matching(NSPredicate(format: "label CONTAINS %@", "min"))
            .firstMatch
        if merged.exists { return merged }
        let duration = app.staticTexts["1 min"].firstMatch
        return duration.exists ? duration : nil
    }

    /// The Rhythm calendar's day cell for today, e.g. "activity-ring-day-2026-10-02".
    private var todayIdentifier: String { "activity-ring-day-\(todayDateString)" }

    /// Today's logical day, in the app's calendar format. The app's day boundary
    /// is 04:00 local, so the early hours still belong to the previous day.
    private var todayDateString: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        let startOfDay = calendar.startOfDay(for: now)
        let day = seconds < 4 * 3600
            ? calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            : startOfDay
        let ymd = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", ymd.year ?? 0, ymd.month ?? 0, ymd.day ?? 0)
    }
}