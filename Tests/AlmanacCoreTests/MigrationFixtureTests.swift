import XCTest
@testable import AlmanacCore

/// Migration fixtures: real databases built through only the first N
/// migrations, seeded with rows, then upgraded the full list to head. This is
/// the "old install upgrades to current" flow the handoff's schema-v010/v015
/// scenario describes — not a synthetic `MigrationRunner` unit test, but an
/// actual old-shape database that must survive the real 001→head sequence.
///
/// Checkpoint versions (from the Slice 12 handoff): v010, just before
/// Migration015 re-shapes `sync_anchor` (old anchor rows die with the old
/// table — the fixture pins that this is expected), and v015, the first
/// version safe to seed hydration through `HydrationStore.log` (drink columns
/// land in 013). Head is read from `AlmanacMigrations` so these tests do not
/// hardcode a migration count.
final class MigrationFixtureTests: XCTestCase {

    private var head: Int { AlmanacMigrations.all.map { $0.version }.max() ?? 0 }

    /// Migrations 1...n, as an old app build would have shipped them.
    private func prefix(_ n: Int) -> [any Migration.Type] {
        AlmanacMigrations.all.filter { $0.version <= n }
    }

    private func appliedVersions(_ db: Database) throws -> [Int] {
        try MigrationRunner(migrations: []).applied(in: db).map(\.version)
    }

    private func foreignKeyViolations(_ db: Database) throws -> Int {
        try db.query("PRAGMA foreign_key_check;").count
    }

    // MARK: - v010 fixture: hydration does not exist yet; sync_anchor is old-shape

