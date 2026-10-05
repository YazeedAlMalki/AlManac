import Testing
import Foundation
@testable import AlmanacCore

/// The launch-argument seeding hook — the mechanism a UI test uses to put a
/// reading on a logical day of its choosing.
///
/// The reason the hook exists is in `VitalsSeedPlan`: the editor's "Measured at"
/// picker is a compact `DatePicker` that expands a *graphical* calendar, whose
/// day cells are locale-formatted buttons, and CI resolves the newest runtime
/// rather than pinning one. These tests are therefore not about vitals — they
/// are about the one property that makes app code existing only for tests
/// defensible, which is that it cannot run without being asked for.
@Suite("Vitals Seed Plan")
struct VitalsSeedPlanTests {
    private let zone = TimeZone(identifier: "Europe/London")!
    private var timeModel: TimeModel { TimeModel(timeZone: zone, boundary: .almanac) }
    private var store: VitalsRecordStore {
        VitalsRecordStore(db: db, zone: ZoneContext(zone), timeModel: timeModel)
    }
    private let db = try! TestDatabase()

    /// 2026-10-05 09:00 London.
    private func morningOnFifthOctober() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 5; c.hour = 9
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: c)!
    }

    // MARK: - The guard

    @Test("A launch with no seeding argument asks for nothing")
    func absentArgumentYieldsNoPlan() {
        // The property the whole arrangement rests on. Every other launch a
        // person or a reviewer makes looks like this one.
        #expect(VitalsSeedPlan.fromLaunchArguments([]) == nil)
        #expect(VitalsSeedPlan.fromLaunchArguments(["Almanac"]) == nil)
        #expect(VitalsSeedPlan.fromLaunchArguments(["-AppleLanguages", "(en)"]) == nil)
        // Present but with nothing after it is also nothing, not a crash.
        #expect(VitalsSeedPlan.fromLaunchArguments(["-AlmanacSeedVitals"]) == nil)
    }

    @Test("A malformed spec plants nothing rather than planting part of it")
    func malformedSpecIsRejectedWhole() {
        for spec in ["", "   ", "rhr", "rhr=52", "rhr=52@", "@-1", "rhr=@−1",
                     "steps=4000@-1", "rhr=nan@-1", "rhr=-5@-1", "rhr=52@x",
                     "rhr=52@-1,hrv=55@nope", "rhr=52@-1=", "rhr==52@-1"] {
            #expect(VitalsSeedPlan(spec: spec) == nil,
                    "expected \"\(spec)\" to be rejected outright")
        }
    }

    @Test("An entry with no value is a clear, not a plant")
    func bareEntryIsAClear() throws {
        let plan = try #require(VitalsSeedPlan(spec: "rhr@0,hrv=55@-1"))
        #expect(plan.readings == [
            VitalsSeedReading(metric: .restingHeartRate, value: nil, dayOffset: 0),
            VitalsSeedReading(metric: .heartRateVariability, value: 55, dayOffset: -1),
        ])
    }

    @Test("A good spec parses into the readings it names")
    func specParses() throws {
        let plan = try #require(VitalsSeedPlan(spec: "rhr=52@-1,hrv=55@-2"))
        #expect(plan.readings == [
            VitalsSeedReading(metric: .restingHeartRate, value: 52, dayOffset: -1),
            VitalsSeedReading(metric: .heartRateVariability, value: 55, dayOffset: -2),
        ])
    }

    // MARK: - Clearing a day

    @Test("A clear empties a day the log cannot show")
    func clearRemovesTodaysReadings() throws {
        let now = morningOnFifthOctober()
        // Stand in for an earlier run that already typed a pair today: the
        // seeder plants two more, then asks for today to be emptied.
        let today = timeModel.start(of: LogicalDay("2026-10-05"))!
        try store.recordManual(metric: .restingHeartRate, value: 51, measuredAt: today)
        try store.recordManual(metric: .restingHeartRate, value: 64, measuredAt: today)
        try #require(VitalsSeedPlan(spec: "rhr@0")).apply(into: store, now: now, timeModel: timeModel)
        #expect(try store.records(for: "2026-10-05").isEmpty)

        // And today's bounded read sees nothing, which is what makes the Vitals
        // "today" card read as absent.
        #expect(try store.latestValue(for: VitalsMetric.restingHeartRate, since: today) == nil)
    }

    @Test("A clear touches one metric on one day, and writes nothing")
    func clearIsScoped() throws {
        let now = morningOnFifthOctober()
        let today = timeModel.start(of: LogicalDay("2026-10-05"))!
        try store.recordManual(metric: .restingHeartRate, value: 51, measuredAt: today)
        try store.recordManual(metric: .heartRateVariability, value: 53, measuredAt: today)
        try #require(VitalsSeedPlan(spec: "rhr=52@-1,hrv=55@-1")).apply(
            into: store, now: now, timeModel: timeModel)

        // Clearing today's resting rate must leave today's HRV alone, or a test
        // that asked for one would silently lose the other.
        let written = try #require(VitalsSeedPlan(spec: "rhr@0")).apply(
            into: store, now: now, timeModel: timeModel)
        #expect(written == 0)
        #expect(try store.records(for: "2026-10-05").map(\.metric) == ["hrv"])
        #expect(try store.records(for: "2026-10-04").count == 2)
    }

    // MARK: - Which day a reading lands on

    @Test("Offsets count the repo's 04:00 boundary days, not calendar midnights")
    func offsetsResolveAgainstTheBoundary() {
        let plan = VitalsSeedPlan(readings: [])
        let now = morningOnFifthOctober()
        // 09:00 on the 5th is after the boundary, so today is the 5th.
        #expect(plan.logicalDay(for: 0, now: now, timeModel: timeModel)?.value == "2026-10-05")
        #expect(plan.logicalDay(for: -1, now: now, timeModel: timeModel)?.value == "2026-10-04")
        #expect(plan.logicalDay(for: -3, now: now, timeModel: timeModel)?.value == "2026-10-02")
        #expect(plan.logicalDay(for: 1, now: now, timeModel: timeModel)?.value == "2026-10-06")
    }

    @Test("A reading named for another day is stored against that day, not today")
    func applyPlacesReadingsOnTheNamedDays() throws {
        let plan = try #require(VitalsSeedPlan(spec: "rhr=52@-1,hrv=55@-1"))
        let written = try plan.apply(into: store, now: morningOnFifthOctober(),
                                     timeModel: timeModel)
        #expect(written == 2)

        let onFourth = try store.records(for: "2026-10-04")
        #expect(onFourth.count == 2)
        #expect(onFourth.map(\.metric).sorted() == ["hrv", "rhr"])
        // 09:00 on the named day, so §7.1 puts it in that day rather than the one
        // before — which a seed stamped at, say, 02:00 would not be.
        #expect(onFourth.allSatisfy { timeModel.logicalDay($0.timestamp).value == "2026-10-04" })

        // And nothing landed on today, which is the whole difference from a hand
        // -typed reading.
        #expect(try store.records(for: "2026-10-05").isEmpty)
    }

    @Test("A seeded reading is a real reading: manual source, today's read, same row as a typed one")
    func applyWritesThroughTheStore() throws {
        try #require(VitalsSeedPlan(spec: "rhr=52@-1")).apply(
            into: store, now: morningOnFifthOctober(), timeModel: timeModel)
        let record = try #require(try store.records(for: "2026-10-04").first)
        #expect(record.source == VitalsRecordStore.manualSource)
        #expect(record.unit == "bpm")
        // The unbounded archive read finds it — it is a real row.
        #expect(try store.latestValue(for: "rhr")?.id == record.id)
        // Today's bounded read must not see it — the property `latestValue(for:since:)`
        // exists for.
        let todayStart = timeModel.start(of: LogicalDay("2026-10-05"))!
        #expect(try store.latestValue(for: VitalsMetric.restingHeartRate, since: todayStart) == nil)
    }

    // MARK: - Re-applying

    @Test("Re-applying the same plan replaces rather than accumulates")
    func applyIsRepeatable() throws {
        let plan = try #require(VitalsSeedPlan(spec: "rhr=52@-1,hrv=55@-1"))
        let now = morningOnFifthOctober()
        try plan.apply(into: store, now: now, timeModel: timeModel)
        try plan.apply(into: store, now: now, timeModel: timeModel)
        try plan.apply(into: store, now: now, timeModel: timeModel)
        // The simulator's database is shared and never reset, and every test
        // relaunches the app, so a seeder that appended would quietly triple the
        // baseline's within-day readings and fill the 40-row log window.
        #expect(try store.records(for: "2026-10-04").count == 2)

        // And a later plan with different values wins, rather than both being
        // true at once.
        try #require(VitalsSeedPlan(spec: "rhr=48@-1")).apply(into: store, now: now, timeModel: timeModel)
        let fourth = try store.records(metric: "rhr", logicalDays: ["2026-10-04"])
        #expect(fourth.map(\.value) == [48])
    }

    @Test("A seeded day is a valid day, and re-seeding it does not move the baseline")
    func seededDaysMakeAValidDayAndRepeatedSeedingDoesNotMoveTheMean() throws {
        // Both metrics, because §9.7 makes a day valid on sleep data *or* an RHR
        // and an HRV together — one metric alone is not a valid day and would
        // never reach the window at all.
        let plan = try #require(VitalsSeedPlan(spec: "rhr=52@-1,hrv=55@-1"))
        let now = morningOnFifthOctober()
        for _ in 0..<3 { try plan.apply(into: store, now: now, timeModel: timeModel) }

        // This is what `ReadinessBaselineService.meanPerDay` averages, and the
        // reason replacing beats appending: a day with three copies of 52 and a
        // day with one both mean 52, so the baseline is stable either way — but
        // only if the copies do not accumulate across a whole session's relaunches.
        let resolution = try ReadinessBaselineService(db: db, timeModel: timeModel)
            .resolve(for: LogicalDay("2026-10-05"))
        #expect(resolution.validDayCount == 1)
        #expect(resolution.baseline.restingHeartRate == 52)
        #expect(resolution.baseline.hrv == 55)
    }

    @Test("The plausibility check still applies to a seeded value")
    func implausibleSeededValueThrows() {
        // `VitalsSeedPlan(spec:)` cannot express this — it rejects non-positive
        // values — but a plan built directly can, and the store must refuse it
        // rather than planting a row the editor would have rejected.
        let absurd = VitalsSeedPlan(readings: [
            VitalsSeedReading(metric: .restingHeartRate, value: 9000, dayOffset: -1)])
        #expect(throws: VitalsEntryError.unusuallySized) {
            try absurd.apply(into: store, now: morningOnFifthOctober(), timeModel: timeModel)
        }
    }
}