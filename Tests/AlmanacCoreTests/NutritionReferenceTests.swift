import XCTest
@testable import AlmanacCore

/// Migration 008: the nutrition reference tables, module-prefixed per
/// docs/architecture/health-data-foundation.md §12.
final class NutritionReferenceTests: XCTestCase {

    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func seedOneFood(_ db: Database) throws {
        try db.execute("""
        INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group, attribution, url)
        VALUES ('cofid', 'cofid_2021', 'CoFID 2021', '2021', 'Open Government Licence v3.0', 'B',
                'Contains public sector information licensed under the Open Government Licence v3.0.',
                'https://www.gov.uk/');
        INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
        VALUES ('protein', 'PROCNT', 'Protein', 'g', '');
        INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                    food_group_name, source_record)
        VALUES ('cofid:13-145', 'cofid', '13-145', 'B', 'DG', 'Vegetables, general', 'fixture');
        """)
    }

    private func insertValue(_ db: Database, amount: String, qualifier: String, cell: String,
                             ref: String = "cofid:13-145") throws {
        try db.execute("""
        INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, source_value,
                                     source_nutrient_id, source_unit, licence_group)
        VALUES ('\(ref)', 'protein', 'per_100g', \(amount), '\(qualifier)', '\(cell)', 'PROT', 'g', 'B');
        """)
    }

    func testMigration008AddsModulePrefixedReferenceTables() throws {
        let db = try migrated()
        let tables = Set(try db.query("""
            SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'nutrition!_%' ESCAPE '!';
            """).compactMap { $0.string("name") })
        // Migrations 009-011 (food log, portions and native dishes, portion
        // identity) are module-prefixed the same way; this asserts the full
        // set migration 008 through 011 leaves behind. Not asserted against
        // `applied(in:).last?.version`: later modules append their own
        // migrations above 011, and this test only owns the nutrition ones.
        XCTAssertEqual(tables, ["nutrition_source", "nutrition_nutrient", "nutrition_food",
                                "nutrition_food_name", "nutrition_value", "nutrition_reference_import",
                                "nutrition_log", "nutrition_log_revision", "nutrition_dish",
                                "nutrition_portion", "nutrition_dish_component"])
        let versions = Set(try MigrationRunner(migrations: AlmanacMigrations.all).applied(in: db).map(\.version))
        XCTAssertTrue([9, 10, 11].allSatisfy(versions.contains), "expected migrations 9-11 applied, got \(versions.sorted())")
    }

    // Defence in depth: the database refuses what the bundle guard refuses, by any route.
    func testTheTablesRefuseRestrictedRowsAndCoercedTokens() throws {
        let db = try migrated()
        try seedOneFood(db)
        XCTAssertThrowsError(try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group, attribution, url)
            VALUES ('sfda', 'sfda', 'SFDA', '2026', 'unclear', 'D', '', '');
            """), "a group D source")
        XCTAssertThrowsError(try db.execute("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES ('cofid:x', 'cofid', 'x', 'C', '', '', '');
            """), "a group C food")
        XCTAssertThrowsError(try insertValue(db, amount: "0", qualifier: "trace", cell: "Tr"), "Tr coerced to 0")
        XCTAssertThrowsError(try insertValue(db, amount: "NULL", qualifier: "measured", cell: "2.9"))
        XCTAssertThrowsError(try insertValue(db, amount: "0.5", qualifier: "zero_reported", cell: "0.5"))
        XCTAssertThrowsError(try insertValue(db, amount: "2.9", qualifier: "guessed", cell: "2.9"))
        XCTAssertNoThrow(try insertValue(db, amount: "NULL", qualifier: "trace", cell: "Tr"))
    }

    func testEveryQualifierTheSwiftEnumKnowsIsAccepted() throws {
        let db = try migrated()
        try seedOneFood(db)
        for (index, qualifier) in NutrientQualifier.allCases.enumerated() {
            let ref = "cofid:q\(index)"
            try db.execute("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES ('\(ref)', 'cofid', 'q\(index)', 'B', '', '', 'fixture');
            """)
            let amount = [.trace, .notAnalysed].contains(qualifier) ? "NULL"
                : qualifier == .zeroReported ? "0" : "1.5"
            XCTAssertNoThrow(try insertValue(db, amount: amount, qualifier: qualifier.rawValue, cell: "x", ref: ref),
                             qualifier.rawValue)
        }
    }

    // MARK: - Arabic search folding

    /// A food's `name_fold` is computed once, at import (`NutritionReferenceImporter`,
    /// mirroring `TextFold.fold` exactly as it would run there), and stored —
    /// these tests seed it the same way rather than through the importer, to
    /// stay focused on `NutritionCatalog.search`'s own folded matching.
    private func seedArabicFood(_ db: Database, ref: String, arabicName: String) throws {
        try db.execute("""
        INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                      attribution, url)
        VALUES ('almanac', 'almanac_native', 'Almanac native foods', '', 'Almanac proprietary', 'N', '', '')
        ON CONFLICT (namespace) DO NOTHING;
        """)
        let localID = String(ref.split(separator: ":", maxSplits: 1)[1])
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES (?, 'almanac', ?, 'N', '', '', 'fixture');
            """, [.text(ref), .text(localID)])
        try db.run("""
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
            VALUES (?, 'ar', ?, 1, ?);
            """, [.text(ref), .text(arabicName), .text(TextFold.fold(arabicName))])
    }

    /// Hamza and harakat variants of one word must fold to the same key, and
    /// tatweel (an elongation mark, never a letter) must be dropped rather
    /// than treated as one.
    func testSearchMatchesHamzaHarakatAndTatweelVariants() throws {
        let db = try migrated()
        // "إبريق" (a jug) written with an initial hamza-below, diacritics, and
        // a tatweel inserted between the second and third letters.
        try seedArabicFood(db, ref: "almanac:jug", arabicName: "إِبْرِيـــق")
        let results = try NutritionCatalog(db: db).search("ابريق")
        XCTAssertEqual(results.map(\.ref.description), ["almanac:jug"],
                       "hamza, harakat and tatweel are decoration, not identity")
    }

    /// A measure or food name with irregular internal spacing still folds to
    /// one collapsed key, so extra whitespace in either the stored name or
    /// the typed query never breaks the match.
    func testSearchFoldsArabicNamesAcrossSurroundingAndInternalSpaces() throws {
        let db = try migrated()
        try seedArabicFood(db, ref: "almanac:bread", arabicName: "  خبز   عربي  ")
        XCTAssertEqual(try NutritionCatalog(db: db).search("خبز عربي").map(\.ref.description),
                       ["almanac:bread"])
        XCTAssertEqual(try NutritionCatalog(db: db).search("عربي").map(\.ref.description),
                       ["almanac:bread"], "internal spacing collapses on both sides of the match")
    }

    /// Arabic-Indic digits (٠-٩) fold to their ASCII equivalents, so "خبز ٢"
    /// is found by a query typed with an ordinary "2".
    func testSearchFoldsArabicIndicDigits() throws {
        let db = try migrated()
        try seedArabicFood(db, ref: "almanac:bread-2", arabicName: "خبز ٢")
        XCTAssertEqual(try NutritionCatalog(db: db).search("خبز 2").map(\.ref.description),
                       ["almanac:bread-2"])
        XCTAssertEqual(TextFold.fold("خبز ٢"), TextFold.fold("خبز 2"))
    }
}