    func testV010DatabaseUpgradesToHeadWithDataSurviving() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: prefix(10)).migrate(db)

        // Seed health_sample (Migration004 shape — survives untouched to head).
        try db.run("""
        INSERT INTO health_sample
            (id, source_system, external_id, domain, start_at, end_at, value, unit,
             source_name, recorded_at, recorded_tz_offset_minutes, deleted_at)
        VALUES ('hs-1', 'healthkit', 'ext-1', 'steps', '2026-01-01T00:00:00Z', '2026-01-01T00:05:00Z',
                1200, 'count', 'Health', '2026-01-01T00:06:00Z', 180, NULL);
        """)
        // Seed the OLD sync_anchor shape (Migration001: domain-keyed). It exists
        // at v010 and Migration015 drops that table entirely.
        try db.run("""
        INSERT INTO sync_anchor (domain, anchor_token, last_synced, last_error)
        VALUES ('steps', x'0102', '2026-01-01T00:00:00Z', NULL);
        """)
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM health_sample;").first?.int("n"), 1)
        XCTAssertEqual(try db.query("SELECT domain FROM sync_anchor;").first?.string("domain"), "steps")

        // Upgrade 001→head. `migrate` returns only the migrations it applied
        // in this call (11...head were pending on a v010 install).
        let applied = try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        XCTAssertEqual(Set(applied), Set((11...head)), "every pending migration from the fixture version to head runs")
        XCTAssertEqual(try appliedVersions(db), Array(1...head))

        // Rows seeded before the upgrade survive.
        let sample = try XCTUnwrap(db.query("SELECT * FROM health_sample WHERE id = 'hs-1';").first)
        XCTAssertEqual(sample.double("value"), 1200)
        XCTAssertEqual(sample.string("unit"), "count")

        // The old-shape anchor is gone with its table: Migration015 dropped and
        // recreated sync_anchor under the spec shape, so the old domain row
        // cannot have survived — and the new table answers the new columns.
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM sync_anchor;").first?.int("n"), 0,
                       "old-shape sync_anchor rows are dropped with the old table (015), by design")
        XCTAssertNoThrow(try db.query("SELECT sampleType, anchorData, lastSyncTimestamp FROM sync_anchor;"),
                         "the new sync_anchor shape must be the one answerable at head")

        XCTAssertEqual(try foreignKeyViolations(db), 0, "no orphaned references after the upgrade")
    }

    // MARK: - v015 fixture: hydration exists with drink columns

    func testV015DatabaseUpgradesToHeadPreservingHydrationRows() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: prefix(15)).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000)) // 2026-02-25T06:13:20Z
        let store = HydrationStore(db: db, clock: clock)

        // Seed through the store, the real app path for this version (drink
        // columns exist from 013). A manual entry with a drink attachment.
        let loggedAt = Date(timeIntervalSince1970: 1_772_000_100)
        let manualID = try store.log(HydrationLogDraft(
            amount: Milliliters(250), loggedAt: loggedAt, note: "Seeded at v015",
            drink: DrinkAttachment(drinkID: "tap-water", drinkName: "Tap water",
                                   caloriesKcal: 0, sodiumMg: 1.5, sugarG: nil,
                                   qualifier: .catalogUnsourcedEstimate)))
        // A healthkit-sourced echo of the same writeback (the de-dup overlap,
        // seeded exactly as sync would have produced it at v015).
        try db.run("""
        UPDATE hydration_log SET healthkit_synced_at = ?, healthkit_external_id = 'hk-uuid-1'
        WHERE id = ?;
        """, [.text(clock.nowText()), .text(manualID)])
        _ = try store.apply(HealthChangeSet(
            added: [HealthSample(externalID: "hk-uuid-1", domain: .water,
                                 start: loggedAt, end: loggedAt, value: 250, unit: "ml")],
            deletedExternalIDs: [], nextAnchor: nil
        ), in: db)

        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM hydration_log;").first?.int("n"), 2)

        // Upgrade 001→head.
        let applied = try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        XCTAssertEqual(Set(applied), Set((16...head)), "016..head are the new migrations for a v015 db")
        XCTAssertEqual(try appliedVersions(db), Array(1...head))

        // Hydration rows survive with their columns intact.
        let manual = try XCTUnwrap(db.query("SELECT * FROM hydration_log WHERE id = ?;", [.text(manualID)]).first)
        XCTAssertEqual(manual.double("amount_ml"), 250)
        XCTAssertEqual(manual.string("note_text"), "Seeded at v015")
        XCTAssertEqual(manual.string("drink_name"), "Tap water")
        XCTAssertEqual(manual.string("healthkit_external_id"), "hk-uuid-1")
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM hydration_log;").first?.int("n"), 2,
                       "the healthkit echo must survive the upgrade (de-dup runs at restore, not at migrate)")

        XCTAssertEqual(try foreignKeyViolations(db), 0)
    }

    // MARK: - v035 fixture: workoutSession has no provenance columns yet

    /// A session logged before 036 must survive the upgrade and be able to take
    /// a HealthKit UUID afterwards — and a *second* manual session on the same
    /// day must still be allowed, which is why the unique index is partial.
    func testV035SessionSurvivesUpgradeAndTakesAHealthKitIdentity() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: prefix(35)).migrate(db)

        let now = "2026-09-01T08:00:00Z"
        try db.run("""
        INSERT INTO workoutSession (date, startTimestamp, durationMinutes, sessionType, createdAt, updatedAt)
        VALUES ('2026-09-01', '2026-09-01T07:00:00Z', 45, 'Running', '\(now)', '\(now)');
        """)

        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)

        // The pre-existing row is intact, with both new columns null.
        let upgraded = try XCTUnwrap(db.query("""
        SELECT id, date, durationMinutes, sessionType, source, healthKitUUID
        FROM workoutSession;
        """).first)
        XCTAssertEqual(upgraded.string("date"), "2026-09-01")
        XCTAssertEqual(upgraded.int("durationMinutes"), 45)
        XCTAssertEqual(upgraded.string("sessionType"), "Running")
        XCTAssertNil(upgraded.string("source"))
        XCTAssertNil(upgraded.string("healthKitUUID"))

        // It can now be claimed by a HealthKit workout.
        try db.run("UPDATE workoutSession SET source = 'healthkit', healthKitUUID = 'hk-1' WHERE id = ?;",
                   [.integer(upgraded.int("id")!)])
        let claimed = try XCTUnwrap(db.query("SELECT source, healthKitUUID FROM workoutSession;").first)
        XCTAssertEqual(claimed.string("source"), "healthkit")
        XCTAssertEqual(claimed.string("healthKitUUID"), "hk-1")

        // A second manual session the same day is still fine — manual rows have
        // no UUID, and the unique index must not treat NULLs as equal.
        try db.run("""
        INSERT INTO workoutSession (date, durationMinutes, createdAt, updatedAt)
        VALUES ('2026-09-01', 30, '\(now)', '\(now)');
        """)
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM workoutSession;").first?.int("n"), 2)

        // But the same HealthKit UUID twice is refused — that is the whole point
        // of the column.
        XCTAssertThrowsError(try db.run(
            "UPDATE workoutSession SET healthKitUUID = 'hk-1' WHERE id != ?;",
            [.integer(upgraded.int("id")!)]))
    }

    // MARK: - Cross-version bundle refusal, with a genuinely old bundle

    func testSchemaGateRefusesBundleFromRealOlderSchema() throws {
        let dir = NSTemporaryDirectory() + "almanac-fixture-\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let oldPath = dir + "/old.sqlite"
        let bundlePath = dir + "/old.almanac-backup"
        let targetPath = dir + "/target.sqlite"

        // A real v012 database (hydration exists, no drink columns yet) —
        // written by BackupService exactly as a v012 app would have shipped it.
        // Its sync_anchor is still the old Migration001 shape, so seed it raw.
        let old = try Database(path: oldPath)
        try MigrationRunner(migrations: prefix(12)).migrate(old)
        try old.run("""
        INSERT INTO sync_anchor (domain, anchor_token, last_synced, last_error)
        VALUES ('steps', x'0402', '2026-01-01T00:00:00Z', NULL);
        """)
        try BackupService(db: old).writeBundle(to: bundlePath, documentsRoot: nil, note: "exported at v012")

        // The bundle reports its own old schema, restorable only by a v012 app.
        XCTAssertEqual(try BackupService(db: old).readBundleInfo(at: bundlePath).schemaVersion, 12)

        // A fresh install at head refuses it before touching its own data.
        let target = try Database(path: targetPath)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(target)
        try SyncAnchorStore(db: target).save(domain: "hrv", token: [9])

        do {
            try BackupService(db: target).restoreBundle(at: bundlePath)
            XCTFail("a v012 bundle must be refused by a head-\(head) app")
        } catch BackupService.BackupError.incompatibleSchemaVersion(let found, let expected) {
            XCTAssertEqual(found, 12)
            XCTAssertEqual(expected, Int64(head))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try SyncAnchorStore(db: target).load("hrv")?.token, [9],
                       "the refused restore must leave the target database untouched")
    }
}

private extension FixedClock {
    func nowText() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: now)
    }
}