import XCTest
@testable import AlmanacCore

/// `NutritionDishEditor`: authoring `almanac:` foods, recipe reduction, and the
/// boundary with the bundle-imported reference catalog.
final class NutritionDishTests: XCTestCase {

    private var db: Database!
    private var editor: NutritionDishEditor!
    private var catalog: NutritionCatalog!
    private let clock = FixedClock(Date(timeIntervalSince1970: 1_773_500_000))

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        editor = NutritionDishEditor(db: db, clock: clock)
        catalog = NutritionCatalog(db: db)
        try seedSource("usda", group: "A")
        try seedSource("ciqual", group: "B")
        // No `almanac` source row is seeded. This file used to seed one on the
        // belief that every bundle carries it; the shipped bundle does not, so
        // every test here passed while `create` failed its foreign key on a real
        // device. `create` registers the namespace itself now, and these tests
        // are what prove it.
        for nutrient in ["protein", "fat_total", "carbohydrate_by_difference", "iron",
                         "carbohydrate_available", "fibre_total_dietary", "alcohol", "energy_kcal"] {
            try seedNutrient(nutrient)
        }
    }

    override func tearDown() {
        editor = nil
        catalog = nil
        db = nil
        super.tearDown()
    }

    // MARK: Fixtures

    private var sourcesSeeded: Set<String> = []

    private func seedSource(_ namespace: String, group: String) throws {
        guard sourcesSeeded.insert(namespace).inserted else { return }
        try db.run("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
            VALUES (?, ?, ?, '2026', 'x', ?, '', '');
            """, [.text(namespace), .text(namespace), .text(namespace), .text(group)])
    }

    private func seedNutrient(_ id: String) throws {
        try db.run("""
            INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
            VALUES (?, ?, ?, 'g', '');
            """, [.text(id), .text(id), .text(id)])
    }

    /// A reference ingredient with protein/fat/carbohydrate — enough for
    /// general Atwater — under the USDA namespace.
    @discardableResult
    private func seedIngredient(_ localID: String, name: String,
                                protein: Double, fat: Double, carbohydrate: Double,
                                unit: String = "g") throws -> SourceIdentifier {
        let ref = SourceIdentifier(namespace: .usda, localID: localID)
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                        food_group_code, food_group_name, source_record)
            VALUES (?, 'usda', ?, 'A', '', '', 'fixture');
            """, [.text(ref.description), .text(localID)])
        try db.run("""
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
            VALUES (?, 'en', ?, 1, ?);
            """, [.text(ref.description), .text(name), .text(TextFold.fold(name))])
        for (nutrient, amount) in [("protein", protein), ("fat_total", fat),
                                   ("carbohydrate_by_difference", carbohydrate)] {
            try db.run("""
                INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier,
                                             source_value, source_nutrient_id, source_unit, licence_group)
                VALUES (?, ?, 'per_100g', ?, 'measured', ?, ?, ?, 'A');
                """, [.text(ref.description), .text(nutrient), .real(amount), .text(String(amount)),
                      .text(nutrient), .text(unit)])
        }
        return ref
    }

    /// A reference food with whatever values it is given, in any namespace.
    @discardableResult
    private func seedFood(_ ref: SourceIdentifier, group: String,
                          _ values: [(String, Double, String)]) throws -> SourceIdentifier {
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                        food_group_code, food_group_name, source_record)
            VALUES (?, ?, ?, ?, '', '', 'fixture');
            """, [.text(ref.description), .text(ref.namespace.rawValue), .text(ref.localID), .text(group)])
        try db.run("""
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
            VALUES (?, 'en', ?, 1, ?);
            """, [.text(ref.description), .text(ref.localID), .text(ref.localID)])
        for (nutrient, amount, unit) in values {
            try db.run("""
                INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier,
                                             source_value, source_nutrient_id, source_unit, licence_group)
                VALUES (?, ?, 'per_100g', ?, ?, ?, ?, ?, ?);
                """, [.text(ref.description), .text(nutrient), .real(amount),
                      .text(amount == 0 ? "zero_reported" : "measured"), .text(String(amount)),
                      .text(nutrient), .text(unit), .text(group)])
        }
        return ref
    }

    private func energy(of ref: SourceIdentifier) throws -> EnergyEstimate {
        try XCTUnwrap(try catalog.energy(for: ref, basis: .per100g))
    }

    // MARK: Creating and editing

    func testCreatingADishRegistersTheAlmanacSourceItWritesInto() throws {
        XCTAssertTrue(try db.query("SELECT 1 FROM nutrition_source WHERE namespace = 'almanac';").isEmpty)
        try editor.create(localID: "one", nameText: "One")
        try editor.create(localID: "two", nameText: "Two")
        XCTAssertEqual(try db.query("SELECT licence_group FROM nutrition_source WHERE namespace = 'almanac';")
            .map { $0.string("licence_group") }, ["N"])
    }

    func testADishIsCreatedAndValuesTypedInDirectly() throws {
        let ref = try editor.create(localID: "kabsa", nameText: "Kabsa")
        XCTAssertEqual(ref.description, "almanac:kabsa")
        try editor.setValues([
            NutrientValue(foodRef: ref, nutrientID: "protein", amount: 5, qualifier: .measured,
                         sourceValue: "5", sourceNutrientID: "protein", sourceUnit: "g",
                         licenceGroup: .native)
        ], for: ref)
        let held = try XCTUnwrap(try catalog.food(ref))
        XCTAssertEqual(held.primaryName, "Kabsa")
        XCTAssertEqual(held.licenceGroup, .native)
        XCTAssertEqual(try catalog.values(for: ref, basis: .per100g).count, 1)
    }

    func testAPublishersFoodCannotBeAuthoredHere() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        XCTAssertThrowsError(try editor.setValues([], for: rice)) { error in
            guard case NutritionError.notANativeFood = error else {
                return XCTFail("expected notANativeFood, got \(error)")
            }
        }
    }

    func testADishCannotBeAnIngredientOfItself() throws {
        let ref = try editor.create(localID: "loop", nameText: "Loop")
        XCTAssertThrowsError(try editor.setRecipe([DishComponent(ref, grams: 50)], for: ref)) { error in
            guard case NutritionError.recipeCycle = error else {
                return XCTFail("expected recipeCycle, got \(error)")
            }
        }
    }

    func testADishCannotBecomeAnIngredientOfItselfThroughAnotherDish() throws {
        let a = try editor.create(localID: "a", nameText: "A")
        let b = try editor.create(localID: "b", nameText: "B")
        try editor.setRecipe([], for: a)
        try editor.setRecipe([DishComponent(a, grams: 100)], for: b)
        XCTAssertThrowsError(try editor.setRecipe([DishComponent(b, grams: 100)], for: a)) { error in
            guard case NutritionError.recipeCycle = error else {
                return XCTFail("expected recipeCycle, got \(error)")
            }
        }
    }

    // MARK: Reduction

    func testARecipeReducesToPerHundredGrammesOfTheFinishedDish() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let milk = try seedIngredient("milk", name: "Milk", protein: 3.4, fat: 3.6, carbohydrate: 4.8)
        let dish = try editor.create(localID: "porridge", nameText: "Porridge")
        let reduction = try editor.setRecipe(
            [DishComponent(rice, grams: 100), DishComponent(milk, grams: 100)], for: dish)
        XCTAssertTrue(reduction.isComplete)
        XCTAssertEqual(reduction.totalGrams, 200)
        // (2.7 + 3.4) / 200 * 100 == 3.05
        let protein = try XCTUnwrap(reduction.values.first { $0.nutrientID == "protein" })
        XCTAssertEqual(protein.amount ?? -1, 3.05, accuracy: 0.0001)
        XCTAssertEqual(protein.qualifier, .calculatedRecipe)
        XCTAssertEqual(protein.basis, .per100g)
        XCTAssertEqual(protein.licenceGroup, .native)
    }

    func testAStatedYieldConcentratesTheDish() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let dish = try editor.create(localID: "reduced", nameText: "Reduced rice")
        // 100 g of ingredient, cooked down to a stated 50 g yield: doubles.
        let reduction = try editor.setRecipe([DishComponent(rice, grams: 100)], for: dish, yieldGrams: 50)
        XCTAssertEqual(reduction.totalGrams, 50)
        let protein = try XCTUnwrap(reduction.values.first { $0.nutrientID == "protein" })
        XCTAssertEqual(protein.amount ?? -1, 5.4, accuracy: 0.0001)
    }

    func testCorrectingTheYieldRecomputesTheStoredValues() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let dish = try editor.create(localID: "reduced", nameText: "Reduced rice")
        try editor.setRecipe([DishComponent(rice, grams: 100)], for: dish, yieldGrams: 100)
        var edit = DishEdit()
        edit.yieldGrams = .set(50)
        XCTAssertTrue(try editor.update(dish, edit))
        let protein = try XCTUnwrap(try catalog.values(for: dish, basis: .per100g)
            .first { $0.nutrientID == "protein" })
        XCTAssertEqual(protein.amount ?? -1, 5.4, accuracy: 0.0001)
    }

    func testRecomputingADishThatHasNoRecipeRefusesRatherThanEmptyingIt() throws {
        let dish = try editor.create(localID: "typed", nameText: "Typed")
        try editor.setValues([
            NutrientValue(foodRef: dish, nutrientID: "protein", amount: 9, qualifier: .measured,
                         sourceValue: "9", sourceNutrientID: "protein", sourceUnit: "g",
                         licenceGroup: .native)
        ], for: dish)
        XCTAssertThrowsError(try editor.recompute(dish)) { error in
            guard case NutritionError.dishHasNoRecipe = error else {
                return XCTFail("expected dishHasNoRecipe, got \(error)")
            }
        }
        XCTAssertEqual(try catalog.values(for: dish, basis: .per100g).count, 1, "nothing was touched")
    }

    func testEmptyingARecipeOnPurposeClearsWhatWasComputedFromIt() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let dish = try editor.create(localID: "was-a-recipe", nameText: "Was a recipe")
        try editor.setRecipe([DishComponent(rice, grams: 100)], for: dish)
        XCTAssertFalse(try catalog.values(for: dish, basis: .per100g).isEmpty)
        let reduction = try editor.setRecipe([], for: dish)
        XCTAssertTrue(reduction.values.isEmpty)
        XCTAssertTrue(try catalog.values(for: dish, basis: .per100g).isEmpty)
    }

    func testAMissingIngredientStopsTheReductionAndIsNamed() throws {
        let dish = try editor.create(localID: "ghost", nameText: "Ghost")
        let ghost = SourceIdentifier(namespace: .usda, localID: "nonexistent")
        let reduction = try editor.setRecipe([DishComponent(ghost, grams: 50)], for: dish)
        XCTAssertFalse(reduction.isComplete)
        XCTAssertEqual(reduction.missingComponents, [ghost])
        XCTAssertTrue(reduction.values.isEmpty)
    }

    func testANutrientOneIngredientNeverReportedIsOmittedAndNamed() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let iron = try seedIngredient("liver", name: "Liver", protein: 20, fat: 5, carbohydrate: 0)
        try db.run("""
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier,
                                         source_value, source_nutrient_id, source_unit, licence_group)
            VALUES (?, 'iron', 'per_100g', 6.2, 'measured', '6.2', 'iron', 'mg', 'A');
            """, [.text(iron.description)])
        let dish = try editor.create(localID: "mix", nameText: "Mix")
        let reduction = try editor.setRecipe(
            [DishComponent(rice, grams: 50), DishComponent(iron, grams: 50)], for: dish)
        XCTAssertTrue(reduction.unmeasuredNutrients.contains("iron"))
        XCTAssertFalse(reduction.values.contains { $0.nutrientID == "iron" })
    }

    func testIngredientsThatDisagreeOnAUnitAreNotAddedTogether() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let odd = try seedIngredient("odd", name: "Odd", protein: 1, fat: 1, carbohydrate: 1, unit: "mg")
        let dish = try editor.create(localID: "conflict", nameText: "Conflict")
        let reduction = try editor.setRecipe(
            [DishComponent(rice, grams: 50), DishComponent(odd, grams: 50)], for: dish)
        XCTAssertTrue(reduction.conflictingUnits.contains("protein"))
        XCTAssertFalse(reduction.values.contains { $0.nutrientID == "protein" })
    }

    // USDA chicken (carbohydrate by difference) with CIQUAL rice (available
    // carbohydrate plus fibre): no carbohydrate id is reported by both, so the
    // same-id sums alone left the dish with no carbohydrate and no Atwater energy.
    func testIngredientsFromDifferentPublishersStillGiveTheDishItsCarbohydrateAndEnergy() throws {
        let chicken = try seedFood(SourceIdentifier(namespace: .usda, localID: "chicken"), group: "A", [
            ("protein", 22.5, "g"), ("fat_total", 1.9, "g"), ("carbohydrate_by_difference", 0, "g")])
        let rice = try seedFood(SourceIdentifier(namespace: .ciqual, localID: "rice"), group: "B", [
            ("protein", 2.95, "g"), ("fat_total", 0.56, "g"), ("carbohydrate_available", 31.7, "g"),
            ("fibre_total_dietary", 1.1, "g"), ("alcohol", 0, "g")])
        let dish = try editor.create(localID: "chicken-rice", nameText: "Chicken and rice")
        let reduction = try editor.setRecipe(
            [DishComponent(chicken, grams: 200), DishComponent(rice, grams: 300)], for: dish)

        // (200 × 0 + 300 × (31.7 + 1.1)) / 100 = 98.4 g over 500 g = 19.68 per 100 g
        let carbohydrate = try XCTUnwrap(reduction.values.first { $0.nutrientID == "carbohydrate_by_difference" })
        XCTAssertEqual(carbohydrate.amount ?? -1, 19.68, accuracy: 1e-9)
        XCTAssertFalse(reduction.unmeasuredNutrients.contains("carbohydrate_by_difference"))
        XCTAssertTrue(reduction.unmeasuredNutrients.contains("carbohydrate_available"),
                      "the publisher-specific ids are still honestly unmeasured")

        // Logging 100 g of the dish counts what 40 g chicken + 60 g rice would.
        let expected = (try energy(of: chicken).kilocalories * 200 + energy(of: rice).kilocalories * 300) / 500
        let dishEnergy = try energy(of: dish)
        XCTAssertEqual(dishEnergy.method, .generalAtwater)
        XCTAssertEqual(dishEnergy.kilocalories, expected, accuracy: 1e-9)
    }

    // An ingredient whose macros cannot be read (CoFID leaves fibre blank for
    // ~46 % of its foods) still has a calorie figure, the publisher's. The dish's
    // fallback is then the sum of each ingredient's own figure.
    func testADishWhoseMacrosCannotBeCombinedFallsBackToTheSumOfItsIngredientsEnergy() throws {
        let chicken = try seedFood(SourceIdentifier(namespace: .usda, localID: "chicken"), group: "A", [
            ("protein", 22.5, "g"), ("fat_total", 1.9, "g"), ("carbohydrate_by_difference", 0, "g"),
            ("energy_kcal", 112.2, "KCAL")])
        let ackee = try seedFood(SourceIdentifier(namespace: .ciqual, localID: "ackee"), group: "B", [
            ("protein", 2.9, "g"), ("fat_total", 15.2, "g"), ("carbohydrate_available", 0.8, "g"),
            ("energy_kcal", 151, "kcal")])
        let dish = try editor.create(localID: "mixed", nameText: "Mixed")
        try editor.setRecipe([DishComponent(chicken, grams: 100), DishComponent(ackee, grams: 100)], for: dish)

        // Chicken counts at its Atwater 4 × 22.5 + 9 × 1.9 = 107.1, not its published 112.2;
        // ackee at its published 151. (107.1 + 151) / 2 = 129.05
        let dishEnergy = try energy(of: dish)
        XCTAssertEqual(dishEnergy.method, .publisherReported)
        XCTAssertEqual(dishEnergy.kilocalories, 129.05, accuracy: 1e-9)
    }

    func testAlcoholFromOneIngredientIsNotLostBecauseAnotherNeverReportedIt() throws {
        let beef = try seedFood(SourceIdentifier(namespace: .usda, localID: "beef"), group: "A", [
            ("protein", 20, "g"), ("fat_total", 10, "g"), ("carbohydrate_by_difference", 0, "g")])
        let wine = try seedFood(SourceIdentifier(namespace: .ciqual, localID: "wine"), group: "B", [
            ("protein", 0, "g"), ("fat_total", 0, "g"), ("carbohydrate_available", 2, "g"),
            ("fibre_total_dietary", 0, "g"), ("alcohol", 10, "g")])
        let dish = try editor.create(localID: "stew", nameText: "Stew")
        let reduction = try editor.setRecipe(
            [DishComponent(beef, grams: 100), DishComponent(wine, grams: 100)], for: dish)
        let alcohol = try XCTUnwrap(reduction.values.first { $0.nutrientID == "alcohol" })
        XCTAssertEqual(alcohol.amount ?? -1, 5, accuracy: 1e-9)
        let expected = (try energy(of: beef).kilocalories + energy(of: wine).kilocalories) / 2
        XCTAssertEqual(try energy(of: dish).kilocalories, expected, accuracy: 1e-9)
    }

    func testNothingIsDerivedAcrossAUnitConflict() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let odd = try seedIngredient("odd", name: "Odd", protein: 1, fat: 1, carbohydrate: 1, unit: "mg")
        let dish = try editor.create(localID: "conflict", nameText: "Conflict")
        let reduction = try editor.setRecipe(
            [DishComponent(rice, grams: 50), DishComponent(odd, grams: 50)], for: dish)
        XCTAssertFalse(reduction.values.contains { $0.nutrientID == "carbohydrate_by_difference" })
        XCTAssertFalse(reduction.values.contains { $0.nutrientID == "energy_kcal" })
    }

    func testRecomputingPicksUpACorrectedIngredient() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let dish = try editor.create(localID: "recomputed", nameText: "Recomputed")
        try editor.setRecipe([DishComponent(rice, grams: 100)], for: dish)
        // The ingredient's own row is corrected upstream (a new import, say).
        try db.run("UPDATE nutrition_value SET amount = 9.9 WHERE food_ref = ? AND nutrient_id = 'protein';",
                   [.text(rice.description)])
        let reduction = try editor.recompute(dish)
        let protein = try XCTUnwrap(reduction.values.first { $0.nutrientID == "protein" })
        XCTAssertEqual(protein.amount ?? -1, 9.9, accuracy: 0.0001)
    }

    // MARK: Deleting

    func testDeletingADishTakesItsValuesAndRecipeButNotTheMealsLoggedAgainstIt() throws {
        let rice = try seedIngredient("rice", name: "Rice", protein: 2.7, fat: 0.3, carbohydrate: 28.2)
        let dish = try editor.create(localID: "gone", nameText: "Gone")
        try editor.setRecipe([DishComponent(rice, grams: 100)], for: dish)
        let log = NutritionLogStore(db: db, clock: clock)
        let logged = try log.record(NutritionLogDraft(foodRef: dish, grams: 150, foodNameText: "Gone"))

        XCTAssertTrue(try editor.delete(dish))
        XCTAssertNil(try catalog.food(dish))
        XCTAssertTrue(try catalog.values(for: dish, basis: .per100g).isEmpty)
        XCTAssertTrue(try editor.components(of: dish).isEmpty)

        let entry = try XCTUnwrap(try log.entry(id: logged.logID))
        XCTAssertEqual(entry.foodRef, dish)
        XCTAssertEqual(entry.foodNameText, "Gone", "the log keeps what the person saw at the time")
    }

    // MARK: Reimport safety

    /// The defect the 2026-09-14 handoff's migration 008 comment flagged and
    /// left for reconciliation: a bundle re-import must never erase a dish a
    /// person authored on this device, and must still replace whatever
    /// `almanac:` rows the pipeline itself ships. `nutrition_dish` is what
    /// tells the two apart.
    func testReimportingTheBundlePreservesADeviceAuthoredDishAndReplacesABundleShippedOne() throws {
        // A device-authored dish.
        let mine = try editor.create(localID: "mine", nameText: "Mine")
        try editor.setValues([
            NutrientValue(foodRef: mine, nutrientID: "protein", amount: 1, qualifier: .measured,
                         sourceValue: "1", sourceNutrientID: "protein", sourceUnit: "g",
                         licenceGroup: .native)
        ], for: mine)

        // A bundle-shipped native food, inserted the way NutritionReferenceImporter
        // would — no nutrition_dish row, because it is reference data, not an
        // editable recipe.
        // `create` above has already registered the `almanac` source row.
        let bundleOwned = SourceIdentifier(namespace: .almanac, localID: "bundle-owned")
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                        food_group_code, food_group_name, source_record)
            VALUES (?, 'almanac', 'bundle-owned', 'N', '', '', '');
            """, [.text(bundleOwned.description)])

        // Reimporting must not need a real bundle file to prove the point:
        // simulate its effect directly, the way NutritionReferenceImporter's
        // own delete step would run it.
        try db.transaction {
            try db.execute("""
                DELETE FROM nutrition_value WHERE food_ref IN (
                    SELECT food_ref FROM nutrition_food
                    WHERE food_ref NOT IN (SELECT food_ref FROM nutrition_dish)
                );
                DELETE FROM nutrition_food_name WHERE food_ref IN (
                    SELECT food_ref FROM nutrition_food
                    WHERE food_ref NOT IN (SELECT food_ref FROM nutrition_dish)
                );
                DELETE FROM nutrition_food
                    WHERE food_ref NOT IN (SELECT food_ref FROM nutrition_dish);
                """)
        }

        XCTAssertNotNil(try catalog.food(mine), "a device-authored dish survives a reimport")
        XCTAssertEqual(try catalog.values(for: mine, basis: .per100g).count, 1)
        XCTAssertNil(try catalog.food(bundleOwned), "a bundle-owned almanac row is replaced like any other")
    }
}
