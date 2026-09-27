import XCTest

/// The two Slice 7 screens that had stores and no way to reach them.
///
/// The stores are unit-tested in `SupplementStoreTests` and
/// `ContextEventStoreTests`; this is the part those cannot see — that the
/// screens render, that the empty state says something honest, and that tapping
/// a tag or a plan's adherence actually persists.
///
/// **No test here asserts that the database is empty.** These run in one
/// process against one installed app, so a row created by one test is still
/// there for the next, and a test written against "nothing logged yet" fails on
/// the second run. Each one drives the app to the state it needs first and then
/// asserts about what it just did.
final class BodyCompositionWellnessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - Supplements

    /// The screen opens, always offers a way to add a plan, and its empty state
    /// and its adherence headline cannot both be true or both be false.
    ///
    /// The coherence check is on the *headline* rather than on a count of plan
    /// rows, because a `List` is lazily built: a query for the plan rows returns
    /// nothing once the list has been scrolled past them, so a count taken after
    /// reaching the "Add plan" button says nothing about whether plans exist. The
    /// prominent card is at the top and always rendered.
    func testSupplementsScreenOpensAndItsEmptyStateMatchesItsHeadline() {
        openModules()
        let supplements = app.buttons["Supplements"]
        XCTAssertTrue(app.reveal(supplements), "Supplements is missing from Modules")
        supplements.tap()

        XCTAssertTrue(app.navigationBars["Supplements"].waitForExistence(timeout: 5))
        // Scrolled to, not merely queried: the control sits below the plan list
        // and the list is lazily built, so on a database that already has plans
        // it has not been rendered and `.exists` is false.
        XCTAssertTrue(app.reveal(app.buttons["Add plan"]), "there is no way to create the first plan")

        let empty = app.staticTexts["No supplement plans yet. Add one to start tracking adherence."]
        let nothingDue = app.staticTexts["Nothing due yet today"]
        if empty.exists {
            XCTAssertTrue(nothingDue.exists,
                          "the screen says it has no plans and also reports today's adherence")
        } else {
            XCTAssertFalse(nothingDue.exists,
                           "the screen reports nothing due while also omitting the no-plans state")
        }
    }

    /// Creating a plan, logging it, and seeing the plan's own control change
    /// state. The control is found by its identifier prefix rather than by the
    /// plan's name, because the name also appears inside the control itself and
    /// a static-text query on it is ambiguous — which is the failure that first
    /// version of this test hit.
    func testCreatingAPlanAndLoggingItShowsAsTaken() throws {
        let name = "Vitamin D \(Int(Date().timeIntervalSince1970))"
        try addPlan(named: name, dose: "2000")

        let toggle = toggle(named: name)
        // Revealed upwards: the adherence controls are in the prominent card at
        // the top, and `addPlan` leaves the list scrolled down at the new row.
        XCTAssertTrue(app.reveal(toggle, direction: .down), "no adherence control for the new plan appeared")
        XCTAssertTrue(toggle.label.contains("Not logged"), "a new plan starts unlogged: \(toggle.label)")

        toggle.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { self.toggleLabel(name).contains("Taken") },
                      "logging the dose did not show as taken")
    }

    /// A discontinued plan stays on the screen. It is deactivated rather than
    /// deleted so its adherence history keeps pointing at a real plan, so
    /// hiding it would make it look deleted — the opposite of what happened.
    func testDiscontinuingAPlanKeepsItVisible() throws {
        let name = "Old Stack \(Int(Date().timeIntervalSince1970))"
        try addPlan(named: name)

        let row = app.staticTexts[name].firstMatch
        row.swipeLeft()
        let discontinue = app.buttons["Discontinue"]
        XCTAssertTrue(discontinue.waitForExistence(timeout: 5), "the plan offers no way to discontinue it")
        discontinue.tap()

        let survived = app.staticTexts[name].firstMatch
        XCTAssertTrue(app.reveal(survived), "a discontinued plan disappeared from the list")
        XCTAssertTrue(app.staticTexts["Discontinued"].exists, "the plan is not marked as discontinued")
    }

    // MARK: - Context tags

    /// The screen opens on a day and the two states cannot both be true.
    func testContextScreenOpensAndItsEmptyStateMatchesItsHistory() {
        openModules()
        let context = app.buttons["Context"]
        XCTAssertTrue(app.reveal(context), "Context is missing from Modules")
        context.tap()

        XCTAssertTrue(app.navigationBars["Context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["context-day-previous"].exists, "there is no way to reach an earlier day")
        XCTAssertTrue(app.buttons["context-day-next"].exists, "there is no way to reach a later day")

        let empty = app.staticTexts["Nothing recorded for this day."]
        let save = app.buttons["context-tags-save"]
        // The save control sits below the tag grid, so it has to be scrolled to
        // before it exists at all — a lazily-built List will not have rendered it.
        XCTAssertTrue(app.reveal(save), "there is no way to save a day's tags")
        // It reads "Saved" until something is chosen, then offers the day it
        // would write to — a tap can never silently land elsewhere.
        if empty.exists {
            XCTAssertFalse(save.isEnabled, "an unchanged day must not offer to save")
        }
    }

    /// Setting a tag and clearing it again, both persisting.
    ///
    /// Written as set-then-clear rather than just set because the tests share
    /// one installed app and one database: a day that already carries the tag
    /// under test cannot demonstrate that *saving* writes anything, since
    /// re-selecting what is already stored correctly leaves the screen reporting
    /// nothing unsaved. Walking the day to a known state and back is idempotent
    /// however many times this runs — and clearing is the half of the screen
    /// that an "add something and save" test never reaches.
    func testSettingAndClearingADayBothPersist() {
        openContext()
        // Any day will do, since the day is walked to a known state first. Two
        // days back is far enough that today and yesterday stay untouched.
        app.buttons["context-day-previous"].tap()
        app.buttons["context-day-previous"].tap()

        let illness = app.buttons["context-tag-illness"]
        XCTAssertTrue(app.reveal(illness), "the illness tag is not reachable")
        // Downwards: the save control sits below the tag grid and the notes
        // field, and the screen opens scrolled to the top.
        let save = app.buttons["context-tags-save"]
        XCTAssertTrue(app.reveal(save), "there is no way to save a day's tags")

        // Normalise: the tag ends up on, whatever the day started as.
        if !illness.isSelected {
            illness.tap()
            XCTAssertTrue(app.waitUntil(timeout: 5) { app.buttons["context-tags-save"].isEnabled },
                          "choosing a tag did not enable saving")
        }
        save.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !self.app.buttons["context-tags-save"].isEnabled },
                      "saving the tag did not settle back to a clean state")
        XCTAssertTrue(app.reveal(app.staticTexts["1 tag"].firstMatch),
                      "the saved day does not appear in the history with its tag")

        // Now clear it. A day whose only tag is removed still has a row with no
        // tags on it, so the screen reports it as nothing recorded rather than
        // as a day with an empty tag list.
        illness.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.buttons["context-tags-save"].isEnabled },
                      "clearing the tag did not enable saving")
        save.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !self.app.buttons["context-tags-save"].isEnabled },
                      "clearing the tag did not settle back to a clean state")
        XCTAssertTrue(app.staticTexts["Nothing recorded for this day."].exists,
                      "a cleared day is not reported as unrecorded")
    }

    /// The tag grid is the screen's whole interactive surface, so a tag that
    /// cannot be reached is a dead screen.
    func testEveryContextTagIsReachable() {
        openContext()
        for tag in ["illness", "medication_change", "travel_jet_lag", "unusual_stress", "heat_exposure",
                    "sauna", "poor_watch_wear", "late_night_event", "sleep_interruption", "competition_day"] {
            let button = app.buttons["context-tag-\(tag)"]
            XCTAssertTrue(app.reveal(button), "the \(tag) tag is not reachable")
        }
    }

    /// Creates a plan called `name` and waits for it to reach the list.
    ///
    /// Both fields are filled: the editor refuses a plan with no dose, and
    /// **the screen underneath a presented sheet is still in the accessibility
    /// tree** — so a test that only waits for the `Supplements` navigation bar
    /// after tapping Save passes even when Save was refused and the sheet never
    /// closed. Waiting for the row itself is the assertion that means something.
    private func addPlan(named name: String, dose: String = "1") throws {
        openSupplements()
        let addPlan = app.buttons["Add plan"]
        XCTAssertTrue(app.reveal(addPlan), "there is no way to add a plan")
        addPlan.tap()

        XCTAssertTrue(app.navigationBars["New plan"].waitForExistence(timeout: 5))
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        let doseField = app.textFields["Dose"]
        doseField.tap()
        doseField.typeText(dose)

        app.navigationBars["New plan"].buttons["Save"].tap()

        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.staticTexts[name].firstMatch.exists },
                      "saving the plan did not add it to the list")
        XCTAssertTrue(app.reveal(row), "the new plan is not on screen")
    }

    // MARK: - Helpers

    /// The label of the adherence control belonging to `name`.
    ///
    /// By identifier prefix and then filtered by the name, because the toggle's
    /// own accessibility label is built from the plan's fields — so the name is
    /// already inside it and no name-derived query is ambiguous.
    private func toggleLabel(_ name: String) -> String {
        toggle(named: name).label
    }

    /// The adherence control for the plan called `name`.
    ///
    /// `firstMatch` over the whole family is not good enough: a previous test in
    /// this run may have created another plan, and the assertion would then be
    /// about that one.
    private func toggle(named name: String) -> XCUIElement {
        let toggles = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "supplement-toggle-"))
        for index in 0..<toggles.count {
            let candidate = toggles.element(boundBy: index)
            if candidate.label.contains(name) { return candidate }
        }
        // Nothing matched, so a failing assertion names the family rather than
        // crashing on an out-of-bounds index.
        return toggles.firstMatch
    }

    private func openModules() {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10))
        modules.tap()
        XCTAssertTrue(app.navigationBars["Modules"].waitForExistence(timeout: 5))
    }

    private func openSupplements() {
        openModules()
        let link = app.buttons["Supplements"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Supplements"].waitForExistence(timeout: 5))
    }

    private func openContext() {
        openModules()
        let link = app.buttons["Context"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Context"].waitForExistence(timeout: 5))
    }
}
