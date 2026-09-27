import XCTest
@testable import AlmanacCore

/// Gross (as-purchased) mass -> edible mass.
///
/// The cases that matter are the ones where the answer is *not* a number:
/// CoFID states an edible proportion for 2,887 of the bundle's 8,354 foods, so
/// the common outcome is that nobody said. Each of those is a distinct result
/// here, because collapsing them into `nil` is what makes the two tempting
/// wrong defaults (`?? 1.0`, `?? gross`) look reasonable.
final class EdibleYieldTests: XCTestCase {

    private var db: Database!
    private var yield_: EdibleYieldCalculator!
    private let rice = SourceIdentifier(namespace: .usda, localID: "1105904")

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        yield_ = EdibleYieldCalculator(db: db)
        try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
            VALUES ('usda', 'usda', 'USDA', '2026', 'CC0', 'A', '', '');
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
            VALUES ('almanac', 'almanac', 'Almanac', '2026', 'N', 'N', '', '');
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES ('usda:1105904', 'usda', '1105904', 'A', '', '', 'fixture');
            """)
    }

    override func tearDown() {
        yield_ = nil
        db = nil
        super.tearDown()
    }

    /// Writes a `nutrition_food_factor` row directly, including the ones the
    /// bundle's own CHECK constraints would refuse — `source_record` is part
    /// of the primary key, so this is the only way to plant those.
    private func factor(_ value: Double?, _ qualifier: NutrientQualifier,
                        kind: NutritionFoodFactor.Kind = .edibleProportion,
                        sourceValue: String, record: String = "r1",
                        ref: SourceIdentifier? = nil) throws {
        try db.run("""
            INSERT INTO nutrition_food_factor
                (food_ref, kind, value, qualifier, source_value, source_record, licence_group)
            VALUES (?, ?, ?, ?, ?, ?, 'A');
            """, [.text((ref ?? rice).description), .text(kind.rawValue),
                  value.map(SQLValue.real) ?? .null, .text(qualifier.rawValue),
                  .text(sourceValue), .text(record)])
    }

    // MARK: The stated case

    func testAStatedProportionIsAppliedToTheGrossMass() throws {
        try factor(0.65, .measured, sourceValue: "fraction 0,65")
        let result = try yield_.edibleGrams(fromGrossGrams: 200, for: rice)
        let grams = try XCTUnwrap(result.edibleGrams)
        XCTAssertEqual(grams, 130, accuracy: 1e-9)
        XCTAssertTrue(result.isStated)
        guard case .known(_, let source) = result else {
            return XCTFail("expected .known, got \(result)")
        }
        XCTAssertEqual(source.shortDescription, "fraction 0,65",
                       "a derived mass must be able to name the number it came from")
    }

    func testProportionOneIsUsableAndIsNotTreatedAsMissing() throws {
        try factor(1.0, .measured, sourceValue: "fraction 1")
        let result = try yield_.edibleGrams(fromGrossGrams: 75, for: rice)
        XCTAssertEqual(try XCTUnwrap(result.edibleGrams), 75, accuracy: 1e-9)
    }

    // MARK: The three ways there is no number

    func testAFoodWithNoFactorRowIsUnstatedNotOne() throws {
        let result = try yield_.edibleGrams(fromGrossGrams: 200, for: rice)
        XCTAssertEqual(result, .unstated)
        XCTAssertNil(result.edibleGrams)
        XCTAssertFalse(result.isStated,
                       "unstated is not a licence to treat the gross mass as edible")
    }

    func testAFactorThatCarriesNoQuantityIsNotAnalysedNotZero() throws {
        try factor(nil, .notAnalysed, sourceValue: "N")
        let result = try yield_.edibleGrams(fromGrossGrams: 200, for: rice)
        guard case .notAnalysed = result else { return XCTFail("expected .notAnalysed, got \(result)") }
        XCTAssertNil(result.edibleGrams, "a token never becomes a number")
    }

    func testAProportionOutsideZeroToOneIsRefusedRatherThanClamped() throws {
        // NaN is absent from this list because SQLite stores it as NULL, so a
        // NaN proportion is indistinguishable from "not analysed" by the time
        // it reaches the reader — and `.notAnalysed` is already the honest
        // answer for it. Infinity does survive, and is a real value to refuse.
        for bad in [1.5, 0.0, -0.2, .infinity] {
            try? db.execute("DELETE FROM nutrition_food_factor;")
            try? db.run("PRAGMA ignore_check_constraints = ON;")
            try factor(bad, .measured, sourceValue: "fraction \(bad)")
            try? db.execute("PRAGMA ignore_check_constraints = OFF;")

            let result = try yield_.edibleGrams(fromGrossGrams: 200, for: rice)
            guard case .unusable(let reason) = result else {
                return XCTFail("expected .unusable for \(bad), got \(result)")
            }
            XCTAssertFalse(reason.isEmpty)
            XCTAssertNil(result.edibleGrams, "an out-of-range figure is the bundle's bug, not a usable mass")
        }
    }

    // MARK: A dish's own figure wins over a reference one

    func testADishUsesItsOwnAuthoredProportion() throws {
        let editor = NutritionDishEditor(db: db)
        let dish = try editor.create(localID: "kubba", nameText: "Kubba", edibleProportion: 0.8)
        XCTAssertEqual(try yield_.edibleProportion(for: dish), .known(0.8, from: .dish))
        let result = try yield_.edibleGrams(fromGrossGrams: 500, for: dish)
        XCTAssertEqual(try XCTUnwrap(result.edibleGrams), 400, accuracy: 1e-9)
    }

    func testADishWithNoProportionIsUnstatedNotOne() throws {
        let dish = try NutritionDishEditor(db: db).create(localID: "salad", nameText: "Salad")
        XCTAssertEqual(try yield_.edibleProportion(for: dish), .unstated)
    }

    func testANativeRefWithNoDishRowIsUnstated() throws {
        let ghost = SourceIdentifier(namespace: .almanac, localID: "not-authored")
        XCTAssertEqual(try yield_.edibleProportion(for: ghost), .unstated)
    }

    // MARK: Density

    func testAVolumeBecomesGramsThroughTheStatedDensity() throws {
        try factor(1.03, .measured, kind: .specificGravity, sourceValue: "1,03 g/ml")
        let result = try yield_.grams(fromVolumeMillilitres: 200, for: rice)
        XCTAssertEqual(try XCTUnwrap(result.edibleGrams), 206, accuracy: 1e-9)
    }

    func testAFoodWithNoDensityIsUnstatedNotAUnitDensity() throws {
        XCTAssertEqual(try yield_.grams(fromVolumeMillilitres: 200, for: rice), .unstated,
                       "1 mL = 1 g is an assumption, not a measurement")
    }

    func testANonPositiveDensityIsRefused() throws {
        try? db.execute("PRAGMA ignore_check_constraints = ON;")
        try factor(0, .measured, kind: .specificGravity, sourceValue: "0 g/ml")
        try? db.execute("PRAGMA ignore_check_constraints = OFF;")
        guard case .unusable = try yield_.grams(fromVolumeMillilitres: 200, for: rice) else {
            return XCTFail("a zero density is not a usable one")
        }
    }

    // MARK: Bad input is a caller error, not a data gap

    func testANonPositiveGrossMassThrowsRatherThanReportingAGap() throws {
        try factor(0.65, .measured, sourceValue: "fraction 0,65")
        for bad in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try yield_.edibleGrams(fromGrossGrams: bad, for: rice)) { error in
                guard case NutritionError.invalidGramWeight = error else {
                    return XCTFail("expected invalidGramWeight for \(bad), got \(error)")
                }
            }
        }
    }

    func testANonPositiveVolumeThrows() throws {
        XCTAssertThrowsError(try yield_.grams(fromVolumeMillilitres: 0, for: rice)) { error in
            guard case NutritionError.invalidAmount = error else {
                return XCTFail("expected invalidAmount, got \(error)")
            }
        }
    }
}
