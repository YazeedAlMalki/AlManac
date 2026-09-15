import XCTest
@testable import AlmanacCore

/// Household measures: `NutritionCatalog.addPortion`/`portion(of:unit:)`/`grams(of:...)`.
final class NutritionPortionTests: XCTestCase {

    private var db: Database!
    private var catalog: NutritionCatalog!
    private let rice = SourceIdentifier(namespace: .usda, localID: "1105904")

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        catalog = NutritionCatalog(db: db)
        try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
            VALUES ('usda', 'usda', 'USDA', '2026', 'CC0', 'A', '', '');
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES ('usda:1105904', 'usda', '1105904', 'A', '', '', 'fixture');
            """)
    }

    override func tearDown() {
        catalog = nil
        db = nil
        super.tearDown()
    }

    private func portion(_ amount: Double, _ unit: String, grams: Double,
                         modifier: String? = nil) -> NutritionPortion {
        NutritionPortion(foodRef: rice, amount: amount, unitText: unit, gramWeight: grams,
                         modifierText: modifier, licenceGroup: .permissive)
    }

    func testAHouseholdMeasureBecomesTheGramsThatGetLogged() throws {
        try catalog.addPortion(portion(1, "cup", grams: 158))
        XCTAssertEqual(try catalog.grams(of: rice, amount: 2, unit: "cups"), 316,
                       "the plural form of a stored singular still matches")
    }

    func testAPortionForAFoodThatIsNotThereIsRefused() throws {
        let ghost = SourceIdentifier(namespace: .usda, localID: "no-such-food")
        XCTAssertThrowsError(try catalog.addPortion(
            NutritionPortion(foodRef: ghost, amount: 1, unitText: "cup", gramWeight: 158,
                             licenceGroup: .permissive))) { error in
            guard case NutritionError.foodNotFound = error else {
                return XCTFail("expected foodNotFound, got \(error)")
            }
        }
    }

    func testAnInvalidGramWeightOrAmountIsRefused() throws {
        for bad in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try catalog.addPortion(portion(1, "cup", grams: bad))) { error in
                guard case NutritionError.invalidGramWeight = error else {
                    return XCTFail("expected invalidGramWeight for gramWeight \(bad), got \(error)")
                }
            }
            XCTAssertThrowsError(try catalog.addPortion(portion(bad, "cup", grams: 158))) { error in
                guard case NutritionError.invalidAmount = error else {
                    return XCTFail("expected invalidAmount for amount \(bad), got \(error)")
                }
            }
        }
    }

    /// USDA genuinely carries several "1 cup" rows for one food (raw vs
    /// cooked, say); picking one by row order would silently choose a mass.
    func testSeveralMeasuresOfTheSameUnitComeBackAmbiguous() throws {
        try catalog.addPortion(portion(1, "cup", grams: 158, modifier: "raw"))
        try catalog.addPortion(portion(1, "cup", grams: 195, modifier: "cooked"))
        guard case .ambiguous(let candidates) = try catalog.portion(of: rice, unit: "cup") else {
            return XCTFail("expected .ambiguous")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertNil(try catalog.grams(of: rice, amount: 1, unit: "cup"),
                     "an ambiguous measure resolves to no gram weight, not a guess")
    }

    func testAModifierNarrowsAnAmbiguousMeasure() throws {
        try catalog.addPortion(portion(1, "cup", grams: 158, modifier: "raw"))
        try catalog.addPortion(portion(1, "cup", grams: 195, modifier: "cooked"))
        XCTAssertEqual(try catalog.grams(of: rice, amount: 1, unit: "cup", modifier: "cooked"), 195)
    }

    func testAnUnmatchedModifierNarrowsToNothingRatherThanFallingBack() throws {
        try catalog.addPortion(portion(1, "cup", grams: 158, modifier: "raw"))
        try catalog.addPortion(portion(1, "cup", grams: 195, modifier: "cooked"))
        guard case .notFound = try catalog.portion(of: rice, unit: "cup", modifier: "toasted") else {
            return XCTFail("expected .notFound for an unmatched modifier")
        }
    }

    func testAddingTheSamePortionTwiceUpdatesRatherThanDuplicates() throws {
        try catalog.addPortion(portion(1, "cup", grams: 158))
        try catalog.addPortion(portion(1, "cup", grams: 158))
        XCTAssertEqual(try catalog.portions(of: rice).count, 1,
                       "re-adding an identical measure must not read back as an ambiguity with itself")
    }

    func testAnUnknownUnitIsNotFound() throws {
        try catalog.addPortion(portion(1, "cup", grams: 158))
        guard case .notFound = try catalog.portion(of: rice, unit: "tablespoon") else {
            return XCTFail("expected .notFound")
        }
    }
}
