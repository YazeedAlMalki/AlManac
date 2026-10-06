import XCTest

/// The two training screens that had no entry point: history and templates.
///
/// `OwnerRequestedFeaturesUITests` already covers the exercise library and its
/// identifiers, so the identifiers those tests pin (`exercise-library-link` and
/// friends) are deliberately untouched by this file. What is new here is that
/// the two links exist, that the screens state their period, that the
/// template editor only offers the ten containers the model defines, and
/// (2026-10-06) that a template applied to today fills it and stays editable.
final class TrainingHistoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - History

    func testTrainingHistoryOpensFromTheTrainingScreen() {
        openTraining()
        let link = app.buttons["training-history-link"]
        XCTAssertTrue(app.reveal(link), "Training history is missing from the Training screen")
        link.tap()
        XCTAssertTrue(app.navigationBars["Training history"].waitForExistence(timeout: 5))
    }

    /// The period has to be on screen and has to be stated, because a history
    /// with no stated range is indistinguishable from one covering everything.
    func testHistoryStatesItsPeriodAndNeverBlanksSilently() {
        openTraining()
        let link = app.buttons["training-history-link"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Training history"].waitForExistence(timeout: 5))

        let period = app.element("training-review-period")
        XCTAssertTrue(app.reveal(period), "the history offers no period")
        XCTAssertTrue(app.staticTexts["No sessions in this period."].exists
                      || app.cells.count > 1,
                      "neither an empty state nor any rows; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testWideningTheHistoryPeriodTakes() {
        openTraining()
        let link = app.buttons["training-history-link"]
        XCTAssertTrue(app.reveal(link))
        link.tap()

        let period = app.element("training-review-period")
        XCTAssertTrue(app.reveal(period))
        period.tap()
        app.buttons["Last 90 days"].tap()
        XCTAssertTrue(app.staticTexts["Last 90 days"].waitForExistence(timeout: 5),
                      "the period did not take")
    }

    // MARK: - Templates

    func testTemplatesOpenAndSayWhatATemplateIsWhenThereAreNone() {
        openTraining()
        let link = app.buttons["training-templates-link"]
        XCTAssertTrue(app.reveal(link), "Templates is missing from the Training screen")
        link.tap()

        XCTAssertTrue(app.navigationBars["Templates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add template"].exists, "there is no way to create the first template")
        // A virgin database has none; the copy has to explain rather than show
        // a blank section.
        let empty = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "No templates yet")).firstMatch
        XCTAssertTrue(empty.exists || app.cells.count > 1,
                      "neither an empty state nor any templates; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testCreatingATemplateOffersTheTenModelContainers() {
        openTraining()
        let link = app.buttons["training-templates-link"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        app.buttons["Add template"].tap()

        XCTAssertTrue(app.navigationBars["New template"].waitForExistence(timeout: 5))
        let container = app.element("template-container")
        XCTAssertTrue(container.waitForExistence(timeout: 5), "the container is not offered")
        container.tap()

        // Every one of the model's ten, by the same words the enum uses. A
        // free-text field here would let a value reach the column that the
        // CHECK constraint then rejects.
        for name in ["Straight sets", "Superset", "Circuit",
                     "Every minute on the minute", "As many rounds as possible",
                     "For time", "Interval block", "Ladder", "Skill block", "Flow"] {
            XCTAssertTrue(app.buttons[name].exists, "the container \"\(name)\" is not offered")
        }
    }

    // MARK: - Applying a template (owner, 2026-10-06)

    /// A template's exercises become today's starting point, and the session
    /// stays editable: one exercise is completed with what was actually done,
    /// another is deleted, and both changes hold.
    ///
    /// Written 2026-10-06 without Xcode; the first run is CI's `test-ios`.
    func testApplyingATemplateFillsTodayAndStaysEditable() {
        let name = "UI template \(Int(Date().timeIntervalSince1970))"

        // Build the template through the screens: Bench Press 3 × 8, and Ab
        // Wheel Rollout with no numbers.
        openTraining()
        let link = app.buttons["training-templates-link"]
        XCTAssertTrue(app.reveal(link), "Templates is missing from the Training screen")
        link.tap()
        app.buttons["Add template"].tap()
        XCTAssertTrue(app.navigationBars["New template"].waitForExistence(timeout: 5))
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the template has no name field")
        nameField.tap()
        nameField.typeText(name)

        addTemplateExercise(1, sets: "3", reps: "8")
        addTemplateExercise(69, sets: nil, reps: nil)
        XCTAssertTrue(app.element("template-item-1").exists, "Bench Press is not in the template's list")

        app.navigationBars["New template"].buttons["Save"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !app.navigationBars["New template"].exists },
                      "saving the template did not close the editor")
        let back = app.navigationBars["Templates"].buttons.firstMatch
        if back.exists { back.tap() }
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 5))

        // Apply it to today.
        let start = app.element("training-apply-template")
        XCTAssertTrue(app.reveal(start), "the Training screen offers no way to start from a template")
        start.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5),
                      "the new template is not offered: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        choice.tap()
        // A shared simulator may already hold bouts logged today; the screen
        // then asks before adding after them. A fresh one does not ask.
        let addAfter = app.buttons["Add after them"]
        if addAfter.waitForExistence(timeout: 3) { addAfter.tap() }

        let planned = NSPredicate(format: "identifier BEGINSWITH 'today-bout-' AND label CONTAINS %@ AND label CONTAINS 'Planned'",
                                  "Bench Press")
        let bench = app.buttons.matching(planned).firstMatch
        XCTAssertTrue(app.waitUntil(timeout: 10) { bench.exists },
                      "today does not show the template's Bench Press as planned: "
                      + "\(app.buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(bench.label.contains("3 x 8"), "the planned sets and reps were not copied: \(bench.label)")
        let benchID = bench.identifier

        // Record what was actually done.
        XCTAssertTrue(app.reveal(bench))
        bench.tap()
        XCTAssertTrue(app.navigationBars["Bout"].waitForExistence(timeout: 5), "the bout did not open for editing")
        type("3", into: app.textFields["Sets"])
        type("6", into: app.textFields["Reps"])
        app.navigationBars["Bout"].buttons["Save"].tap()
        let edited = app.element(benchID)
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            edited.exists && edited.label.contains("3 x 6") && !edited.label.contains("Planned")
        }, "what was done did not replace the plan on today's row: \(edited.label)")

        // Drop the exercise that was not done.
        let wheel = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'today-bout-' AND label CONTAINS 'Ab Wheel Rollout' AND label CONTAINS 'Planned'"))
            .firstMatch
        XCTAssertTrue(app.reveal(wheel), "the template's second exercise is not on today")
        let wheelID = wheel.identifier
        wheel.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "today's bout offers no delete")
        delete.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !app.element(wheelID).exists },
                      "the deleted exercise is still on today")
        XCTAssertTrue(app.element(benchID).label.contains("3 x 6"), "deleting one exercise changed another")
    }

    /// Template editor → Add exercise → pick `id` → optional numbers → Add.
    private func addTemplateExercise(_ id: Int64, sets: String?, reps: String?) {
        let add = app.element("template-add-exercise")
        XCTAssertTrue(app.reveal(add), "the template editor offers no way to add an exercise")
        add.tap()
        XCTAssertTrue(app.navigationBars["Choose Exercise"].waitForExistence(timeout: 5),
                      "the exercise catalog did not open")
        let row = app.buttons["exercise-row-\(id)"]
        XCTAssertTrue(app.reveal(row), "exercise \(id) is missing from the catalog")
        row.tap()
        let save = app.element("template-item-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the exercise's numbers did not open")
        if let sets { type(sets, into: app.element("template-item-sets")) }
        if let reps { type(reps, into: app.element("template-item-reps")) }
        save.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !save.exists }, "adding the exercise did not close its editor")
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field")
        field.tap()
        field.typeText(text)
    }

    // MARK: - Helpers

    private func openTraining() {
        let modules = app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10))
        modules.tap()
        XCTAssertTrue(app.navigationBars["Modules"].waitForExistence(timeout: 5))

        let training = app.buttons["Training"]
        XCTAssertTrue(app.reveal(training), "Training is missing from Modules")
        training.tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 5))
    }
}
