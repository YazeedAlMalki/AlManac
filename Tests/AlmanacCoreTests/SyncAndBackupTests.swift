import XCTest
@testable import AlmanacCore

final class SyncAnchorStoreTests: XCTestCase {

    private func migratedDB() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    func testSaveAndLoadRoundTrips() throws {
        let db = try migratedDB()
        let clock = FixedClock(Date(timeIntervalSince1970: 1_780_000_000))
        let store = SyncAnchorStore(db: db, clock: clock)

        XCTAssertNil(try store.load("sleep"))
        try store.save(domain: "sleep", token: [0xDE, 0xAD, 0xBE, 0xEF])

        let anchor = try XCTUnwrap(try store.load("sleep"))
        XCTAssertEqual(anchor.token, [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertNil(anchor.lastError)
        XCTAssertEqual(anchor.lastSynced?.timeIntervalSince1970 ?? 0, 1_780_000_000, accuracy: 1)
    }

    func testSaveOverwritesSameDomain() throws {
        let db = try migratedDB()
        let store = SyncAnchorStore(db: db)
        try store.save(domain: "steps", token: [1])
        try store.save(domain: "steps", token: [2, 3])
        XCTAssertEqual(try store.load("steps")?.token, [2, 3])
        let count = try db.query("SELECT COUNT(*) AS n FROM sync_anchor;").first?.int("n")
        XCTAssertEqual(count, 1)
    }

    // A failed sync must never cost the last good anchor, or the next sync
    // re-imports the user's entire history.
    func testFailureKeepsLastGoodAnchor() throws {
        let db = try migratedDB()
        let store = SyncAnchorStore(db: db)
        try store.save(domain: "workouts", token: [9, 9, 9])
        try store.recordFailure(domain: "workouts", message: "HealthKit unavailable")

        let anchor = try XCTUnwrap(try store.load("workouts"))
        XCTAssertEqual(anchor.token, [9, 9, 9])
        XCTAssertEqual(anchor.lastError, "HealthKit unavailable")
    }

    func testFakeHealthProviderRequiresAuthorisation() async throws {
        let provider = FakeHealthProvider()
        do {
            _ = try await provider.changes(in: .sleep, since: nil)
            XCTFail("expected authorisationDenied")
        } catch HealthProviderError.authorisationDenied(let d) {
            XCTAssertEqual(d, .sleep)
        }

        try await provider.requestAuthorisation(for: [.sleep])
        let empty = try await provider.changes(in: .sleep, since: [7])
        XCTAssertTrue(empty.added.isEmpty)
        XCTAssertEqual(empty.nextAnchor, [7], "an empty batch must not reset the anchor")
    }
}

final class BackupServiceTests: XCTestCase {

    func testSnapshotIsRestorableAndRecorded() throws {
        let source = NSTemporaryDirectory() + "almanac-src-\(UUID().uuidString).sqlite"
        let dest = NSTemporaryDirectory() + "almanac-bak-\(UUID().uuidString).sqlite"
        defer {
            for p in [source, dest] { try? FileManager.default.removeItem(atPath: p) }
        }

        let db = try Database(path: source)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        try SyncAnchorStore(db: db).save(domain: "hrv", token: [4, 2])

        let bytes = try BackupService(db: db).snapshot(to: dest, note: "unit test")
        XCTAssertGreaterThan(bytes, 0)

        // The manifest row exists and carries a real digest.
        let row = try XCTUnwrap(try db.query(
            "SELECT sha256, schema_version, note FROM backup_manifest ORDER BY id DESC LIMIT 1;"
        ).first)
        XCTAssertEqual(row.string("sha256")?.count, 64)
        XCTAssertEqual(row.int("schema_version"), 1)
        XCTAssertEqual(row.string("note"), "unit test")

        // The snapshot really is a usable database with the data in it.
        let restored = try Database(path: dest)
        XCTAssertEqual(try SyncAnchorStore(db: restored).load("hrv")?.token, [4, 2])
    }

    func testKnownSHA256Vector() {
        XCTAssertEqual(
            SHA256File.hex(of: Array("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256File.hex(of: []),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testRestoreIsExplicitlyUnimplemented() throws {
        let db = try Database.inMemory()
        XCTAssertThrowsError(try BackupService(db: db).restore(from: "/tmp/whatever"))
    }
}
