import XCTest

/// Shifts & rhythm, reached from the Modules menu (BRD §6.11, §13).
///
/// What these cover is the part the core tests cannot see: that the screen is
/// reachable, that a person with no shifts is told so plainly instead of shown
/// a blank week, and that a shift entered in the editor turns up on the screen
/// that reads it.
///
/// **Every launch names its shift state.** The editor persists, the simulator's
/// database is shared across runs and never reset, and a day's rhythm depends
/// on the days before it — so a test that began from "whatever the last run
/// left" would pass or fail on history. `-AlmanacSeedShifts` replaces the
/// schedule outright (`ShiftSeedPlan`).
///
/// The wording is repeated here rather than imported: this target does not link
/// `AlmanacCore`, and asserting on a string derived from the thing under test
/// would be tautological.
final class ShiftsAndRhythmUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(seeding spec: String, language: String = "en", locale: String = "en_US") {
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                "-AlmanacSeedShifts", spec]
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - Reaching it

    func testShiftsAndRhythmIsInTheModulesMenu() {
        launch(seeding: "none")
        openShiftsAndRhythm()
    }

    // MARK: - No shifts

    /// §6.11: a person with no shift schedule is the ordinary case and stays
    /// fully supported. The screen says what it needs from them, and does not
    /// invent a rhythm.
    func testWithNoShiftsTheScreenSaysSoAndOffersToAddSome() {
        launch(seeding: "none")
        openShiftsAndRhythm()

        XCTAssertTrue(app.staticTexts["No shifts entered yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["circadian-add-shifts"].exists)
        XCTAssertFalse(app.staticTexts["A settled night rhythm."].exists,
                       "a rhythm was claimed with no shifts to base it on")
    }

    // MARK: - Reading shifts

    /// Five nights ending today are the engine's definition of settled (§13.1).
    func testFiveNightsInARowReadAsASettledNightRhythm() {
        launch(seeding: "night:-4,night:-3,night:-2,night:-1,night:0")
        openShiftsAndRhythm()

        XCTAssertTrue(app.staticTexts["A settled night rhythm."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No shifts entered yet"].exists)
    }

    // MARK: - Entering shifts

    /// One day entered through the editor shows on that day's row. The editor
    /// opens on Day shift, so choosing Night shift and seeing Night shift on the
    /// row can only happen if saving writes the *chosen* value.
    func testOneShiftEnteredInTheEditorShowsOnTodaysRow() {
        launch(seeding: "none")
        openShiftsAndRhythm()

        app.buttons["circadian-add-shifts"].tap()
        let picker = app.buttons["shift-editor-shift"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the shift editor did not open")
        picker.tap()
        app.buttons["Night shift"].tap()
        app.buttons["shift-editor-save"].tap()

        let today = app.staticTexts["circadian-shift-0"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today's row never appeared")
        XCTAssertEqual(today.label, "Night shift", "today's row does not show the saved shift")
        XCTAssertFalse(app.staticTexts["No shifts entered yet"].exists)
    }

    /// A rotation fills the days ahead. The editor's default rotation is one
    /// day-shift repeated, so after saving the days from today on are all day
    /// shifts and, five days in, a settled daytime rhythm.
    func testSavingTheDefaultRotationFillsTheDaysAhead() {
        launch(seeding: "none")
        openShiftsAndRhythm()

        app.buttons["circadian-add-shifts"].tap()
        let mode = app.segmentedControls["shift-editor-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), "the shift editor did not open")
        mode.buttons["Rotation"].tap()
        app.buttons["shift-editor-save"].tap()

        // The list is lazy: the fifth day of the rotation is ten rows down and
        // does not exist on screen until it is scrolled to.
        XCTAssertTrue(app.staticTexts["circadian-shift-0"].waitForExistence(timeout: 10),
                      "the saved rotation never appeared")
        let settled = app.staticTexts["A settled daytime rhythm."].firstMatch
        XCTAssertTrue(app.reveal(settled), "five day shifts in a row never read as a settled rhythm")
        let lastDay = app.staticTexts["circadian-shift-7"]
        XCTAssertTrue(app.reveal(lastDay), "the rotation did not reach the end of the window")
        XCTAssertEqual(lastDay.label, "Day shift")
    }

    // MARK: - Arabic

    /// The catalog gate proves each string has an Arabic entry; this proves the
    /// entries are the ones the screen looks up. Everything asserted is Arabic
    /// text that exists only in the catalog, and the identifiers are the same
    /// ones the English tests use, so a layout that broke in right-to-left
    /// would fail on them too.
    func testTheScreenReadsInArabic() {
        launch(seeding: "night:-4,night:-3,night:-2,night:-1,night:0", language: "ar", locale: "ar_SA")
        openShiftsAndRhythm(menuRow: "المناوبات والإيقاع", title: "المناوبات والإيقاع")

        XCTAssertTrue(app.staticTexts["إيقاع ليلي مستقر."].waitForExistence(timeout: 10),
                      "the settled-night sentence is not in Arabic")
        XCTAssertEqual(app.staticTexts["circadian-shift-0"].label, "مناوبة ليلية")
        XCTAssertFalse(app.staticTexts["A settled night rhythm."].exists)
    }

    // MARK: - Helpers

    private func openShiftsAndRhythm(menuRow: String = "Shifts & rhythm", title: String = "Shifts & rhythm") {
        let modules = app.buttons["tab-modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10), "the Modules destination is missing")
        modules.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10),
                      "the Modules menu did not open")
        let row = app.buttons[menuRow]
        XCTAssertTrue(app.reveal(row), "\(menuRow) has no row in the Modules menu")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].firstMatch.waitForExistence(timeout: 10),
                      "tapping \(menuRow) did not open it")
    }
}
