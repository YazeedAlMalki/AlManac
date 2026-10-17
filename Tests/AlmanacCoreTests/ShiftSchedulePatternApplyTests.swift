import Testing
import Foundation
@testable import AlmanacCore

/// `ShiftScheduleStore.applyPattern` — the path the shift editor takes when the
/// user enters a rotation rather than one day. Read back through the store's
/// own `occurrence(for:)`, the way every other reader of shifts sees them.
@Suite("ShiftScheduleStore applyPattern Tests")
struct ShiftSchedulePatternApplyTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)

    init() throws {
        db = try TestDatabase()
    }

    private var store: ShiftScheduleStore { ShiftScheduleStore(db: db) }

    private func pattern(scheduleId: Int64, sequence: String, start: String) -> ShiftRecurrencePatternDraft {
        ShiftRecurrencePatternDraft(scheduleId: scheduleId, patternType: "custom",
                                    shiftSequence: sequence, startDate: start)
    }

    @Test("An applied rotation can be read back day by day, each day pointing at its pattern")
    func appliedRotationIsReadable() throws {
        let scheduleId = try store.createSchedule(ShiftScheduleDraft(name: "Rota"))

        let patternId = try store.applyPattern(
            pattern(scheduleId: scheduleId, sequence: #"["night","night","rest"]"#, start: "2026-09-01"),
            through: LogicalDay("2026-09-04"), timeModel: timeModel)

        let read = try ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"]
            .map { try store.occurrence(for: $0) }
        #expect(read.map { $0?.shiftType } == [.night, .night, .rest, .night])
        #expect(read.allSatisfy { $0?.recurrencePatternId == patternId })
    }

    @Test("A rotation that cannot be expanded leaves no pattern row behind")
    func unreadablePatternLeavesNothing() throws {
        let scheduleId = try store.createSchedule(ShiftScheduleDraft(name: "Rota"))

        #expect(throws: ShiftPatternError.unknownShiftType("graveyard")) {
            try store.applyPattern(
                pattern(scheduleId: scheduleId, sequence: #"["night","graveyard"]"#, start: "2026-09-01"),
                through: LogicalDay("2026-09-03"), timeModel: timeModel)
        }

        // No reader for patterns exists on the store, so the table is asked.
        let stored = try db.query("SELECT COUNT(*) AS n FROM shift_recurrence_pattern;").first?.int("n")
        #expect(stored == 0)
        #expect(try store.occurrence(for: "2026-09-01") == nil)
    }

    @Test("A day the user changed by hand keeps their change when a rotation is applied over it")
    func manualOverrideSurvivesApply() throws {
        let scheduleId = try store.createSchedule(ShiftScheduleDraft(name: "Rota"))
        try store.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: "2026-09-02", shiftType: .day, isManualOverride: true))

        try store.applyPattern(
            pattern(scheduleId: scheduleId, sequence: #"["night"]"#, start: "2026-09-01"),
            through: LogicalDay("2026-09-03"), timeModel: timeModel)

        let read = try ["2026-09-01", "2026-09-02", "2026-09-03"].map { try store.occurrence(for: $0) }
        #expect(read.map { $0?.shiftType } == [.night, .day, .night])
        #expect(read[1]?.isManualOverride == true)
    }

    // MARK: - The schedule the editor writes into

    @Test("The first call creates the user's schedule and every later call returns the same one")
    func defaultScheduleIsCreatedOnce() throws {
        let first = try store.defaultScheduleId()
        let second = try store.defaultScheduleId()

        #expect(first == second)
        let rows = try db.query("SELECT COUNT(*) AS n FROM shift_schedule;").first?.int("n")
        #expect(rows == 1)
    }

    @Test("An existing active schedule is reused rather than shadowed by a new one")
    func existingActiveScheduleIsReused() throws {
        let existing = try store.createSchedule(ShiftScheduleDraft(name: "Ward rota"))

        #expect(try store.defaultScheduleId() == existing)
    }
}
