import XCTest
@testable import AlmanacCore

/// The Health screen reads what the bridges write, so these tests drive the
/// real writers through the real sync seam and then read the summary back. A
/// screen wired to the wrong table or metric would pass a hand-written fixture
/// and show nothing in the app.
final class HealthSummaryStoreTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func fixture() throws -> (Database, FakeHealthProvider) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return (db, FakeHealthProvider())
    }

    private func sync(_ provider: FakeHealthProvider, _ db: Database,
                      _ domain: HealthDomain, _ samples: [HealthSample]) async throws {
        try await provider.requestAuthorisation(for: [domain])
        provider.enqueue(HealthChangeSet(added: samples, deletedExternalIDs: [], nextAnchor: [1]),
                         for: domain)
        _ = try await HealthSyncService(db: db, provider: provider, writer: writer(for: domain, db),
                                        healthDomain: domain).syncOnce()
    }

    private func writer(for domain: HealthDomain, _ db: Database) -> any HealthSampleWriting {
        switch domain {
        case .sleep: SleepEpisodeHealthBridge(db: db, timeModel: TimeModel(timeZone: utc))
        case .bodyMass, .bodyFatPercentage, .leanBodyMass:
            BodyCompositionMeasurementHealthBridge(db: db, zone: ZoneContext(utc))
        default: VitalsRecordHealthBridge(db: db, zone: ZoneContext(utc))
        }
    }

    private func quantity(_ id: String, _ domain: HealthDomain,
                          _ value: Double, _ unit: String, _ at: String) -> HealthSample {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: at)!
        return HealthSample(externalID: id, domain: domain, start: date, end: date,
                            value: value, unit: unit, sourceName: "Apple Watch")
    }

    private func window() -> DateRange {
        DateRange(from: "2026-02-01T00:00:00Z", to: "2026-03-01T00:00:00Z")!
    }

    func testVitalsDomainsReportTheirLatestValueAndCount() async throws {
        let (db, provider) = try fixture()
        try await sync(provider, db, .heartRate, [
            quantity("h1", .heartRate, 64, "bpm", "2026-02-10T07:00:00Z"),
            quantity("h2", .heartRate, 58, "bpm", "2026-02-11T07:00:00Z"),
        ])
        try await sync(provider, db, .steps, [
            quantity("p1", .steps, 4200, "count", "2026-02-11T20:00:00Z"),
        ])

        let summaries = try HealthSummaryStore(db: db).summaries(in: window())
        let heartRate = try XCTUnwrap(summaries.first { $0.domain == .heartRate })
        XCTAssertEqual(heartRate.latestValue, 58, "latest, not first")
        XCTAssertEqual(heartRate.count, 2)
        XCTAssertEqual(heartRate.unit, "bpm")

        let steps = try XCTUnwrap(summaries.first { $0.domain == .steps })
        XCTAssertEqual(steps.latestValue, 4200)
        XCTAssertEqual(steps.count, 1)
    }

    /// Sleep is not a quantity: it is a count of episodes and the latest one's
    /// duration in minutes. Showing "8.0 hours" as a sum would be wrong.
    func testSleepReportsEpisodeCountAndLatestDuration() async throws {
        let (db, provider) = try fixture()
        let formatter = ISO8601DateFormatter()
        func stage(_ id: String, _ from: String, _ to: String) -> HealthSample {
            HealthSample(externalID: id, domain: .sleep,
                         start: formatter.date(from: from)!, end: formatter.date(from: to)!,
                         value: nil, unit: SleepStage.asleepCore.rawValue, sourceName: "Apple Watch")
        }
        try await sync(provider, db, .sleep, [
            stage("s1", "2026-02-10T23:00:00Z", "2026-02-11T07:00:00Z"),
            stage("s2", "2026-02-11T13:00:00Z", "2026-02-11T13:40:00Z"),
        ])

        let sleep = try XCTUnwrap(
            HealthSummaryStore(db: db).summaries(in: window()).first { $0.domain == .sleep })
        XCTAssertEqual(sleep.count, 2, "a night and a nap")
        XCTAssertEqual(sleep.latestValue, 40, "the most recent episode's duration")
        XCTAssertEqual(sleep.unit, "min")
    }

    /// A domain with nothing synced in the window is absent, not zero — a zero
    /// would read as "you did nothing" rather than "we have no data".
    func testDomainsWithoutDataAreOmitted() async throws {
        let (db, provider) = try fixture()
        try await sync(provider, db, .hrv, [
            quantity("v1", .hrv, 52, "ms", "2026-02-11T07:00:00Z"),
        ])

        let summaries = try HealthSummaryStore(db: db).summaries(in: window())
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.domain, .hrv)
    }

    /// A sample outside the window must not count, or a 30-day view would show
    /// the last known value as if it were today's.
    func testSamplesOutsideTheWindowAreExcluded() async throws {
        let (db, provider) = try fixture()
        try await sync(provider, db, .activeEnergy, [
            quantity("e1", .activeEnergy, 500, "kcal", "2026-01-15T12:00:00Z"),
        ])

        XCTAssertTrue(try HealthSummaryStore(db: db).summaries(in: window()).isEmpty)
    }
}
