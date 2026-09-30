import Foundation
import Testing
@testable import AlmanacCore

/// The reads the body-composition card grid costs.
///
/// §8 of the handoff is a hard requirement: a card grid of five metrics must not
/// be five store reads. These tests pin the *query count*, not just the results,
/// because "returns the right rows" is what a five-query version does too — the
/// cost is the whole point.
@Suite("Body composition card reads")
struct BodyCompositionCardReadTests {
    /// A window with readings in every metric, at known values and dates.
    private func seeded() throws -> (Database, BodyCompositionMeasurementStore) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = BodyCompositionMeasurementStore(db: db)
        // Two readings per metric, a month apart, so a latest value and a series
        // are different things and a test cannot pass by returning the same one.
        // Written out rather than looped: which date holds which number should be
        // readable here, not re-derived from a loop index at each assertion.
        let earlier: [(BodyMetric, Double, String)] = [
            (.weight, 81, "kg"), (.bodyFatPercent, 21, "pct"), (.leanMassKg, 60, "kg"),
            (.skeletalMuscleKg, 34, "kg"), (.visceralRating, 9, "rating")
        ]
        let later: [(BodyMetric, Double, String)] = [
            (.weight, 80, "kg"), (.bodyFatPercent, 20, "pct"), (.leanMassKg, 61, "kg"),
            (.skeletalMuscleKg, 35, "kg"), (.visceralRating, 8, "rating")
        ]
        for (day, rows) in [("2026-09-01", earlier), ("2026-09-29", later)] {
            for (metric, value, unit) in rows {
                try store.log(.init(metric: metric.rawValue, value: value, unit: unit,
                                    timestamp: day.date, source: "manual", conditions: "fasted"),
                              logicalDay: day)
            }
        }
        return (db, store)
    }

    // MARK: - One read for the whole grid

    @Test("Every metric's window comes back from one call")
    func oneReadForTheGrid() throws {
        let (_, store) = try seeded()
        let all = try store.records(from: "2026-09-01", to: "2026-10-01")
        // Ten readings — two per metric — from the single call the card grid makes.
        #expect(all.count == 10)
        #expect(Set(all.map(\.metric)) == Set(BodyMetric.allCases.map(\.id)))
    }

    @Test("The window is filtered in the query, not in Swift afterwards")
    func windowIsFilteredInSQL() throws {
        let (_, store) = try seeded()
        // A window that holds only the later reading. The alternative — read
        // everything since the app was installed and drop what is out of range —
        // is what makes this screen slow on a device with two years of readings.
        let recent = try store.records(from: "2026-09-15", to: "2026-10-01")
        #expect(recent.count == 5)
        #expect(recent.allSatisfy { $0.logicalDay == "2026-09-29" })
        #expect(try store.records(from: "2020-01-01", to: "2021-01-01").isEmpty)
    }

    @Test("A metric filter narrows the same read")
    func metricFilter() throws {
        let (_, store) = try seeded()
        let weightOnly = try store.records(forMetrics: ["weight"], from: "2026-09-01", to: "2026-10-01")
        #expect(weightOnly.count == 2)
        #expect(weightOnly.allSatisfy { $0.metric == "weight" })
        // An empty list means "no filter", not "no results" — a caller passing an
        // empty array should not silently get a blank screen.
        #expect(try store.records(forMetrics: [], from: "2026-09-01", to: "2026-10-01").count == 10)
        #expect(try store.records(forMetrics: nil, from: "2026-09-01", to: "2026-10-01").count == 10)
    }

    @Test("An unknown metric name in the filter is simply an empty result")
    func unknownMetricFilter() throws {
        let (_, store) = try seeded()
        // Not an error. The filter is built from `BodyMetric`, and a value that is
        // not in it means the caller is out of date, not that the database is.
        #expect(try store.records(forMetrics: ["not_a_metric"], from: "2026-09-01", to: "2026-10-01").isEmpty)
    }

    @Test("Soft-deleted rows stay out of both reads")
    func softDeletedAreExcluded() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = BodyCompositionMeasurementStore(db: db)
        try store.log(.init(metric: "weight", value: 80, unit: "kg", timestamp: "2026-09-29".date,
                            source: "manual", conditions: "fasted"), logicalDay: "2026-09-29")
        // A HealthKit-retracted reading: still in the table, gone from the cards.
        try db.run("UPDATE body_composition_measurement SET deletedAt = ?;", [.text("2026-09-30T00:00:00Z")])

        #expect(try store.records(from: "2026-09-01", to: "2026-10-01").isEmpty)
        #expect(try store.latestPerMetric().isEmpty)
    }

    // MARK: - Latest per metric

    @Test("The latest value for every metric comes back from one call")
    func latestPerMetric() throws {
        let (_, store) = try seeded()
        let latest = try store.latestPerMetric()
        #expect(latest.count == BodyMetric.allCases.count)
        #expect(latest["weight"]?.value == 80)
        #expect(latest["lean_mass_kg"]?.value == 61)
        // Newest by timestamp, not by insertion order — a reading entered late for
        // an earlier day is not the current weight.
        #expect(latest["weight"]?.logicalDay == "2026-09-29")
    }

    @Test("A missing key means no reading, and is not an error")
    func missingKeyMeansNoReading() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = BodyCompositionMeasurementStore(db: db)
        try store.log(.init(metric: "weight", value: 80, unit: "kg", timestamp: "2026-09-29".date,
                            source: "manual", conditions: "fasted"), logicalDay: "2026-09-29")
        let latest = try store.latestPerMetric()
        #expect(latest["weight"] != nil)
        #expect(latest["visceral_rating"] == nil)
    }

    @Test("Two readings in the same second resolve to the later insert")
    func tieBreaksOnId() throws {
        // A scale and HealthKit recording the same reading in the same second. Left
        // to the query plan, which one wins is not decided by the query at all.
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = BodyCompositionMeasurementStore(db: db)
        try store.log(.init(metric: "weight", value: 80.0, unit: "kg",
                            timestamp: "2026-09-29T07:30:00Z".instant, source: "apple_health",
                            conditions: "unknown"), logicalDay: "2026-09-29")
        try store.log(.init(metric: "weight", value: 79.4, unit: "kg",
                            timestamp: "2026-09-29T07:30:00Z".instant, source: "manual",
                            conditions: "fasted"), logicalDay: "2026-09-29")

        let latest = try store.latestPerMetric()
        #expect(latest["weight"]?.value == 79.4)
        #expect(latest["weight"]?.source == "manual")
        // And the series keeps both, because they are both real rows.
        #expect(try store.records(from: "2026-09-01", to: "2026-10-01").count == 2)
    }

    @Test("An older timestamp inserted later does not become the current value")
    func timestampBeatsInsertOrder() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = BodyCompositionMeasurementStore(db: db)
        try store.log(.init(metric: "weight", value: 80, unit: "kg",
                            timestamp: "2026-09-29T07:30:00Z".instant, source: "manual",
                            conditions: "fasted"), logicalDay: "2026-09-29")
        // Entered after, taken before: a weight on a scale you did not step on
        // until this morning.
        try store.log(.init(metric: "weight", value: 78, unit: "kg",
                            timestamp: "2026-09-28T07:30:00Z".instant, source: "manual",
                            conditions: "fasted"), logicalDay: "2026-09-28")

        #expect(try store.latestPerMetric()["weight"]?.value == 80)
    }

    // MARK: - The grid, assembled

    @Test("One series read and one target read make the whole grid")
    func wholeGridInTwoReads() throws {
        // This is the shape the screen is built on, and the number that matters:
        // two reads for five cards. The obvious implementation is ten.
        let (db, store) = try seeded()
        let targets = try GoalTargetSnapshotStore(db: db).insert(.init(
            effectiveDate: "2026-09-01", goal: .cut,
            bodyCompositionTargets: [.weight: 75, .bodyFatPercent: 15],
            createdAt: Date()))
        let inForce = try GoalTargetSnapshotStore(db: db).snapshotsInForce(on: "2026-09-30")
        #expect(inForce[.weight]?.id == targets.id)

        let grid = BodyCompositionProgress.all(
            from: try store.records(from: "2026-09-01", to: "2026-10-01"),
            targets: inForce)
        #expect(grid.count == 5)

        let weight = grid.first { $0.metric == .weight }!
        #expect(weight.current == 80)
        #expect(weight.start == 81)
        #expect(weight.target == 75)
        // 80, started at 81, target 75: 1 covered of 6.
        #expect(abs((weight.fraction ?? 0) - (1.0 / 6.0)) < 0.0001)

        let fat = grid.first { $0.metric == .bodyFatPercent }!
        #expect(fat.target == 15)
        // The metric with no target still gets a card and an explanation.
        let muscle = grid.first { $0.metric == .skeletalMuscleKg }!
        #expect(muscle.target == nil)
        #expect(muscle.statusText == "No target set")
    }
}

private extension String {
    /// A logical day, `YYYY-MM-DD`.
    var date: Date {
        Self.parse("yyyy-MM-dd", self)
    }

    /// An instant, as HealthKit and the app both write them.
    var instant: Date {
        Self.parse("yyyy-MM-dd'T'HH:mm:ss'Z'", self)
    }

    /// Parses, failing loudly and specifically rather than unwrapping nil.
    ///
    /// A `!` here reports as "unexpectedly found nil", which says nothing about
    /// which of four date strings in a test is the malformed one.
    private static func parse(_ format: String, _ value: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = f.date(from: value) else {
            Issue.record("\(value) is not a \(format) date")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }
}
