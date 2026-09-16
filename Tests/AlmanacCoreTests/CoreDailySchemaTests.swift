import XCTest
@testable import AlmanacCore

/// Migration 014 — the Slice 2 tables transcribed from Technical Spec §5.
///
/// These assert the schema the spec wrote, not a schema of this codebase's
/// choosing: camelCase column names included. If a future reconciliation pass
/// renames them, these tests are where that decision shows up.
final class CoreDailySchemaTests: XCTestCase {

    private func migratedDB() throws -> Database {
        let db = try Database.inMemory()
        let runner = try MigrationRunner(migrations: AlmanacMigrations.all)
        _ = try runner.migrate(db)
        return db
    }

    func testEveryMigrationAppliesInOrder() throws {
        let db = try Database.inMemory()
        let runner = try MigrationRunner(migrations: AlmanacMigrations.all)
        let applied = try runner.migrate(db)
        XCTAssertEqual(applied, Array(1...14))
    }

    func testSliceTwoTablesExist() throws {
        let db = try migratedDB()
        let expected = ["profile", "day_record", "circadian_context",
                        "shift_schedule", "shift_occurrence", "shift_recurrence_pattern",
                        "sleep_episode", "readiness_cycle", "vitals_record",
                        "mood_log", "soreness_log", "injury_note",
                        "readiness_record", "readiness_baseline"]
        for table in expected {
            let rows = try db.query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name = ?;",
                [.text(table)])
            XCTAssertEqual(rows.count, 1, "missing table \(table)")
        }
    }

    func testMutuallyReferentialSleepAndCycleTablesBothResolve() throws {
        let db = try migratedDB()
        // The forward reference in Migration014: sleep_episode names
        // readiness_cycle before it exists. Inserting into both proves the
        // loop closed rather than leaving a dangling foreign key.
        try db.execute("""
        INSERT INTO readiness_cycle (id, anchorDate, createdAt, updatedAt)
        VALUES (1, '2026-09-05', '2026-09-05T04:00:00Z', '2026-09-05T04:00:00Z');
        """)
        try db.execute("""
        INSERT INTO sleep_episode
            (id, startTimestamp, endTimestamp, timezoneOffset, durationMinutes,
             episodeType, source, readinessCycleId, logicalDay, createdAt, updatedAt)
        VALUES (1, '2026-09-04T23:00:00Z', '2026-09-05T06:00:00Z', '+03:00', 420,
                'primary', 'healthkit', 1, '2026-09-05',
                '2026-09-05T06:00:00Z', '2026-09-05T06:00:00Z');
        """)
        try db.execute("UPDATE readiness_cycle SET primarySleepEpisodeId = 1 WHERE id = 1;")

        let rows = try db.query("SELECT primarySleepEpisodeId FROM readiness_cycle WHERE id = 1;")
        XCTAssertEqual(rows.first?.int("primarySleepEpisodeId"), 1)
    }

    func testMoodAndSorenessEnforceTheirOneToTenRange() throws {
        let db = try migratedDB()
        XCTAssertThrowsError(try db.execute("""
        INSERT INTO mood_log (timestamp, timezoneOffset, logicalDay, score, createdAt)
        VALUES ('2026-09-05T08:00:00Z', '+03:00', '2026-09-05', 0, '2026-09-05T08:00:00Z');
        """), "0 is outside the spec's 1-10 scale")

        XCTAssertThrowsError(try db.execute("""
        INSERT INTO soreness_log (timestamp, timezoneOffset, logicalDay, overallScore, createdAt)
        VALUES ('2026-09-05T08:00:00Z', '+03:00', '2026-09-05', 11, '2026-09-05T08:00:00Z');
        """), "11 is outside the spec's 1-10 scale")

        try db.execute("""
        INSERT INTO mood_log (timestamp, timezoneOffset, logicalDay, score, createdAt)
        VALUES ('2026-09-05T08:00:00Z', '+03:00', '2026-09-05', 7, '2026-09-05T08:00:00Z');
        """)
    }

    func testVitalsRejectDuplicateHealthKitSamples() throws {
        let db = try migratedDB()
        let insert = """
        INSERT INTO vitals_record
            (timestamp, timezoneOffset, logicalDay, metric, value, unit, source, healthKitUUID, createdAt)
        VALUES ('2026-09-05T05:00:00Z', '+03:00', '2026-09-05', 'rhr', 51, 'count/min',
                'healthkit', 'HK-UUID-1', '2026-09-05T05:00:00Z');
        """
        try db.execute(insert)
        XCTAssertThrowsError(try db.execute(insert),
                             "re-syncing the same sample must not create a second row")
    }

    func testReadinessRecordDefaultsMatchTheSpec() throws {
        let db = try migratedDB()
        try db.execute("""
        INSERT INTO readiness_cycle (id, anchorDate, createdAt, updatedAt)
        VALUES (1, '2026-09-05', '2026-09-05T04:00:00Z', '2026-09-05T04:00:00Z');
        """)
        try db.execute("""
        INSERT INTO readiness_record
            (readinessCycleId, anchorDate, state, confidence, inputSnapshot,
             calculationTimestamp, createdAt, updatedAt)
        VALUES (1, '2026-09-05', 'provisional', 'medium', '{}',
                '2026-09-05T06:05:00Z', '2026-09-05T06:05:00Z', '2026-09-05T06:05:00Z');
        """)
        let rows = try db.query("""
        SELECT formulaVersion, missingInputs, precedenceApplied, baselineContext, score
        FROM readiness_record;
        """)
        XCTAssertEqual(rows.first?.string("formulaVersion"), "1.0")
        XCTAssertEqual(rows.first?.string("missingInputs"), "[]")
        XCTAssertEqual(rows.first?.string("precedenceApplied"), "[]")
        XCTAssertEqual(rows.first?.string("baselineContext"), "general")
        XCTAssertTrue(rows.first?.isNull("score") ?? false,
                      "an unscoreable day is null, never zero")
    }
}
