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
        XCTAssertEqual(tables, ["nutrition_source", "nutrition_nutrient", "nutrition_food",
                                "nutrition_food_name", "nutrition_value", "nutrition_reference_import"])
        XCTAssertEqual(try MigrationRunner(migrations: AlmanacMigrations.all).applied(in: db).last?.version, 8)
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
}
