import Testing
import Foundation
@testable import AlmanacCore

/// `ShiftSeedPlan` — the launch argument a UI test uses to put the shift
/// schedule in a known state. The simulator's database is shared across runs
/// and never reset, and the shift editor persists, so without this one run's
/// shifts would be the next run's starting point.
@Suite("ShiftSeedPlan Tests")
struct ShiftSeedPlanTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    /// 2026-09-05 12:00 Riyadh, so "today" is the logical day 2026-09-05.
    let now = Date(timeIntervalSince1970: 1_788_598_800)

    init() throws {
        db = try TestDatabase()
    }

    @Test("Only the explicit argument asks for a plan; an ordinary launch gets nil")
    func ordinaryLaunchGetsNothing() {
        #expect(ShiftSeedPlan.fromLaunchArguments([]) == nil)
        #expect(ShiftSeedPlan.fromLaunchArguments(["Almanac"]) == nil)
        #expect(ShiftSeedPlan.fromLaunchArguments(["-AppleLanguages", "(en)"]) == nil)
        // The flag with nothing after it names no plan.
        #expect(ShiftSeedPlan.fromLaunchArguments(["-AlmanacSeedShifts"]) == nil)
        #expect(ShiftSeedPlan.fromLaunchArguments(["-AlmanacSeedShifts", "none"]) != nil)
    }

    @Test("Applying a plan replaces whatever shifts were there, and applying it twice leaves one copy")
    func applyingIsAuthoritative() throws {
        let store = ShiftScheduleStore(db: db)
        let old = try store.createSchedule(ShiftScheduleDraft(name: "Left by an earlier run"))
        try store.logOccurrence(ShiftOccurrenceDraft(scheduleId: old, date: "2026-08-20", shiftType: .day))
        let plan = try #require(ShiftSeedPlan(spec: "night:-1,rest:0"))

        try plan.apply(into: db, now: now, timeModel: timeModel)
        try plan.apply(into: db, now: now, timeModel: timeModel)

        #expect(try store.occurrence(for: "2026-08-20") == nil)
        #expect(try store.occurrence(for: "2026-09-04")?.shiftType == .night)
        #expect(try store.occurrence(for: "2026-09-05")?.shiftType == .rest)
        // Two applications, two shifts: the second did not stack on the first.
        let rows = try db.query("SELECT COUNT(*) AS n FROM shift_occurrence;").first?.int("n")
        #expect(rows == 2)
    }

    @Test("A spec of none only clears")
    func noneClearsAndPlantsNothing() throws {
        let store = ShiftScheduleStore(db: db)
        let old = try store.createSchedule(ShiftScheduleDraft(name: "Left by an earlier run"))
        try store.logOccurrence(ShiftOccurrenceDraft(scheduleId: old, date: "2026-09-05", shiftType: .night))

        try #require(ShiftSeedPlan(spec: "none")).apply(into: db, now: now, timeModel: timeModel)

        #expect(try store.occurrence(for: "2026-09-05") == nil)
    }

    @Test("A seeded week reaches the timeline the screen reads")
    func seededShiftsReachTheTimeline() throws {
        let plan = try #require(ShiftSeedPlan(spec: "night:-4,night:-3,night:-2,night:-1,night:0"))
        try plan.apply(into: db, now: now, timeModel: timeModel)

        let today = try CircadianTimeline(db: db, timeModel: timeModel)
            .days(from: LogicalDay("2026-09-05"), through: LogicalDay("2026-09-05"))

        #expect(today.map(\.contextType) == [.stableNight])
    }

    @Test("A spec that is not shift:offset pairs is no plan at all, rather than half of one")
    func malformedSpecsAreRejected() {
        #expect(ShiftSeedPlan(spec: "banana:0") == nil)
        #expect(ShiftSeedPlan(spec: "night:x") == nil)
        #expect(ShiftSeedPlan(spec: "night") == nil)
        #expect(ShiftSeedPlan(spec: "night:0,banana:1") == nil)
        #expect(ShiftSeedPlan(spec: "") == nil)
    }
}
