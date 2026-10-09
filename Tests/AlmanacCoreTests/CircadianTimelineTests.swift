import Testing
import Foundation
@testable import AlmanacCore

/// `CircadianTimeline` — a run of days' circadian context, derived from the
/// shift schedule the user has actually entered (§13, BRD §6.11).
///
/// Tested at its one public method against a real database. The engine
/// underneath is covered on its own by `CircadianContextTests`; what is
/// untested anywhere else is that a stored schedule reaches it correctly.
@Suite("CircadianTimeline Tests")
struct CircadianTimelineTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)

    init() throws {
        db = try TestDatabase()
    }

    private var timeline: CircadianTimeline {
        CircadianTimeline(db: db, timeModel: timeModel)
    }

    @Test("With no shift schedule every day is unknown, and no day is given a shift")
    func noScheduleIsUnknownAllWeek() throws {
        let days = try timeline.days(from: LogicalDay("2026-09-01"), through: LogicalDay("2026-09-07"))

        #expect(days.map(\.date.value) == [
            "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04",
            "2026-09-05", "2026-09-06", "2026-09-07"
        ])
        #expect(days.allSatisfy { $0.contextType == .unknown && $0.shiftType == nil })
    }

    @Test("Five nights in a row entered by the user make the fifth stable and the fourth not")
    func enteredNightsReachTheEngine() throws {
        try enter(.night, on: ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"])

        let days = try timeline.days(from: LogicalDay("2026-09-01"), through: LogicalDay("2026-09-05"))

        #expect(days.allSatisfy { $0.shiftType == .night })
        #expect(days[3].contextType != .stableNight, "four nights is not yet a settled rhythm")
        #expect(days[4].contextType == .stableNight)
    }

    @Test("A window that starts partway through a run still sees the run")
    func windowStartingMidRunSeesTheRunBeforeIt() throws {
        try enter(.night, on: ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"])

        // Only the fifth night is asked for. Its context depends on the four
        // nights before it, which are outside the window.
        let days = try timeline.days(from: LogicalDay("2026-09-05"), through: LogicalDay("2026-09-05"))

        #expect(days.map(\.contextType) == [.stableNight])
    }

    @Test("Days then nights is a transition later, counted from the first night, even when the days are outside the window")
    func transitionIsCountedFromTheChange() throws {
        try enter(.day, on: ["2026-09-01", "2026-09-02"])
        try enter(.night, on: ["2026-09-03", "2026-09-04", "2026-09-05"])

        let days = try timeline.days(from: LogicalDay("2026-09-03"), through: LogicalDay("2026-09-05"))

        #expect(days.map(\.contextType) == [.transitionLater, .transitionLater, .transitionLater])
        #expect(days.map(\.transitionDayN) == [1, 2, 3])
    }

    @Test("A day with nothing entered is unknown even between two nights")
    func unscheduledDayInTheMiddleIsUnknown() throws {
        try enter(.night, on: ["2026-09-01", "2026-09-03"])

        let days = try timeline.days(from: LogicalDay("2026-09-01"), through: LogicalDay("2026-09-03"))

        #expect(days[1].contextType == .unknown)
        #expect(days[1].shiftType == nil)
    }

    @Test("A rest day is recovery and keeps its shift type")
    func restDayIsRecovery() throws {
        try enter(.night, on: ["2026-09-01", "2026-09-02"])
        try enter(.rest, on: ["2026-09-03"])

        let days = try timeline.days(from: LogicalDay("2026-09-03"), through: LogicalDay("2026-09-03"))

        #expect(days.map(\.contextType) == [.recovery])
        #expect(days.map(\.shiftType) == [.rest])
    }

    // MARK: - Helpers

    private func enter(_ shift: ShiftType, on dates: [String]) throws {
        let store = ShiftScheduleStore(db: db)
        let scheduleId = try store.createSchedule(ShiftScheduleDraft(name: "Schedule"))
        for date in dates {
            try store.logOccurrence(ShiftOccurrenceDraft(scheduleId: scheduleId, date: date, shiftType: shift))
        }
    }
}
