import XCTest
@testable import AlmanacCore

private enum M1: Migration {
    static let version = 1
    static let name = "one"
    static func up(_ db: Database) throws { try db.execute("CREATE TABLE a (id INTEGER PRIMARY KEY);") }
}
private enum M2: Migration {
    static let version = 2
    static let name = "two"
    static func up(_ db: Database) throws { try db.execute("CREATE TABLE b (id INTEGER PRIMARY KEY);") }
}
private enum M2Renamed: Migration {
    static let version = 2
    static let name = "two_but_edited"
    static func up(_ db: Database) throws { try db.execute("CREATE TABLE b (id INTEGER PRIMARY KEY);") }
}
private enum M3Failing: Migration {
    static let version = 3
    static let name = "boom"
    static func up(_ db: Database) throws {
        try db.execute("CREATE TABLE c (id INTEGER PRIMARY KEY);")
        try db.execute("THIS IS NOT SQL;")
    }
}
private enum MDupA: Migration {
    static let version = 7
    static let name = "dup_a"
    static func up(_ db: Database) throws {}
}
private enum MDupB: Migration {
    static let version = 7
    static let name = "dup_b"
    static func up(_ db: Database) throws {}
}

final class MigrationRunnerTests: XCTestCase {

    private func tempDB() throws -> (Database, String) {
        let path = NSTemporaryDirectory() + "almanac-test-\(UUID().uuidString).sqlite"
        return (try Database(path: path), path)
    }

    func testAppliesInVersionOrder() throws {
        let db = try Database.inMemory()
        let runner = try MigrationRunner(migrations: [M2.self, M1.self])
        XCTAssertEqual(try runner.migrate(db), [1, 2])
        XCTAssertEqual(try runner.applied(in: db).map(\.version), [1, 2])
    }

    func testIsIdempotent() throws {
        let db = try Database.inMemory()
        let runner = try MigrationRunner(migrations: [M1.self, M2.self])
        XCTAssertEqual(try runner.migrate(db), [1, 2])
        XCTAssertEqual(try runner.migrate(db), [], "a second run must apply nothing")
    }

    func testFailedMigrationRollsBackEntirely() throws {
        let db = try Database.inMemory()
        let runner = try MigrationRunner(migrations: [M1.self, M3Failing.self])
        XCTAssertThrowsError(try runner.migrate(db))

        // M1 committed; M3 must have left no trace at all — not even the table
        // it successfully created before the bad statement.
        let tables = try db.query(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
        ).compactMap { $0.string("name") }
        XCTAssertTrue(tables.contains("a"))
        XCTAssertFalse(tables.contains("c"), "partial migration leaked a table")
        XCTAssertEqual(try runner.applied(in: db).map(\.version), [1])
    }

    func testRejectsDuplicateVersions() throws {
        XCTAssertThrowsError(try MigrationRunner(migrations: [MDupA.self, MDupB.self]))
    }

    func testDetectsEditedMigration() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: [M1.self, M2.self]).migrate(db)
        let tampered = try MigrationRunner(migrations: [M1.self, M2Renamed.self])
        XCTAssertThrowsError(try tampered.migrate(db)) { error in
            guard case MigrationError.checksumDrift = error else {
                return XCTFail("expected checksumDrift, got \(error)")
            }
        }
    }

    func testRejectsMigrationInsertedBehindHead() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: [M2.self]).migrate(db)
        let backfilled = try MigrationRunner(migrations: [M1.self, M2.self])
        XCTAssertThrowsError(try backfilled.migrate(db)) { error in
            guard case MigrationError.outOfOrder = error else {
                return XCTFail("expected outOfOrder, got \(error)")
            }
        }
    }

    func testMigration001CreatesCoreTables() throws {
        let (db, path) = try tempDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let tables = Set(try db.query(
            "SELECT name FROM sqlite_master WHERE type='table';"
        ).compactMap { $0.string("name") })
        XCTAssertTrue(tables.contains("sync_anchor"))
        XCTAssertTrue(tables.contains("backup_manifest"))
        XCTAssertTrue(tables.contains("schema_migrations"))
    }

    func testMigration037AddsHealthSampleTimezoneIdentifiers() throws {
        let (db, path) = try tempDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)

        let bodyColumns = Set(try db.query("PRAGMA table_info(body_composition_measurement);")
            .compactMap { $0.string("name") })
        let vitalsColumns = Set(try db.query("PRAGMA table_info(vitals_record);")
            .compactMap { $0.string("name") })
        XCTAssertTrue(bodyColumns.contains("timezoneIdentifier"))
        XCTAssertTrue(vitalsColumns.contains("timezoneIdentifier"))
    }

    func testMigration038AddsCustomMeasurementTimezoneColumns() throws {
        let (db, path) = try tempDB()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)

        let columns = Set(try db.query("PRAGMA table_info(custom_measurement_log);")
            .compactMap { $0.string("name") })
        XCTAssertTrue(columns.contains("timezoneOffset"))
        XCTAssertTrue(columns.contains("timezoneIdentifier"))
    }
}
