import Testing
import Foundation
@testable import AlmanacCore

/// The launch-argument hook that gives the Trends chart readiness history.
///
/// Like `VitalsSeedPlanTests`, the first property pinned is that it cannot run
/// without being asked for. The rest pin that it writes what a chart needs —
/// one record per day, scored by the real engine — and that applying it again
/// changes nothing, since a UI test relaunches the app many times over a
/// database that is never reset.
@Suite("Readiness History Seed Plan")
struct ReadinessHistorySeedPlanTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private var timeModel: TimeModel { TimeModel(timeZone: zone, boundary: .almanac) }
    private let db = try! TestDatabase()

    /// 2026-10-09 12:00 Riyadh.
    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 9; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: c)!
    }

    @Test("A launch with no seeding argument asks for nothing")
    func absentArgumentYieldsNoPlan() {
        #expect(ReadinessHistorySeedPlan.fromLaunchArguments([]) == nil)
        #expect(ReadinessHistorySeedPlan.fromLaunchArguments(["-AppleLanguages", "(ar)"]) == nil)
        #expect(ReadinessHistorySeedPlan.fromLaunchArguments(["-AlmanacSeedReadinessHistory"]) == nil)
        #expect(ReadinessHistorySeedPlan.fromLaunchArguments(["-AlmanacSeedReadinessHistory", "14"])?.days == 14)
    }

    @Test("A spec outside one to ninety days is refused")
    func outOfRangeSpecIsRefused() {
        for spec in ["", "0", "-3", "91", "fourteen", "14d", "1.5"] {
            #expect(ReadinessHistorySeedPlan(spec: spec) == nil, "expected \"\(spec)\" to be refused")
        }
    }

    @Test("Each past day gets a night, the morning's vitals and a scored record; today gets none")
    func everyPastDayIsScored() throws {
        let plan = try #require(ReadinessHistorySeedPlan(days: 7))
        let days = try plan.apply(into: db, now: now, timeModel: timeModel)

        #expect(days.map(\.value) == ["2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05",
                                      "2026-10-06", "2026-10-07", "2026-10-08"])
        let records = try ReadinessRecordStore(db: db).records(limit: 90)
        #expect(records.map(\.anchorDate) == days.map(\.value))
        #expect(records.allSatisfy { $0.score != nil }, "a seeded day with sleep and vitals must score")

        let sleep = SleepEpisodeStore(db: db)
        for day in days {
            let night = try sleep.episodes(for: day.value)
            #expect(night.count == 1)
            #expect(night.first?.effectiveType == .primary)
        }
        #expect(try sleep.episodes(for: "2026-10-09").isEmpty, "today is the dashboard's to score")
    }

    @Test("The scores climb, so the chart has a direction")
    func scoresRise() throws {
        let plan = try #require(ReadinessHistorySeedPlan(days: 14))
        try plan.apply(into: db, now: now, timeModel: timeModel)
        let scores = try ReadinessRecordStore(db: db).records(limit: 90).compactMap(\.score)
        #expect(scores.count == 14)
        let oldest = try #require(scores.first)
        let newest = try #require(scores.last)
        #expect(newest > oldest, "scores \(scores) do not climb")
    }

    @Test("Applying the plan again changes nothing")
    func reapplyingIsIdempotent() throws {
        let plan = try #require(ReadinessHistorySeedPlan(days: 5))
        try plan.apply(into: db, now: now, timeModel: timeModel)
        let first = try ReadinessRecordStore(db: db).records(limit: 90).map { [$0.anchorDate, "\($0.score ?? -1)"] }
        try plan.apply(into: db, now: now, timeModel: timeModel)
        let second = try ReadinessRecordStore(db: db).records(limit: 90).map { [$0.anchorDate, "\($0.score ?? -1)"] }
        #expect(first == second)

        let sleep = SleepEpisodeStore(db: db)
        #expect(try sleep.episodes(for: "2026-10-08").count == 1, "a second application added a second night")
        let rhr = try VitalsRecordStore(db: db, zone: ZoneContext(zone), timeModel: timeModel)
            .manualRecords(metric: .restingHeartRate, for: "2026-10-08")
        #expect(rhr.count == 1, "a second application added a second reading")
    }
}
