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
/// `-AlmanacSeedKitchen` (`KitchenSeedPlan`): five `Kitchen test …` foods, two
/// of them recipes, none of them in the pantry, and the oats logged on each of
/// the last three days so the pantry offers them. The seed is authoritative,
/// so the shared, never-reset simulator database starts each test the same way.
///
/// 2026-10-07: three more, for what only a UI test can catch here — that adding
/// to the pantry changes the recipe list, that a pantry suggestion can be added
/// and dismissed and the dismissal is kept, and that Saved meals withholds the
/// same recipe Kitchen does (the owner's "same rule everywhere").
///
/// Written 2026-10-06 in a Linux container with no Xcode. CI's UI run on a
/// macOS simulator found and fixed the lookups below over five runs, and all
/// four tests passed there on `cccf311` (run 37548425210).
final class KitchenUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let rice = "Kitchen test rice"
    private static let bowl = "Kitchen test rice bowl"
    private static let satay = "Kitchen test satay"
    private static let sauce = "Kitchen test peanut sauce"
    private static let oats = "Kitchen test oats"

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
        openPantry()
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("Your pantry is empty") }
        }, "the seed should leave the pantry empty of its own foods: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        addToPantryBySearch(Self.rice)

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

    /// What the pantry is for: with the rice in it, the Pantry list offers the
    /// rice bowl as made from what is on hand, and the satay as one ingredient
    /// short, naming it.
    func testAPantryItemBringsUpTheRecipesThatUseIt() throws {
        try openRecipes()
        openPantry()
        addToPantryBySearch(Self.rice)
        XCTAssertTrue(app.staticTexts[Self.rice].waitForExistence(timeout: 10), "the rice did not reach the pantry")
        app.navigationBars["Pantry"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 10), "Done did not return to Recipes")

        // Pantry is the picker's default mode.
        let bowl = recipeButton(Self.bowl)
        XCTAssertTrue(bowl.waitForExistence(timeout: 10),
                      "the recipe made only of the rice is not listed: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(bowl.label.contains("Everything on hand"), "the bowl should need nothing: \(bowl.label)")
        let satay = recipeButton(Self.satay)
        XCTAssertTrue(satay.exists, "the recipe that uses the rice is not listed")
        XCTAssertTrue(satay.label.contains("Missing \(Self.sauce)"), "the satay should name what it lacks: \(satay.label)")
    }

    /// A food logged on three of the last fourteen days is offered, never added
    /// on its own. Added, it is in the pantry and no longer offered; removed
    /// again, it is offered again; dismissed, it is gone and stays gone.
    func testAFoodLoggedOftenIsOfferedAndTheChoiceIsKept() throws {
        try openRecipes()
        openPantry()

        let add = anyElement("pantry-suggestion-add-ui-kitchen-oats")
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "the oats, logged on each of the last three days, were not offered: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        add.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !add.exists }, "an added food is still offered")
        let row = app.staticTexts[Self.oats]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the accepted food is not in the pantry")

        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the pantry row offers no delete")
        delete.tap()

        let dismiss = anyElement("pantry-suggestion-dismiss-ui-kitchen-oats")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5),
                      "a food taken out of the pantry, never dismissed, was not offered again")
        dismiss.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !dismiss.exists && !app.staticTexts[Self.oats].exists },
                      "a dismissed food is still on screen: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        // Kept: closed and reopened, it is not offered.
        app.navigationBars["Pantry"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 10), "Done did not return to Recipes")
        openPantry()
        XCTAssertFalse(anyElement("pantry-suggestion-add-ui-kitchen-oats").waitForExistence(timeout: 3),
                       "a dismissed food was offered again")
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
        // An alert, so Cancel is always there (the iOS 26 confirmation dialog
        // had none, and tapping outside it did not close it in CI).
        let cancel = app.alerts.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "the confirmation offers no Cancel")
        cancel.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !confirm.exists }, "the confirmation did not close")
        XCTAssertTrue(warning.exists, "cancelling the confirmation left the recipe's page")
    }

    /// Saved meals and Kitchen are the same rows under one check, so with
    /// peanuts recorded Saved meals hides the satay behind the same entry.
    func testSavedMealsWithholdTheSameRecipe() throws {
        XCTAssertTrue(app.seedKitchen("recipes,peanuts"), "the app refused to open with peanuts recorded")
        let saved = try nutritionToolbarButton("Saved meals")
        saved.tap()
        XCTAssertTrue(app.navigationBars["Saved meals"].waitForExistence(timeout: 10), "Saved meals never opened")

        let hidden = anyElement("allergen-hidden-toggle")
        XCTAssertTrue(hidden.waitForExistence(timeout: 10),
                      "Saved meals hid nothing: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(hidden.label.contains("Hidden because of your allergens"),
                      "the hidden entry is not labelled as such: \(hidden.label)")
        XCTAssertFalse(app.buttons.allElementsBoundByIndex.contains { $0.label.hasPrefix(Self.satay) },
                       "Saved meals offers the satay as an ordinary meal")
        XCTAssertTrue(app.buttons.allElementsBoundByIndex.contains { $0.label.hasPrefix(Self.bowl) },
                      "the meal with no declared allergen was hidden too")
    }

    // MARK: - Servings

    /// Saved meals → swipe the 200 g bowl → Servings → count of 2 → Save. The
    /// row then says 100 g, and choosing the meal pre-fills 100 g. The seed in
    /// `setUp` and `tearDown` takes the count back (`KitchenSeedPlan.apply`).
    func testAServingCountSetOnASavedMealIsWhatItPreFills() throws {
        try nutritionToolbarButton("Saved meals").tap()
        XCTAssertTrue(app.navigationBars["Saved meals"].waitForExistence(timeout: 10), "Saved meals never opened")

        let bowl = recipeButton(Self.bowl)
        XCTAssertTrue(bowl.waitForExistence(timeout: 10),
                      "the seeded bowl is not listed: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(bowl.label.contains("Serving: 200 g"), "the uncounted bowl is not one 200 g serving: \(bowl.label)")

        bowl.swipeLeft()
        let servings = app.buttons["Servings"]
        XCTAssertTrue(servings.waitForExistence(timeout: 5), "the saved meal offers no Servings action")
        servings.tap()

        let toggle = app.switches["serving-count-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the servings sheet never opened")
        XCTAssertEqual(toggle.value as? String, "0", "the seeded bowl already had a count")
        toggle.tapSwitchControl()
        XCTAssertTrue(app.waitUntil(timeout: 5) { toggle.value as? String == "1" }, "the count could not be turned on")

        let stepper = app.steppers["serving-count-stepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), "no count control once a count is turned on")
        XCTAssertTrue(app.staticTexts["Servings: 2"].exists, "a new count does not start at 2")
        let preview = app.staticTexts["serving-count-preview"]
        XCTAssertEqual(preview.label, "Serving: 100 g", "the sheet does not show what one serving becomes")

        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 10) { !toggle.exists }, "Save did not close the sheet")

        XCTAssertTrue(app.waitUntil(timeout: 10) { recipeButton(Self.bowl).label.contains("Serving: 100 g") },
                      "the list still shows the whole bowl: \(recipeButton(Self.bowl).label)")

        recipeButton(Self.bowl).tap()
        let grams = app.textFields["Amount, in grams"]
        XCTAssertTrue(app.reveal(grams), "choosing the meal did not reach the logging form")
        XCTAssertEqual(grams.value as? String, "100", "one counted serving was not pre-filled")
    }

    // MARK: - Imported recipes

    /// A Wikibooks recipe (owner, T04, 2026-10-16) is listed with its credit
    /// and a link to its page, and, because its page states no serving count,
    /// choosing it asks how many it makes before the logging form opens with
    /// one serving. "Indian Rice" is 1,435.8 g in the shipped bundle.
    func testAnImportedRecipeIsCreditedAndAsksForServings() throws {
        try openRecipes()
        app.buttons["All"].tap()
        let field = app.textFields["Recipe name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "All offers no name search")
        field.tap()
        field.typeText("Indian Rice")

        // The recipes install after the nutrition reference, on first launch.
        let recipe = recipeButton("Indian Rice")
        XCTAssertTrue(recipe.waitForExistence(timeout: 120),
                      "the imported recipe is not listed: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(recipe.label.contains("Wikibooks Cookbook, CC BY-SA 4.0"),
                      "the recipe carries no credit: \(recipe.label)")
        XCTAssertTrue(anyElement("recipe-source-link-wikibooks-13950").exists, "no link to the recipe's page")

        recipe.tap()
        XCTAssertTrue(app.staticTexts["How many servings does this make?"].waitForExistence(timeout: 10),
                      "choosing a recipe with no stated count did not ask")
        XCTAssertTrue(app.staticTexts["Servings: 2"].exists, "the question does not start at 2")
        XCTAssertEqual(app.staticTexts["recipe-servings-preview"].label, "Serving: 718 g")
        app.buttons["recipe-servings-continue"].tap()

        XCTAssertTrue(app.waitUntil(timeout: 10) { !app.navigationBars["Recipes"].exists },
                      "answering did not hand the recipe on")
        let grams = app.textFields["Amount, in grams"]
        XCTAssertTrue(app.reveal(grams), "the logging form has no gram amount")
        XCTAssertEqual(grams.value as? String, "718", "one of two servings was not pre-filled")
    }

    // MARK: - Helpers

    /// The first element of any type carrying `identifier`.
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A recipe row in the picker, by the name its label starts with.
    private func recipeButton(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Recipes → Pantry. The toolbar's button, not the "Pantry" segment of the
    /// mode picker: both are buttons named Pantry (CI, 2026-10-06: "Multiple
    /// matching elements").
    private func openPantry() {
        app.navigationBars["Recipes"].buttons["Pantry"].tap()
        XCTAssertTrue(app.navigationBars["Pantry"].waitForExistence(timeout: 10), "the pantry never opened")
    }

    /// Pantry → Add → search for `name` → choose the food of exactly that name.
    private func addToPantryBySearch(_ name: String) {
        app.navigationBars["Pantry"].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Food search"].waitForExistence(timeout: 10),
                      "Add did not open the food search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.tap()
        field.typeText(name)

        // The exact name, so the rice bowl (whose name contains the rice's) is
        // not the row tapped.
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name))
            .matching(NSPredicate(format: "NOT (label CONTAINS %@)", "bowl")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15),
                      "\(name) was not found: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        result.tap()
    }

    /// Modules → Nutrition → Recipes, waiting for the catalogue: the button is
    /// disabled until the reference bundle has installed.
    private func openRecipes() throws {
        try nutritionToolbarButton("Recipes").tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 10), "Recipes never opened")
    }

    /// Modules → Nutrition, then the named toolbar button once it is enabled:
    /// Recipes and Saved meals are both disabled until the reference bundle has
    /// installed.
    private func nutritionToolbarButton(_ title: String) throws -> XCUIElement {
        let modules = app.buttons["tab-modules"].exists ? app.buttons["tab-modules"] : app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 15), "no Modules tab")
        modules.tap()
        let nutrition = app.buttons["Nutrition"]
        XCTAssertTrue(app.reveal(nutrition), "Nutrition is not reachable from Modules")
        nutrition.tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 10), "Nutrition never opened")

        let button = app.navigationBars["Nutrition"].buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10),
                      "no \(title) button: \(app.navigationBars["Nutrition"].buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(app.waitUntil(timeout: 120) { button.isEnabled },
                      "\(title) stayed disabled; the food catalogue never became available")
        return button
    }
}
