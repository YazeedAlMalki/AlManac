import XCTest
@testable import AlmanacCore

/// Sleep is the one `HealthDomain` with no writer: `health_sample` had no path
/// into `sleep_episode`, so the classifier and the store existed with nothing
/// feeding them. These tests drive it through the real seam — `HealthSyncService`
/// over a `FakeHealthProvider` — and read back through `SleepEpisodeStore`, the
/// same public surface the Today dashboard uses.
final class SleepEpisodeHealthBridgeTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func fixture() throws -> (Database, FakeHealthProvider, SleepEpisodeHealthBridge) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let provider = FakeHealthProvider()
        let bridge = SleepEpisodeHealthBridge(
            db: db, clock: clock,
            timeModel: TimeModel(timeZone: utc), zone: ZoneContext(utc))
        return (db, provider, bridge)
    }

    /// A stage sample as `HealthKitProvider` encodes one: the stage's raw value
    /// travels in `unit`, because a category sample has no quantity to read.
    private func stage(_ id: String, _ stage: SleepStage,
                       _ from: String, _ to: String) -> HealthSample {
        let formatter = ISO8601DateFormatter()
        return HealthSample(externalID: id, domain: .sleep,
                            start: formatter.date(from: from)!,
                            end: formatter.date(from: to)!,
                            value: nil, unit: stage.rawValue, sourceName: "Apple Watch")
    }

    private func sync(_ bridge: SleepEpisodeHealthBridge, _ provider: FakeHealthProvider,
                      _ db: Database, added: [HealthSample], anchor: [UInt8] = [1]) async throws {
        try await provider.requestAuthorisation(for: [.sleep])
        provider.enqueue(HealthChangeSet(added: added, deletedExternalIDs: [], nextAnchor: anchor),
                         for: .sleep)
        _ = try await HealthSyncService(db: db, provider: provider, writer: bridge,
                                        healthDomain: .sleep).syncOnce()
    }

    /// The tracer bullet: a night of HealthKit stages becomes one classified
    /// primary episode, readable the way the dashboard reads it.
    func testNightOfStagesBecomesOnePrimaryEpisode() async throws {
        let (db, provider, bridge) = try fixture()
        try await sync(bridge, provider, db, added: [
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z"),
            stage("s2", .awake,      "2026-02-11T01:00:00Z", "2026-02-11T01:30:00Z"),
            stage("s3", .asleepDeep, "2026-02-11T01:30:00Z", "2026-02-11T05:00:00Z"),
            stage("s4", .asleepREM,  "2026-02-11T05:00:00Z", "2026-02-11T07:00:00Z"),
        ])

        // Woke at 07:00, so the night belongs to the day the 04:00 boundary opens.
        let episodes = try SleepEpisodeStore(db: db).episodes(for: "2026-02-11")
        XCTAssertEqual(episodes.count, 1)
        let night = try XCTUnwrap(episodes.first)
        XCTAssertEqual(night.effectiveType, .primary)
        XCTAssertEqual(night.source, .healthkit)
        // Wall-clock span (8h), not asleep time (7h30) — the awake stage is part
        // of the night but `durationMinutes` is the row's span column.
        XCTAssertEqual(night.durationMinutes, 480)
        XCTAssertEqual(night.sourceApp, "Apple Watch")
    }

    /// Re-syncing the same night must not double it, and the anchor must move
    /// with the rows.
    func testResyncOfSameNightIsIdempotent() async throws {
        let (db, provider, bridge) = try fixture()
        let samples = [stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z")]

        try await sync(bridge, provider, db, added: samples, anchor: [1])
        let service = HealthSyncService(db: db, provider: provider, writer: bridge, healthDomain: .sleep)
        XCTAssertEqual(try service.currentAnchor(), [1])

        provider.enqueue(HealthChangeSet(added: samples, deletedExternalIDs: [], nextAnchor: [2]),
                         for: .sleep)
        try await service.syncOnce()

        XCTAssertEqual(try SleepEpisodeStore(db: db).episodes(for: "2026-02-11").count, 1)
        XCTAssertEqual(try service.currentAnchor(), [2])
    }

    /// A gap longer than the 30-minute merge rule starts a second episode, and
    /// the longer of the two is the night's primary sleep.
    func testShortAfternoonNapIsNotThePrimarySleep() async throws {
        let (db, provider, bridge) = try fixture()
        try await sync(bridge, provider, db, added: [
            // Night: 23:00–07:00.
            stage("n1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z"),
            // Nap, 13:00–13:40 — 24 hours later, so its own episode.
            stage("p1", .asleepCore, "2026-02-11T13:00:00Z", "2026-02-11T13:40:00Z"),
        ])

        let store = SleepEpisodeStore(db: db)
        // The nap wakes on the 11th too, so both land on the same logical day.
        let episodes = try store.episodes(for: "2026-02-11")
        XCTAssertEqual(episodes.count, 2)
        let primary = try XCTUnwrap(episodes.first { $0.effectiveType == .primary })
        XCTAssertEqual(primary.durationMinutes, 480, "the 8h night outranks the 40m nap")
        let nap = try XCTUnwrap(episodes.first { $0.effectiveType == .nap })
        XCTAssertEqual(nap.durationMinutes, 40)
    }

    /// A phone that reports "in bed" around the whole night overlaps the watch's
    /// asleep stages. The real risk is two sources producing two nights, which
    /// would double every sleep total. The span still starts when the user got
    /// into bed — `inBed` bounds the episode the way an awake stage does, and is
    /// excluded from time-asleep rather than from the night.
    func testOverlappingInBedAndAsleepSourcesDescribeOneNight() async throws {
        let (db, provider, bridge) = try fixture()
        try await sync(bridge, provider, db, added: [
            stage("b1", .inBed,      "2026-02-10T22:30:00Z", "2026-02-11T07:30:00Z"),
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z"),
        ])

        let episodes = try SleepEpisodeStore(db: db).episodes(for: "2026-02-11")
        XCTAssertEqual(episodes.count, 1, "overlapping sources describe one night, not two")
        XCTAssertEqual(try XCTUnwrap(episodes.first).durationMinutes, 540)
    }

    /// An episode is identified by its first sample's UUID. When HealthKit
    /// withdraws *that* sample the night is unchanged but its identity is, so
    /// the upsert would otherwise land a second row beside the first — and the
    /// dashboard sums every episode on the day, which would double the night.
    func testWithdrawingTheIdentitySampleDoesNotLeaveTwoNights() async throws {
        let (db, provider, bridge) = try fixture()
        let service = HealthSyncService(db: db, provider: provider, writer: bridge, healthDomain: .sleep)
        try await sync(bridge, provider, db, added: [
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T03:00:00Z"),
            stage("s2", .asleepREM,  "2026-02-11T03:00:00Z", "2026-02-11T07:00:00Z"),
        ])
        XCTAssertEqual(try SleepEpisodeStore(db: db).episodes(for: "2026-02-11").count, 1)

        // The watch corrects the night: the first stage is withdrawn.
        provider.enqueue(HealthChangeSet(added: [], deletedExternalIDs: ["s1"], nextAnchor: [2]),
                         for: .sleep)
        try await service.syncOnce()

        let episodes = try SleepEpisodeStore(db: db).episodes(for: "2026-02-11")
        XCTAssertEqual(episodes.count, 1, "the night must be re-identified, not duplicated")
        XCTAssertEqual(try XCTUnwrap(episodes.first).healthKitUUID, "s2")
        // Re-measured from what is left: 03:00–07:00, not the original 23:00–07:00.
        XCTAssertEqual(try XCTUnwrap(episodes.first).durationMinutes, 240)
    }

    /// A manual wake-time entry has no HealthKit UUID and no sample behind it.
    /// Re-classifying a day must never take it with it.
    func testManualWakeTimeEntrySurvivesReclassification() async throws {
        let (db, provider, bridge) = try fixture()
        let formatter = ISO8601DateFormatter()
        let manual = try SleepEpisodeStore(db: db).upsertManualWake(
            wakeTime: formatter.date(from: "2026-02-11T07:00:00Z")!,
            logicalDay: "2026-02-11", timezoneOffset: 0)

        try await sync(bridge, provider, db, added: [
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z"),
        ])

        let episodes = try SleepEpisodeStore(db: db).episodes(for: "2026-02-11")
        XCTAssertEqual(episodes.count, 2, "the manual marker and the synced night are separate facts")
        XCTAssertNotNil(episodes.first { $0.id == manual && $0.source == .manual })
    }
}
