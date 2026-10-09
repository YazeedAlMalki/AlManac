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
}
