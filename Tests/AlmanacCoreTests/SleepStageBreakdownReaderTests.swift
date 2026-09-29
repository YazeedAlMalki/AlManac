import XCTest
@testable import AlmanacCore

/// §9.2's Sleep Quality Score has been permanently neutral.
///
/// `ReadinessFormula.sleepQualityScore(nil)` returns 50, and nothing in the app
/// ever set `ReadinessInputs.stages` — `ReadinessModel.refresh()` built the
/// struct without the field. Twenty percent of every readiness score has
/// therefore been a constant, arrived at by accident and presented to the user
/// with the same confidence as the 80% that was measured. The stage samples
/// themselves were never missing: `health_sample` holds them, the classifier
/// consumed them, and the one query that read them was `private` to
/// `SleepEpisodeHealthBridge`.
///
/// These tests pin the read path that closes that gap, and pin the arithmetic
/// decisions §9.2 leaves open, because each of them is a way to turn "no data"
/// into a confident-looking number.
final class SleepStageBreakdownReaderTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    // MARK: - Fixture

    private func fixture() throws -> (Database, HealthSampleStore, SleepEpisodeStore, SleepStageBreakdownReader) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        return (db,
                HealthSampleStore(db: db, healthDomain: .sleep, clock: clock, zone: ZoneContext(utc)),
                SleepEpisodeStore(db: db, clock: clock),
                SleepStageBreakdownReader(db: db))
    }

    /// A stage sample as `HealthKitProvider` encodes one: the stage's raw value
    /// travels in `unit`, because a category sample has no quantity to read.
    private func stage(_ id: String, _ stage: SleepStage,
                       _ from: String, _ to: String) -> HealthSample {
        let iso = ISO8601DateFormatter()
        return HealthSample(externalID: id, domain: .sleep,
                            start: iso.date(from: from)!, end: iso.date(from: to)!,
                            value: nil, unit: stage.rawValue, sourceName: "Apple Watch")
    }

    private func write(_ samples: [HealthSample], to store: HealthSampleStore, in db: Database) throws {
        try store.apply(HealthChangeSet(added: samples, deletedExternalIDs: [], nextAnchor: [1]), in: db)
    }

    /// A primary episode covering `from...to`, on the day it wakes.
    private func episode(_ store: SleepEpisodeStore, day: String,
                         _ from: String, _ to: String, firstUUID: String) throws -> StoredSleepEpisode {
        let iso = ISO8601DateFormatter()
        try store.upsert(
            SleepEpisode(start: iso.date(from: from)!, end: iso.date(from: to)!,
                         type: .primary, source: .healthkit, asleepMinutes: 0,
                         healthKitUUIDs: [firstUUID]),
            timezoneOffset: 0, logicalDay: day)
        return try XCTUnwrap(try store.episodes(for: day).first)
    }

    // MARK: - The read path itself

    /// The tracer bullet: a night's stage samples become the §9.2 split.
    func testNightOfStagesBecomesABreakdown() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z"),
            stage("s2", .awake,      "2026-02-11T01:00:00Z", "2026-02-11T01:30:00Z"),
            stage("s3", .asleepDeep, "2026-02-11T01:30:00Z", "2026-02-11T05:00:00Z"),
            stage("s4", .asleepREM,  "2026-02-11T05:00:00Z", "2026-02-11T07:00:00Z"),
        ], to: samples, in: db)

        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z", firstUUID: "s1")
        let breakdown = try XCTUnwrap(try reader.breakdown(forEpisode: night))

        // Of an eight-hour span: 3h30 deep, 2h REM, 2h core, 30m awake. The
        // awake half-hour is in the denominator and not the numerator, so the
        // three fractions sum to less than one rather than to one.
        XCTAssertEqual(breakdown.deep, 210.0 / 480.0, accuracy: 0.0001)
        XCTAssertEqual(breakdown.rem, 120.0 / 480.0, accuracy: 0.0001)
        XCTAssertEqual(breakdown.core, 120.0 / 480.0, accuracy: 0.0001)
        XCTAssertLessThan(breakdown.deep + breakdown.rem + breakdown.core, 1.0)
    }

    /// `inBed` is bed occupancy, not sleep. Devices that emit it alongside the
    /// asleep stages would otherwise have every fraction counted twice.
    func testInBedIsNotCountedAsSleep() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z"),
            stage("s2", .asleepDeep, "2026-02-11T01:00:00Z", "2026-02-11T03:00:00Z"),
            stage("bed", .inBed,    "2026-02-10T22:30:00Z", "2026-02-11T07:30:00Z"),
        ], to: samples, in: db)

        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-10T23:00:00Z", "2026-02-11T03:00:00Z", firstUUID: "s1")
        let breakdown = try XCTUnwrap(try reader.breakdown(forEpisode: night))

        // 4h span, all of it asleep: the inBed sample spanning 9h changed nothing.
        XCTAssertEqual(breakdown.core, 0.5, accuracy: 0.0001)
        XCTAssertEqual(breakdown.deep, 0.5, accuracy: 0.0001)
        XCTAssertEqual(breakdown.rem, 0.0, accuracy: 0.0001)
    }

    /// Awake time is the denominator, so the same two hours of deep sleep
    /// occupies a smaller share of a fragmented night. This is the distinction
    /// §9.2's percentages have to make, and it is invisible if awake time were
    /// excluded from both the numerator and the denominator.
    func testDeepShareFallsAsTheNightGetsLonger() throws {
        let (db, samples, episodes, reader) = try fixture()

        // Night A: two hours, all of it deep.
        try write([
            stage("a1", .asleepDeep, "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z"),
        ], to: samples, in: db)
        // Night B: the same two hours of deep, then two of core, then two hours
        // awake — six hours in, of which two are deep.
        try write([
            stage("b1", .asleepDeep, "2026-02-11T23:00:00Z", "2026-02-12T01:00:00Z"),
            stage("b2", .asleepCore, "2026-02-12T01:00:00Z", "2026-02-12T03:00:00Z"),
            stage("b3", .awake,      "2026-02-12T03:00:00Z", "2026-02-12T05:00:00Z"),
        ], to: samples, in: db)

        let short = try episode(episodes, day: "2026-02-11",
                                "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z", firstUUID: "a1")
        let long = try episode(episodes, day: "2026-02-12",
                               "2026-02-11T23:00:00Z", "2026-02-12T05:00:00Z", firstUUID: "b1")

        let a = try XCTUnwrap(try reader.breakdown(forEpisode: short))
        let b = try XCTUnwrap(try reader.breakdown(forEpisode: long))

        XCTAssertEqual(a.deep, 1.0, accuracy: 0.0001)
        XCTAssertEqual(b.deep, 2.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(b.core, 2.0 / 6.0, accuracy: 0.0001)
        // Same two hours of deep sleep either way, but it is a quarter of night
        // B and all of night A — so night B scores worse on §9.2's formula.
        XCTAssertLessThan(b.deep, a.deep)
        XCTAssertLessThan(ReadinessFormula.sleepQualityScore(b),
                          ReadinessFormula.sleepQualityScore(a))
    }

    // MARK: - "No data" must stay "no data"

    /// An episode with no stage samples is missing input, not a night of zero
    /// quality. §9.2's answer for this is 50, flagged as missing — a breakdown
    /// of three zeros would score 0 and tell the user they slept terribly on a
    /// night the app never observed.
    func testNoStageSamplesYieldsNilNotZero() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z"),
        ], to: samples, in: db)

        // A different day: a manual entry, which carries no HealthKit samples.
        let manual = try episode(episodes, day: "2026-02-12",
                                 "2026-02-11T23:00:00Z", "2026-02-12T07:00:00Z", firstUUID: "manual-1")
        XCTAssertNil(try reader.breakdown(forEpisode: manual))

        // And the consequence §9.2 prescribes for that nil.
        XCTAssertEqual(ReadinessFormula.sleepQualityScore(nil), 50)
    }

    /// A night whose only samples are `inBed`/`awake` is the same case: the
    /// device was watching, the user was not asleep.
    func testOnlyInBedAndAwakeYieldsNil() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("bed", .inBed, "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z"),
        ], to: samples, in: db)

        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z", firstUUID: "bed")
        XCTAssertNil(try reader.breakdown(forEpisode: night))
    }

    /// A withdrawn sample stops counting. HealthKit deletes sleep stages
    /// routinely — a re-synced night, a corrected stage — and the score must
    /// follow the correction rather than the first import.
    func testWithdrawnSampleStopsCounting() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("s1", .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z"),
            stage("s2", .asleepDeep, "2026-02-11T01:00:00Z", "2026-02-11T03:00:00Z"),
        ], to: samples, in: db)
        try samples.apply(HealthChangeSet(added: [], deletedExternalIDs: ["s2"], nextAnchor: [2]), in: db)

        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-10T23:00:00Z", "2026-02-11T03:00:00Z", firstUUID: "s1")
        let breakdown = try XCTUnwrap(try reader.breakdown(forEpisode: night))
        XCTAssertEqual(breakdown.deep, 0.0, accuracy: 0.0001)
        XCTAssertEqual(breakdown.core, 0.5, accuracy: 0.0001)
    }

    /// Only the episode's own window is read. The night before and the nap
    /// after must not leak into it.
    func testSamplesOutsideTheWindowAreIgnored() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("prev", .asleepDeep, "2026-02-09T23:00:00Z", "2026-02-10T07:00:00Z"),
            stage("s1",   .asleepCore, "2026-02-10T23:00:00Z", "2026-02-11T01:00:00Z"),
            stage("s2",   .asleepCore, "2026-02-11T01:00:00Z", "2026-02-11T03:00:00Z"),
            stage("nap",  .asleepDeep, "2026-02-11T13:00:00Z", "2026-02-11T14:00:00Z"),
        ], to: samples, in: db)

        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-10T23:00:00Z", "2026-02-11T03:00:00Z", firstUUID: "s1")
        let breakdown = try XCTUnwrap(try reader.breakdown(forEpisode: night))
        XCTAssertEqual(breakdown.core, 1.0, accuracy: 0.0001)
        XCTAssertEqual(breakdown.deep, 0.0, accuracy: 0.0001)
    }

    /// Fractions are of the episode, so a sample overhanging the window is
    /// clipped rather than allowed to push one past 1.0.
    func testOverhangingSampleIsClippedToTheWindow() throws {
        let (db, samples, episodes, reader) = try fixture()
        try write([
            stage("s1", .asleepDeep, "2026-02-10T22:00:00Z", "2026-02-11T09:00:00Z"),
        ], to: samples, in: db)

        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-11T01:00:00Z", "2026-02-11T03:00:00Z", firstUUID: "s1")
        let breakdown = try XCTUnwrap(try reader.breakdown(forEpisode: night))
        XCTAssertEqual(breakdown.deep, 1.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(breakdown.deep, 1.0)
    }

    /// A zero-length episode cannot be a fraction of anything.
    func testZeroLengthEpisodeYieldsNil() throws {
        let (db, _, episodes, reader) = try fixture()
        let night = try episode(episodes, day: "2026-02-11",
                                "2026-02-11T01:00:00Z", "2026-02-11T01:00:00Z", firstUUID: "z1")
        XCTAssertNil(try reader.breakdown(forEpisode: night))
    }

    // MARK: - The reason any of this matters

    /// The end-to-end claim: with the read path in place, a night of real
    /// stages stops being a constant 50 and starts moving the score. Before
    /// this existed the sleep-quality input was 20% of every readiness score
    /// and always exactly neutral.
    func testStagesChangeTheReadinessScore() async throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let bridge = SleepEpisodeHealthBridge(db: db, clock: clock,
                                               timeModel: TimeModel(timeZone: utc),
                                               zone: ZoneContext(utc))
        let provider = FakeHealthProvider()
        let iso = ISO8601DateFormatter()
        func sample(_ id: String, _ s: SleepStage, _ a: String, _ b: String) -> HealthSample {
            HealthSample(externalID: id, domain: .sleep,
                         start: iso.date(from: a)!, end: iso.date(from: b)!,
                         value: nil, unit: s.rawValue, sourceName: "Apple Watch")
        }
        try await provider.requestAuthorisation(for: [.sleep])
        provider.enqueue(HealthChangeSet(added: [
            sample("s1", .asleepDeep, "2026-02-11T01:00:00Z", "2026-02-11T05:00:00Z"),
            sample("s2", .asleepCore, "2026-02-11T05:00:00Z", "2026-02-11T07:00:00Z"),
        ], deletedExternalIDs: [], nextAnchor: [1]), for: .sleep)
        _ = try await HealthSyncService(db: db, provider: provider, writer: bridge,
                                        healthDomain: .sleep).syncOnce()

        let night = try XCTUnwrap(try SleepEpisodeStore(db: db).episodes(for: "2026-02-11").first)
        let stages = try SleepStageBreakdownReader(db: db).breakdown(forEpisode: night)

        let baseline = ReadinessBaseline(context: .general, restingHeartRate: 52, hrv: 60, validDayCount: 40)
        func score(_ stages: SleepStageBreakdown?) -> ReadinessOutcome {
            ReadinessEngine.evaluate(state: .provisional,
                                     inputs: ReadinessInputs(sleepDurationMinutes: 480,
                                                             stages: stages,
                                                             restingHeartRate: 48, hrv: 70),
                                     baseline: baseline)
        }

        // The gap this closes: with real stages the input is no longer missing,
        // and the score reflects deep+REM rather than a constant.
        let withStages = score(stages)
        XCTAssertNotNil(stages)
        XCTAssertFalse(withStages.missingInputs.contains(.sleepQuality))
        XCTAssertNotEqual(withStages.score, score(nil).score)
        // 4h deep / 6h span = 0.667, no REM: (0.667 × 1.4) × 100 = 93.3, which
        // beats the neutral 50 the same night used to score.
        XCTAssertGreaterThan(try XCTUnwrap(withStages.score), score(nil).score ?? 0)
    }
}
