import XCTest
@testable import AlmanacCore

/// Importing the pipeline's bundle into the nutrition reference tables and reading
/// it back. The bundle is tools/nutrition/fixtures/bundle_v1.sql, written by the
/// pipeline's own union and bundle stages — this is the cross-language contract.
final class NutritionBundleImportTests: XCTestCase {

    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AlmanacCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // package root
        .appendingPathComponent("tools/nutrition/fixtures/bundle_v1.sql")

    /// A bundle file built from the fixture, optionally altered by SQL that bypasses
    /// the bundle's own CHECK constraints — a bundle that never went through the pipeline.
    private func bundle(altered alteration: String? = nil) throws -> String {
        let path = NSTemporaryDirectory() + "almanac-bundle-\(UUID().uuidString).sqlite"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let file = try Database(path: path)
        try file.execute(String(contentsOf: Self.fixture, encoding: .utf8))
        if let alteration { try file.execute("PRAGMA ignore_check_constraints = ON;\n" + alteration) }
        try file.execute("PRAGMA journal_mode = DELETE;")
        return path
    }

    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func ref(_ text: String) -> SourceIdentifier { SourceIdentifier(parsing: text)! }

    func testEveryBundledFoodIsReadableThroughTheCatalog() throws {
        let db = try migrated()
        let report = try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        XCTAssertEqual(report.namespaces, [.afcd, .almanac, .ciqual, .cofid, .usda])
        XCTAssertEqual(report.foodCount, 8)

        let catalog = NutritionCatalog(db: db)
        let bread = try XCTUnwrap(try catalog.food(ref("ciqual:900001")))
        XCTAssertEqual(bread.primaryName, "Fixture bread, white")
        XCTAssertEqual(bread.names["fr"], "Pain blanc (fixture)")
        XCTAssertEqual(bread.licenceGroup, .attribution)
        let values = Dictionary(uniqueKeysWithValues:
            try catalog.values(for: bread.ref, basis: .per100g).map { ($0.nutrientID, $0) })
        XCTAssertEqual(values["fat_total"]?.qualifier, .belowLOQ)
        XCTAssertEqual(values["fat_total"]?.amount, 0.5)
        XCTAssertEqual(values["fat_total"]?.sourceValue, "< 0,5")
        XCTAssertEqual(values["alcohol"]?.qualifier, .notAnalysed)
        XCTAssertNil(values["alcohol"]?.amount, "CIQUAL '-' is never 0")
        XCTAssertEqual(values["protein"]?.confidence, "A")
        XCTAssertNil(try catalog.food(ref("ciqual:404")))
    }

    func testCaloriesForImportedFoods() throws {
        let db = try migrated()
        try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        let catalog = NutritionCatalog(db: db)
        // 4 × 9.01 + 9 × 0 ("< 0,5") + 4 × (50.3 + 3.1) + 7 × 0 ("-") = 36.04 + 213.6 = 249.64
        let bread = try XCTUnwrap(try catalog.energy(for: ref("ciqual:900001"), basis: .per100g))
        XCTAssertEqual(bread.kilocalories, 249.64, accuracy: 1e-9)
        XCTAssertEqual(bread.inputsTakenAsZero, ["alcohol", "fat_total"])
        // 4 × 13.2 + 9 × 6.5 + 4 × 67.7 = 382.1 — not the published 379
        XCTAssertEqual(try catalog.energy(for: ref("usda:900001"), basis: .per100g)?.kilocalories ?? 0,
                       382.1, accuracy: 1e-9)
        // CoFID with no AOAC fibre row: the publisher's own 151, labelled as the publisher's
        let fruit = try XCTUnwrap(try catalog.energy(for: ref("cofid:900-001"), basis: .per100g))
        XCTAssertEqual(fruit.method, .publisherReported)
        XCTAssertEqual(fruit.kilocalories, 151)
        // Wine is published per 100 mL: 4 × (0.2 + 0) + 7 × 10.7 = 75.7, and there is no per 100 g figure
        XCTAssertEqual(try catalog.energy(for: ref("cofid:900-002"), basis: .per100ml)?.kilocalories ?? 0,
                       75.7, accuracy: 1e-9)
        XCTAssertNil(try catalog.energy(for: ref("cofid:900-002"), basis: .per100g))
        XCTAssertEqual(try catalog.bases(for: ref("afcd:F900001")), [.per100g, .per100ml])
    }

    func testNativeRowsShipAsGroupN() throws {
        let db = try migrated()
        try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        let catalog = NutritionCatalog(db: db)
        let dish = try XCTUnwrap(try catalog.food(ref("almanac:fixture-dish")))
        XCTAssertEqual(dish.licenceGroup, .native)
        XCTAssertEqual(dish.names["ar"], "طبق تجريبي")
        // 4 × 10 + 9 × 8 + 4 × (20 + 2) = 40 + 72 + 88 = 200
        XCTAssertEqual(try catalog.energy(for: dish.ref, basis: .per100g)?.kilocalories ?? 0, 200,
                       accuracy: 1e-9)
    }

