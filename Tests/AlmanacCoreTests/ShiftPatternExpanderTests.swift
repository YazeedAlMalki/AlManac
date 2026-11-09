import Testing
import Foundation
@testable import AlmanacCore

/// `ShiftPatternExpander` — turns a stored recurrence rule into the dated
/// shifts the rest of the app reads. `ShiftScheduleStore` deliberately does
/// not do this; it persists whatever occurrences it is handed.
@Suite("ShiftPatternExpander Tests")
struct ShiftPatternExpanderTests {
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)

    private func pattern(type: String = "custom", sequence: String,
                         start: String, end: String? = nil) -> ShiftRecurrencePatternDraft {
        ShiftRecurrencePatternDraft(scheduleId: 7, patternType: type, shiftSequence: sequence,
                                    startDate: start, endDate: end)
    }

    @Test("Four nights on and four off cycles through the days, one shift per day")
    func fourOnFourOffCycles() throws {
        let sequence = #"["night","night","night","night","rest","rest","rest","rest"]"#

        let drafts = try ShiftPatternExpander.occurrences(
            for: pattern(sequence: sequence, start: "2026-09-01"),
            through: LogicalDay("2026-09-10"), timeModel: timeModel)

        #expect(drafts.map(\.date) == [
            "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05",
            "2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10"
        ])
        #expect(drafts.map(\.shiftType) == [
            .night, .night, .night, .night, .rest, .rest, .rest, .rest, .night, .night
        ])
    }

    @Test("A pattern with an end date stops there even when asked for later days")
    func endDateCapsTheExpansion() throws {
        let drafts = try ShiftPatternExpander.occurrences(
            for: pattern(sequence: #"["day","rest"]"#, start: "2026-09-01", end: "2026-09-04"),
            through: LogicalDay("2026-09-30"), timeModel: timeModel)

        #expect(drafts.map(\.date) == ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"])
    }

    @Test("Generated shifts belong to the schedule, point back at their pattern, and are not manual overrides")
    func draftsAreLinkedToTheirPattern() throws {
        let drafts = try ShiftPatternExpander.occurrences(
            for: pattern(sequence: #"["day"]"#, start: "2026-09-01"), patternId: 42,
            through: LogicalDay("2026-09-03"), timeModel: timeModel)

        #expect(drafts.count == 3)
        #expect(drafts.allSatisfy { $0.scheduleId == 7 })
        #expect(drafts.allSatisfy { $0.recurrencePatternId == 42 })
        #expect(drafts.allSatisfy { !$0.isManualOverride })
    }

    @Test("A monthly rotation is refused rather than guessed at")
    func monthlyRotationIsUnsupported() throws {
        #expect(throws: ShiftPatternError.unsupportedPatternType("monthly_rotation")) {
            try ShiftPatternExpander.occurrences(
                for: pattern(type: "monthly_rotation", sequence: #"["day"]"#, start: "2026-09-01"),
                through: LogicalDay("2026-09-03"), timeModel: timeModel)
        }
    }

    @Test("A cycle carries across the end of the year without losing its place")
    func cycleCrossesYearEnd() throws {
        let drafts = try ShiftPatternExpander.occurrences(
            for: pattern(sequence: #"["day","evening","night"]"#, start: "2026-12-30"),
            through: LogicalDay("2027-01-02"), timeModel: timeModel)

        #expect(drafts.map(\.date) == ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"])
        #expect(drafts.map(\.shiftType) == [.day, .evening, .night, .day])
    }

    @Test("A rotation built from a list of shifts expands back to that list, on-call included")
    func draftBuiltFromShiftsRoundTrips() throws {
        let draft = ShiftRecurrencePatternDraft(scheduleId: 7, shifts: [.night, .onCall, .rest],
                                                startDate: "2026-09-01")

        let drafts = try ShiftPatternExpander.occurrences(
            for: draft, through: LogicalDay("2026-09-04"), timeModel: timeModel)

        #expect(drafts.map(\.shiftType) == [.night, .onCall, .rest, .night])
        #expect(draft.patternType == "custom")
    }

    @Test("An empty sequence is refused rather than expanding to nothing or crashing")
    func emptySequenceIsRefused() throws {
        #expect(throws: ShiftPatternError.emptySequence) {
            try ShiftPatternExpander.occurrences(
                for: pattern(sequence: "[]", start: "2026-09-01"),
                through: LogicalDay("2026-09-03"), timeModel: timeModel)
        }
    }

    @Test("A shift name the app does not know is refused, not skipped, because skipping it would shift every later day")
    func unknownShiftNameIsRefused() throws {
        #expect(throws: ShiftPatternError.unknownShiftType("graveyard")) {
            try ShiftPatternExpander.occurrences(
                for: pattern(sequence: #"["day","graveyard","rest"]"#, start: "2026-09-01"),
                through: LogicalDay("2026-09-03"), timeModel: timeModel)
        }
    }

    // MARK: - Saved patterns: weekly and monthly cadence

    private func saved(_ blocks: [ShiftBlock], _ cadence: ShiftCadence, start: String) -> ShiftRecurrencePatternDraft {
        ShiftRecurrencePatternDraft(scheduleId: 7, blocks: blocks, cadence: cadence,
                                    startDate: start, savedPatternId: 5)
    }

    private func shifts(_ drafts: [ShiftOccurrenceDraft], on dates: [String]) -> [ShiftType?] {
        let byDate = Dictionary(uniqueKeysWithValues: drafts.map { ($0.date, $0.shiftType) })
        return dates.map { byDate[$0] }
    }

    @Test("A weekly pattern started on a Wednesday repeats its blocks inside the week and starts again each Wednesday")
    func weeklyCadenceRestartsEachWeek() throws {
        // 3 nights then 1 rest is four days, so it repeats inside a week and is
        // cut off at day 7. Day 8 (28 Oct) is the start of the next week: block
        // one again, a night, where carrying on would have given a rest.
        let drafts = try ShiftPatternExpander.occurrences(
            for: saved([ShiftBlock(.night, days: 3), ShiftBlock(.rest, days: 1)], .weekly, start: "2026-10-21"),
            through: LogicalDay("2026-11-04"), timeModel: timeModel)

        #expect(drafts.map(\.date).first == "2026-10-21")
        #expect(drafts.map(\.date).last == "2026-11-04")
        #expect(drafts.map(\.shiftType) == [
            .night, .night, .night, .rest, .night, .night, .night,
            .night, .night, .night, .rest, .night, .night, .night,
            .night
        ])
        #expect(drafts.allSatisfy { $0.recurrencePatternId == nil && !$0.isManualOverride })
    }

    @Test("A monthly pattern started mid-month starts again on the same date each month")
    func monthlyCadenceRestartsOnTheStartDate() throws {
        // 2 nights then 3 rests is five days. 15 Oct to 14 Nov is 31 days, so
        // 14 Nov is block one by the count (day 30) and 15 Nov is block one
        // because a new month begins. 16 Nov is the test: a night here, where
        // carrying on from October would have made it a rest.
        let drafts = try ShiftPatternExpander.occurrences(
            for: saved([ShiftBlock(.night, days: 2), ShiftBlock(.rest, days: 3)], .monthly, start: "2026-10-15"),
            through: LogicalDay("2026-11-18"), timeModel: timeModel)

        #expect(shifts(drafts, on: ["2026-10-15", "2026-10-16", "2026-10-17", "2026-10-20"])
                == [.night, .night, .rest, .night])
        #expect(shifts(drafts, on: ["2026-11-14", "2026-11-15", "2026-11-16", "2026-11-17"])
                == [.night, .night, .night, .rest])
    }

    @Test("A monthly pattern started on the 31st counts its months from the 31st, through a short February")
    func monthlyCadenceFromTheEndOfAMonth() throws {
        // Months count from the start date itself: 31 Jan, 28 Feb (no 31st),
        // 31 Mar. 2 days then 1 rest; 1 Mar and 1 Apr are each day two of a
        // fresh month, so a day shift, where carrying on would have given rest.
        let drafts = try ShiftPatternExpander.occurrences(
            for: saved([ShiftBlock(.day, days: 2), ShiftBlock(.rest, days: 1)], .monthly, start: "2027-01-31"),
            through: LogicalDay("2027-04-03"), timeModel: timeModel)

        #expect(shifts(drafts, on: ["2027-01-31", "2027-02-01", "2027-02-02", "2027-02-27"])
                == [.day, .day, .rest, .day])
        #expect(shifts(drafts, on: ["2027-02-28", "2027-03-01", "2027-03-02"]) == [.day, .day, .rest])
        #expect(shifts(drafts, on: ["2027-03-29", "2027-03-30", "2027-03-31", "2027-04-01", "2027-04-02"])
                == [.rest, .day, .day, .day, .rest])
    }

    @Test("Weekly and monthly patterns accept any start date, and each period opens on block one",
          arguments: [
            ("2026-10-19", ShiftCadence.weekly, ["2026-10-19", "2026-10-26", "2026-11-02"]),
            ("2026-10-25", ShiftCadence.weekly, ["2026-10-25", "2026-11-01", "2026-11-08"]),
            ("2026-12-29", ShiftCadence.weekly, ["2026-12-29", "2027-01-05", "2027-01-12"]),
            ("2026-10-01", ShiftCadence.monthly, ["2026-10-01", "2026-11-01", "2026-12-01"]),
            ("2026-12-30", ShiftCadence.monthly, ["2026-12-30", "2027-01-30", "2027-02-28"]),
            ("2028-01-29", ShiftCadence.monthly, ["2028-01-29", "2028-02-29", "2028-03-29"])
          ])
    func anyStartDate(start: String, cadence: ShiftCadence, periodStarts: [String]) throws {
        // Four days of evening then nine of rest: longer than a week, so a week
        // never reaches the rests' end, and no period start is block one by
        // the count alone except by restarting.
        let drafts = try ShiftPatternExpander.occurrences(
            for: saved([ShiftBlock(.evening, days: 4), ShiftBlock(.rest, days: 9)], cadence, start: start),
            through: LogicalDay(periodStarts.last!), timeModel: timeModel)

        #expect(drafts.first?.date == start)
        #expect(shifts(drafts, on: periodStarts) == periodStarts.map { _ in .evening })
        // The day before each later period start is inside the previous period.
        let byDate = Dictionary(uniqueKeysWithValues: drafts.map { ($0.date, $0.shiftType) })
        for later in periodStarts.dropFirst() {
            let eve = timeModel.day(before: LogicalDay(later))!.value
            #expect(byDate[eve] != nil, "\(eve) is missing")
        }
    }

    @Test("Blocks of several days flatten into one shift per day, in order")
    func blocksFlattenToDays() throws {
        let draft = saved([ShiftBlock(.day, days: 2), ShiftBlock(.night, days: 3), ShiftBlock(.rest, days: 2)],
                          .weekly, start: "2026-10-19")

        #expect(draft.patternType == "weekly_rotation")
        #expect(draft.savedPatternId == 5)
        let week = try ShiftPatternExpander.occurrences(for: draft, through: LogicalDay("2026-10-25"),
                                                        timeModel: timeModel)
        #expect(week.map(\.shiftType) == [.day, .day, .night, .night, .night, .rest, .rest])
    }

    @Test("A monthly rotation that is not a saved pattern is still refused")
    func monthlyRotationOutsideASavedPatternIsStillRefused() throws {
        var draft = saved([ShiftBlock(.day, days: 1)], .monthly, start: "2026-09-01")
        draft.savedPatternId = nil
        #expect(throws: ShiftPatternError.unsupportedPatternType("monthly_rotation")) {
            try ShiftPatternExpander.occurrences(for: draft, through: LogicalDay("2026-09-03"), timeModel: timeModel)
        }
    }
}
