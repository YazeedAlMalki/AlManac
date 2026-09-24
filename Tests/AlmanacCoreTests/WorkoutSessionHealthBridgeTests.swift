import XCTest
@testable import AlmanacCore

/// HealthKit workouts were the one domain with no writer and no place to put a
/// result: `workoutSession` had no `source`/`healthKitUUID` before Migration036,
/// so there was nowhere to upsert idempotently.
///
/// Driven through the real seam — `HealthSyncService` over a `FakeHealthProvider`
/// — and read back through `WorkoutSessionStore`, the same surface the Training
/// tab reads.
final class WorkoutSessionHealthBridgeTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func fixture() throws -> (Database, FakeHealthProvider, WorkoutSessionHealthBridge) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let provider = FakeHealthProvider()
        return (db, provider,
                WorkoutSessionHealthBridge(db: db, clock: clock,
                                          timeModel: TimeModel(timeZone: utc),
                                          zone: ZoneContext(utc)))
    }

    private func workout(_ id: String, _ start: String, _ end: String,
                         activity: String = "running") -> HealthSample {
        let formatter = ISO8601DateFormatter()
        return HealthSample(externalID: id, domain: .workouts,
                            start: formatter.date(from: start)!,
                            end: formatter.date(from: end)!,
                            value: nil, unit: nil, sourceName: "Apple Watch",
                            activity: activity)
    }

    @discardableResult
    private func sync(_ bridge: WorkoutSessionHealthBridge, _ provider: FakeHealthProvider,
                      _ db: Database, added: [HealthSample], deleted: [String] = [],
                      anchor: [UInt8] = [1]) async throws -> HealthSyncService {
        try await provider.requestAuthorisation(for: [.workouts])
        provider.enqueue(HealthChangeSet(added: added, deletedExternalIDs: deleted, nextAnchor: anchor),
                         for: .workouts)
        let service = HealthSyncService(db: db, provider: provider, writer: bridge,
                                        healthDomain: .workouts)
        _ = try await service.syncOnce()
        return service
    }

    private func sessions(_ db: Database) throws -> [WorkoutSessionEntry] {
        try WorkoutSessionStore(db: db).sessions(date: "2026-02-11")
    }

    // MARK: - Create

    /// The tracer bullet: a watch workout with nothing logged becomes a session
    /// carrying its activity, times and duration, with no bouts.
    func testUnmatchedWorkoutBecomesASession() async throws {
        let (db, provider, bridge) = try fixture()
        try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z"),
        ])

        let all = try db.query("""
        SELECT date, startTimestamp, endTimestamp, durationMinutes, sessionType,
               source, healthKitUUID
        FROM workoutSession;
        """)
        XCTAssertEqual(all.count, 1)
        let row = try XCTUnwrap(all.first)
        XCTAssertEqual(row.string("date"), "2026-02-11")
        XCTAssertEqual(row.string("sessionType"), "Running")
        XCTAssertEqual(row.int("durationMinutes"), 45)
        XCTAssertEqual(row.string("source"), "healthkit")
        XCTAssertEqual(row.string("healthKitUUID"), "hk-1")
        // No bouts: a watch workout records time and activity, not sets and reps.
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM workoutBout;").first?.int("n"), 0)
    }

    /// Activity identifiers HealthKit spells its own way still produce a readable
    /// label rather than a dropped sample — and two genuinely different strength
    /// activities stay distinguishable.
    func testCompoundActivityIdentifierBecomesAReadableLabel() async throws {
        let (db, provider, bridge) = try fixture()
        try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T18:00:00Z", "2026-02-11T18:50:00Z",
                    activity: "traditionalStrengthTraining"),
            workout("hk-2", "2026-02-11T19:00:00Z", "2026-02-11T19:30:00Z",
                    activity: "highIntensityIntervalTraining"),
        ])

        let types = try db.query("SELECT sessionType FROM workoutSession ORDER BY id;")
            .compactMap { $0.string("sessionType") }
        XCTAssertEqual(types, ["Traditional Strength Training", "High Intensity Interval Training"])
    }

    /// An activity Almanac has never heard of must not be lost — the long tail
    /// of HealthKit's ~80 types is not worth an exhaustive table.
    func testUnknownActivityFallsBackToACapitalisedLabel() async throws {
        let (db, provider, bridge) = try fixture()
        try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z",
                    activity: "someFutureAppleActivity"),
        ])

        XCTAssertEqual(try db.query("SELECT sessionType FROM workoutSession;").first?
            .string("sessionType"), "Some Future Apple Activity")
    }

    // MARK: - Merge

    /// The point of the confidence rule: the same workout logged by hand is
    /// enriched, not duplicated. Two sessions for one workout would double the
    /// day's training load.
    func testIdenticalLoggedSessionIsClaimedRatherThanDuplicated() async throws {
        let (db, provider, bridge) = try fixture()
        try db.run("""
        INSERT INTO workoutSession (date, startTimestamp, endTimestamp, durationMinutes, createdAt, updatedAt)
        VALUES ('2026-02-11', '2026-02-11T07:00:10Z', '2026-02-11T07:45:10Z', 45,
                '2026-02-11T08:00:00Z', '2026-02-11T08:00:00Z');
        """)

        try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z"),
        ])

        let rows = try db.query("SELECT healthKitUUID, source FROM workoutSession;")
        XCTAssertEqual(rows.count, 1, "one workout must never become two sessions")
        XCTAssertEqual(rows.first?.string("healthKitUUID"), "hk-1")
        // `source` stays NULL: it records who *created* the row, and the user
        // created this one. Claiming a link is not claiming authorship — which
        // is what lets a withdrawn workout release the link without deleting
        // somebody's own log.
        XCTAssertNil(rows.first?.string("source"))
    }

    /// The swallow guard, end to end: a 45-minute run inside an 8-hour logged
    /// session is its own workout and gets its own session.
    func testWorkoutInsideALongSessionStillGetsItsOwnSession() async throws {
        let (db, provider, bridge) = try fixture()
        try db.run("""
        INSERT INTO workoutSession (date, startTimestamp, endTimestamp, durationMinutes, createdAt, updatedAt)
        VALUES ('2026-02-11', '2026-02-11T00:00:00Z', '2026-02-11T08:00:00Z', 480,
                '2026-02-11T09:00:00Z', '2026-02-11T09:00:00Z');
        """)

        try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z"),
        ])

        let all = try db.query("SELECT healthKitUUID, durationMinutes FROM workoutSession ORDER BY id;")
        XCTAssertEqual(all.count, 2, "the run must not be absorbed by the day's session")
        XCTAssertNil(all.first?.string("healthKitUUID"), "the manual session stays the user's own")
        XCTAssertEqual(all.last?.string("healthKitUUID"), "hk-1")
    }

    /// Re-syncing the same workout must not add a second session.
    func testResyncIsIdempotent() async throws {
        let (db, provider, bridge) = try fixture()
        let sample = workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z")
        let service = try await sync(bridge, provider, db, added: [sample], anchor: [1])
        XCTAssertEqual(try service.currentAnchor(), [1])

        provider.enqueue(HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: [2]),
                         for: .workouts)
        try await service.syncOnce()

        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM workoutSession;").first?.int("n"), 1)
        XCTAssertEqual(try service.currentAnchor(), [2])
    }

    // MARK: - Withdrawal

    /// A session Almanac created from a withdrawn workout is withdrawn with it —
    /// soft-deleted, so a bout ever logged against it still resolves.
    func testWithdrawnWorkoutSoftDeletesTheSessionItCreated() async throws {
        let (db, provider, bridge) = try fixture()
        let service = try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z"),
        ], anchor: [1])

        provider.enqueue(HealthChangeSet(added: [], deletedExternalIDs: ["hk-1"], nextAnchor: [2]),
                         for: .workouts)
        try await service.syncOnce()

        let row = try XCTUnwrap(db.query("SELECT deletedAt FROM workoutSession;").first)
        XCTAssertNotNil(row.string("deletedAt"))
        XCTAssertTrue(try sessions(db).isEmpty, "a withdrawn workout leaves no live session")
    }

    /// But a session the *user* logged is their record, not HealthKit's. A
    /// withdrawn watch workout releases the claim and leaves their log alone —
    /// deleting it would erase something Almanac never owned.
    func testWithdrawnWorkoutNeverDeletesTheUsersOwnSession() async throws {
        let (db, provider, bridge) = try fixture()
        try db.run("""
        INSERT INTO workoutSession (date, startTimestamp, endTimestamp, durationMinutes, createdAt, updatedAt)
        VALUES ('2026-02-11', '2026-02-11T07:00:10Z', '2026-02-11T07:45:10Z', 45,
                '2026-02-11T08:00:00Z', '2026-02-11T08:00:00Z');
        """)
        let service = try await sync(bridge, provider, db, added: [
            workout("hk-1", "2026-02-11T07:00:00Z", "2026-02-11T07:45:00Z"),
        ], anchor: [1])
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM workoutSession WHERE healthKitUUID = 'hk-1';").first?.int("n"), 1)

        provider.enqueue(HealthChangeSet(added: [], deletedExternalIDs: ["hk-1"], nextAnchor: [2]),
                         for: .workouts)
        try await service.syncOnce()

        let row = try XCTUnwrap(db.query("SELECT deletedAt, healthKitUUID, source FROM workoutSession;").first)
        XCTAssertNil(row.string("deletedAt"), "the user's own log must survive")
        XCTAssertNil(row.string("healthKitUUID"), "the claim is released")
        XCTAssertNil(row.string("source"), "and it never claimed to be HealthKit's")
    }
}