    func testARepeatedPublisherCodeStaysTwoFoods() throws {
        let db = try migrated()
        try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        XCTAssertEqual(try NutritionCatalog(db: db).food(ref("cofid:900-004@row9"))?.primaryName,
                       "Fixture vegetable, repeated publisher code")
    }

    private func foodCount(_ db: Database) throws -> Int64? {
        try db.query("SELECT COUNT(*) AS n FROM nutrition_food;").first?.int("n")
    }

    // Processing Design v0.1 §1 and §5, enforced again on the device: a restricted row
    // fails the import loudly and by name, and nothing already imported changes.
    func testARestrictedRowFailsTheImportAndChangesNothing() throws {
        let db = try migrated()
        try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        let tampered = try bundle(altered:
            "UPDATE nutrition_food SET licence_group = 'D' WHERE food_ref = 'cofid:900-001';")
        XCTAssertThrowsError(try NutritionReferenceImporter(db: db).importBundle(at: tampered)) { error in
            XCTAssertTrue(error is LicenceViolation, "\(error)")
            XCTAssertTrue("\(error)".contains("cofid:900-001"), "\(error)")
        }
        XCTAssertEqual(try NutritionCatalog(db: db).food(ref("cofid:900-001"))?.licenceGroup, .attribution)
        XCTAssertEqual(try foodCount(db), 8)
    }

    // Group B ships, but USDA is group A: a bundle saying otherwise was not built by the pipeline.
    func testALicenceGroupThatDisagreesWithItsNamespaceIsRefused() throws {
        for alteration in ["UPDATE nutrition_food SET licence_group = 'B' WHERE food_ref = 'usda:900001';",
                           "UPDATE nutrition_value SET licence_group = 'B' WHERE food_ref = 'usda:900001';",
                           "UPDATE nutrition_source SET licence_group = 'B' WHERE namespace = 'usda';"] {
            let db = try migrated()
            XCTAssertThrowsError(try NutritionReferenceImporter(db: db).importBundle(at: bundle(altered: alteration)),
                                 alteration)
            XCTAssertEqual(try foodCount(db), 0, alteration)
        }
    }

    func testQualifierMeaningsMustBeSwiftsOwn() throws {
        let db = try migrated()
        let drifted = try bundle(altered:
            "UPDATE nutrition_qualifier SET has_quantity = 1 WHERE qualifier = 'not_analysed';")
        XCTAssertThrowsError(try NutritionReferenceImporter(db: db).importBundle(at: drifted)) {
            XCTAssertTrue("\($0)".contains("not_analysed"), "\($0)")
        }
        XCTAssertEqual(try foodCount(db), 0)
    }

    func testAnUnsupportedSchemaOrAMissingFileIsRefused() throws {
        let db = try migrated()
        XCTAssertThrowsError(try NutritionReferenceImporter(db: db).importBundle(at: bundle(altered:
            "UPDATE bundle_meta SET value = '2' WHERE key = 'schema_version';")))
        let missing = NSTemporaryDirectory() + "almanac-no-such-bundle-\(UUID().uuidString).sqlite"
        XCTAssertThrowsError(try NutritionReferenceImporter(db: db).importBundle(at: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing), "ATTACH must not have created it")
    }

    // Names are folded with Laboratory's TextFold, so case, accents and Arabic letter
    // variants do not decide whether a food is found.
    func testSearchMatchesEveryLanguageFoldedAndReturnsEachFoodOnce() throws {
        let db = try migrated()
        try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        let catalog = NutritionCatalog(db: db)
        XCTAssertEqual(try catalog.search("PÂIN").map(\.ref), [ref("ciqual:900001")], "French name, folded")
        XCTAssertEqual(try catalog.search("طبق").map(\.ref), [ref("almanac:fixture-dish")], "Arabic name")
        XCTAssertEqual(try catalog.search("bread").map(\.ref), [ref("ciqual:900001")],
                       "matched in English only once, though it has two names")
        XCTAssertEqual(try catalog.search("fixture", limit: 3).count, 3)
        XCTAssertEqual(try catalog.search("fixture").count, 8)
        XCTAssertEqual(try catalog.search("  ").count, 0)
        XCTAssertEqual(try catalog.search("100%").count, 0, "LIKE wildcards in a query are literal")
    }

    // Removing a whole source stays one step (§3): the next bundle without it removes it here too.
    func testReimportingReplacesAndDropsARemovedSource() throws {
        let db = try migrated()
        try NutritionReferenceImporter(db: db).importBundle(at: bundle())
        let withoutCoFID = try bundle(altered: """
            DELETE FROM nutrition_value WHERE food_ref LIKE 'cofid:%';
            DELETE FROM nutrition_food_name WHERE food_ref LIKE 'cofid:%';
            DELETE FROM nutrition_food WHERE namespace = 'cofid';
            DELETE FROM nutrition_source WHERE namespace = 'cofid';
            """)
        let report = try NutritionReferenceImporter(db: db).importBundle(at: withoutCoFID)
        XCTAssertEqual(report.namespaces, [.afcd, .almanac, .ciqual, .usda])
        XCTAssertNil(try NutritionCatalog(db: db).food(ref("cofid:900-001")))
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM nutrition_reference_import;").first?.int("n"), 2)
    }
}
