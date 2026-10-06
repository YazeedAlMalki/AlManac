import XCTest

/// Kitchen's Recipes screen, driven from the Nutrition screen it hangs off.
///
/// `KitchenTests` and `KitchenSeedPlanTests` prove the matching and the allergen
/// filter at the core. What only a UI test can catch is that the screen is
/// unreachable, that the pantry cannot actually be edited, that choosing a
/// recipe does not reach the logging form, or that a withheld recipe is shown
/// as an ordinary one.
///
/// No screen creates a recipe, so every test launches with
/// `-AlmanacSeedKitchen` (`KitchenSeedPlan`): four `Kitchen test …` foods, two
/// of them recipes, and none of them in the pantry. The seed is authoritative,
/// so the shared, never-reset simulator database starts each test the same way.
///
/// Written 2026-10-06 in a Linux container with no Xcode: **not yet run**.
/// The first run on a Mac is the check that the queries below match the
/// screen; a failure there is as likely to be the test as the app.
final class KitchenUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let rice = "Kitchen test rice"
    private static let bowl = "Kitchen test rice bowl"
    private static let satay = "Kitchen test satay"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCTAssertTrue(app.seedKitchen("recipes,noallergens"),
                      "the app refused to open with the Kitchen seed")
    }

    override func tearDownWithError() throws {
        // Leave no peanut allergy behind for the next suite, whichever test ran.
        app.seedKitchen("recipes,noallergens")
    }

    // MARK: - Reachable

    /// Nutrition → Recipes opens the picker.
    func testRecipesOpensFromTheNutritionScreen() throws {
        try openRecipes()
        XCTAssertTrue(app.buttons["Pantry"].exists, "the Recipes screen offers no pantry")
    }

    // MARK: - Pantry

    /// A food added to the pantry is listed, and a swiped-away one is gone.
    func testAPantryItemCanBeAddedAndRemoved() throws {
        try openRecipes()
        // The toolbar's, not the "Pantry" segment of the mode picker: both are
        // buttons named Pantry (CI, 2026-10-06: "Multiple matching elements").
        app.navigationBars["Recipes"].buttons["Pantry"].tap()
        XCTAssertTrue(app.navigationBars["Pantry"].waitForExistence(timeout: 10), "the pantry never opened")
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("Your pantry is empty") }
        }, "the seed should leave the pantry empty of its own foods: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        app.navigationBars["Pantry"].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Food search"].waitForExistence(timeout: 10),
                      "Add did not open the food search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.tap()
        field.typeText(Self.rice)

        // The exact name, so the rice bowl (whose name contains the rice's) is
        // not the row tapped.
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.rice))
            .matching(NSPredicate(format: "NOT (label CONTAINS %@)", "bowl")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15),
                      "the rice was not found: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        result.tap()

        let row = app.staticTexts[Self.rice]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the added food is not listed in the pantry: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the pantry row offers no delete")
        delete.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !app.staticTexts[Self.rice].exists },
                      "the removed food is still listed")
    }

    // MARK: - Choosing

    /// A chosen recipe lands in the logging form, which is the only way Kitchen
    /// logs anything.
    func testChoosingARecipeHandsItToTheLoggingForm() throws {
        try openRecipes()
        app.buttons["All"].tap()

        let recipe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.bowl)).firstMatch
        XCTAssertTrue(recipe.waitForExistence(timeout: 10),
                      "the seeded recipe is not listed: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        recipe.tap()

        XCTAssertTrue(app.waitUntil(timeout: 10) { !app.navigationBars["Recipes"].exists },
                      "choosing a recipe did not close the picker")
        // `LabeledContent("Food", value: name)` inside the form's button.
        XCTAssertTrue(app.waitUntil(timeout: 10) {
            app.buttons.allElementsBoundByIndex.contains { $0.label.contains(Self.bowl) }
                || app.staticTexts[Self.bowl].exists
        }, "the logging form does not show the chosen recipe")
        XCTAssertTrue(app.buttons["Log"].exists, "the logging form offers no Log once a recipe is chosen")

        // One serving is pre-filled (owner, 2026-10-06). The seeded bowl is 200 g
        // with no serving count, so the whole bowl is one serving. Still editable.
        let grams = app.textFields["Amount, in grams"]
        XCTAssertTrue(app.reveal(grams), "the logging form has no gram amount")
        XCTAssertEqual(grams.value as? String, "200", "one serving was not pre-filled")
    }

    // MARK: - Allergens

    /// With peanuts recorded, the satay is hidden by default — not among the
    /// recipes, but behind a collapsed "Hidden because of your allergens" entry —
    /// and the disclaimer shows. Opened, it carries a warning naming the
    /// allergen on its own page, and logging it asks first (owner, 2026-10-06).
    func testARecipeDeclaringARecordedAllergenIsWithheld() throws {
        XCTAssertTrue(app.seedKitchen("recipes,peanuts"), "the app refused to open with peanuts recorded")
        try openRecipes()
        app.buttons["All"].tap()

        // Any element type: on a `DisclosureGroup` in a `List` the identifier
        // can land on the cell, which `app.element(_:)` does not search.
        let hidden = anyElement("allergen-hidden-toggle")
        XCTAssertTrue(hidden.waitForExistence(timeout: 10),
                      "nothing was hidden: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(hidden.label.contains("Hidden because of your allergens"),
                      "the hidden entry is not labelled as such: \(hidden.label)")
        // Any element type, and *contains*: the note is an `AlmanacProblemNote`,
        // one element (not a static text) whose label starts with what was
        // hidden and goes on to the disclaimer (CI, 2026-10-06).
        let disclaimer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Checked recipe and ingredient names only")).firstMatch
        XCTAssertTrue(disclaimer.exists, "the allergen disclaimer is missing")
        XCTAssertFalse(app.buttons.allElementsBoundByIndex.contains { $0.label.hasPrefix(Self.satay) },
                       "the hidden recipe is offered as an ordinary one before the entry is opened")
        XCTAssertTrue(app.buttons.allElementsBoundByIndex.contains { $0.label.hasPrefix(Self.bowl) },
                      "the recipe with no declared allergen was hidden too")

        // Reachable: open the entry, then the recipe's own page.
        // Tap the disclosure's own button, not whatever carries the identifier:
        // a tap on the cell's centre left it collapsed (CI, 2026-10-06). Then
        // find the recipe by identifier or, failing that, by its name.
        let disclosure = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Hidden because of your allergens")).firstMatch
        (disclosure.exists ? disclosure : hidden).tap()
        let byID = anyElement("allergen-hidden-row-ui-kitchen-satay")
        let byName = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.satay)).firstMatch
        XCTAssertTrue(app.waitUntil(timeout: 5) { byID.exists || byName.exists },
                      "the hidden recipe is not listed once the entry is opened: "
                      + "\(app.buttons.allElementsBoundByIndex.map(\.label))")
        (byID.exists ? byID : byName).tap()
        let warning = anyElement("allergen-warning")
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "the hidden recipe's page shows no warning")
        XCTAssertTrue(warning.label.contains("Peanuts"), "the warning does not name the allergen: \(warning.label)")

        // Logging asks first; cancelling leaves the page where it was.
        anyElement("allergen-log-anyway").tap()
        let confirm = app.buttons["Log anyway"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "logging a hidden recipe did not ask for confirmation")
        // iOS 26 shows the dialog as a popover with no Cancel button; tapping
        // outside it is the cancel (CI, 2026-10-06: "Failed to tap Cancel").
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // The navigation bar's title: outside the popover, and harmless if
            // the tap passes through.
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.waitUntil(timeout: 5) { !confirm.exists }, "the confirmation did not close")
        XCTAssertTrue(warning.exists, "cancelling the confirmation left the recipe's page")
    }

    // MARK: - Helpers

    /// The first element of any type carrying `identifier`.
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Modules → Nutrition → Recipes, waiting for the catalogue: the button is
    /// disabled until the reference bundle has installed.
    private func openRecipes() throws {
        let modules = app.buttons["tab-modules"].exists ? app.buttons["tab-modules"] : app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 15), "no Modules tab")
        modules.tap()
        let nutrition = app.buttons["Nutrition"]
        XCTAssertTrue(app.reveal(nutrition), "Nutrition is not reachable from Modules")
        nutrition.tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 10), "Nutrition never opened")

        let recipes = app.navigationBars["Nutrition"].buttons["Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 10),
                      "no Recipes button: \(app.navigationBars["Nutrition"].buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(app.waitUntil(timeout: 120) { recipes.isEnabled },
                      "Recipes stayed disabled; the food catalogue never became available")
        recipes.tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 10), "Recipes never opened")
    }
}
