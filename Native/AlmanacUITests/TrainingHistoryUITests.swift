import XCTest

/// The two training screens that had no entry point: history and templates.
///
/// `OwnerRequestedFeaturesUITests` already covers the exercise library and its
/// identifiers, so the identifiers those tests pin (`exercise-library-link` and
/// friends) are deliberately untouched by this file. What is new here is that
/// the two links exist, that the screens state their period, and that the
/// template editor only offers the ten containers the model defines.
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
