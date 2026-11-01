import Testing
import Foundation
@testable import AlmanacCore

/// The launch-argument hook that fills the app with months of lived-in history.
///
/// Pinned: it cannot run without being asked for, it plants something in every
/// module it claims to, and a second launch with the same argument adds nothing.
@Suite("Demo History Seed Plan")
struct DemoHistorySeedPlanTests {
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

    private func count(_ table: String) throws -> Int {
        Int(try db.query("SELECT count(*) AS n FROM \(table);").first?.int("n") ?? 0)
    }

    @Test("A launch with no seeding argument asks for nothing")
    func absentArgumentYieldsNoPlan() {
        #expect(DemoHistorySeedPlan.fromLaunchArguments([]) == nil)
        #expect(DemoHistorySeedPlan.fromLaunchArguments(["-AlmanacSeedDemoHistory"]) == nil)
        #expect(DemoHistorySeedPlan.fromLaunchArguments(["-AlmanacSeedDemoHistory", "0"]) == nil)
        #expect(DemoHistorySeedPlan.fromLaunchArguments(["-AlmanacSeedDemoHistory", "90"])?.days == 90)
    }

    @Test("Every module gets history, once")
    func plantsEveryModuleOnce() throws {
        try WorkoutGuideSeed.seed(into: ExerciseCatalogStore(db: db))
        let plan = try #require(DemoHistorySeedPlan(days: 28))

        #expect(try plan.apply(into: db, now: now, timeModel: timeModel) == 28)
        for table in ["workoutSession", "workoutBout", "hydration_log", "nutrition_log",
                      "sleep_episode", "readiness_record", "mood_log",
                      "body_composition_measurement", "body_measurement",
                      "bowel_movement", "urination_record", "supplement_log"] {
            #expect(try count(table) > 0, "\(table) was left empty")
        }

        let water = try count("hydration_log")
        #expect(try plan.apply(into: db, now: now, timeModel: timeModel) == 0)
        #expect(try count("hydration_log") == water)
    }
}
