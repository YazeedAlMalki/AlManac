import Testing
import Foundation
@testable import AlmanacCore

/// Saved shift patterns (spec section 2): a name, blocks of days on one shift,
/// a start date, a weekly or monthly cadence and a run length in nights.
/// Read back through the stores, the way the app reads them.
@Suite("Saved shift patterns")
struct SavedShiftPatternStoreTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)

    init() throws {
        db = try TestDatabase()
    }

    private var store: SavedShiftPatternStore { SavedShiftPatternStore(db: db, timeModel: timeModel) }
    private var shifts: ShiftScheduleStore { ShiftScheduleStore(db: db) }

    private func threeNights(start: String = "2026-10-21", cadence: ShiftCadence = .weekly,
                             runLength: Int? = nil) -> SavedShiftPatternDraft {
        SavedShiftPatternDraft(name: "Three nights",
                               blocks: [ShiftBlock(.night, days: 3), ShiftBlock(.rest, days: 1)],
                               startDate: LogicalDay(start), cadence: cadence, runLengthNights: runLength)
    }

    // MARK: - Storing

    @Test("A saved pattern keeps its name, blocks, start date, cadence and run length")
    func savedPatternRoundTrips() throws {
        let id = try store.save(threeNights(start: "2026-10-15", cadence: .monthly, runLength: 4))

        let read = try #require(try store.pattern(id: id))
        #expect(read.name == "Three nights")
        #expect(read.blocks == [ShiftBlock(.night, days: 3), ShiftBlock(.rest, days: 1)])
        #expect(read.startDate == LogicalDay("2026-10-15"))
        #expect(read.cadence == .monthly)
        #expect(read.runLengthNights == 4)
        #expect(try store.patterns().map(\.id) == [id])
    }

    @Test("A pattern saved without a run length has none, rather than a number nobody chose")
    func runLengthIsOptional() throws {
        let id = try store.save(threeNights())
        #expect(try store.pattern(id: id)?.runLengthNights == nil)
    }

    @Test("A pattern with no name, no blocks, or a block of no days is refused")
    func invalidPatternsAreRefused() throws {
        var unnamed = threeNights()
        unnamed.name = "  "
        #expect(throws: SavedShiftPatternError.missingName) { try store.save(unnamed) }

        var empty = threeNights()
        empty.blocks = []
        #expect(throws: SavedShiftPatternError.noBlocks) { try store.save(empty) }

        var zero = threeNights()
        zero.blocks = [ShiftBlock(.night, days: 0)]
        #expect(throws: SavedShiftPatternError.blockWithNoDays) { try store.save(zero) }

        var noRun = threeNights()
        noRun.runLengthNights = 0
        #expect(throws: SavedShiftPatternError.runLengthNotPositive) { try store.save(noRun) }

        #expect(try store.patterns().isEmpty)
    }

    @Test("Migration 069 only adds: every shift row from before it is still there, unchanged")
    func migrationIsAdditive() throws {
        let existing = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all.filter { $0.version < 69 }).migrate(existing)
        // Written in SQL, the columns as they were before 069: the stores now
        // write the columns 069 adds.
        try existing.execute("""
        INSERT INTO shift_schedule (id, name, isActive, createdAt, updatedAt) VALUES (1, 'Rota', 1, 'x', 'x');
        INSERT INTO shift_recurrence_pattern (id, scheduleId, patternType, shiftSequence, startDate, createdAt)
            VALUES (9, 1, 'custom', '["night","rest"]', '2026-09-01', 'x');
        INSERT INTO shift_occurrence (scheduleId, date, shiftType, isManualOverride, recurrencePatternId, createdAt)
            VALUES (1, '2026-09-01', 'night', 0, 9, 'x');
        INSERT INTO shift_occurrence (scheduleId, date, shiftType, isManualOverride, notes, createdAt)
            VALUES (1, '2026-09-03', 'day', 1, 'swap', 'x');
        """)
        let patternId: Int64 = 9

        #expect(try MigrationRunner(migrations: AlmanacMigrations.all).migrate(existing) == [69, 70])

        let after = ShiftScheduleStore(db: existing)
        #expect(try after.occurrence(for: "2026-09-01")?.shiftType == .night)
        #expect(try after.occurrence(for: "2026-09-01")?.recurrencePatternId == patternId)
        #expect(try after.occurrence(for: "2026-09-03")?.notes == "swap")
        let rule = try existing.query("SELECT patternType, savedPatternId FROM shift_recurrence_pattern;").first
        #expect(rule?.string("patternType") == "custom")
        #expect(rule?.int("savedPatternId") == nil)
        #expect(try existing.query("SELECT name FROM shift_schedule;").first?.string("name") == "Rota")
    }

    // MARK: - Using a pattern

    private func shift(on date: String) throws -> ShiftType? { try shifts.occurrence(for: date)?.shiftType }

    @Test("Using a saved pattern writes its shifts from its start date, each pointing at the pattern")
    func usingAPatternWritesItsShifts() throws {
        let id = try store.save(threeNights(start: "2026-10-21"))
        try store.use(id, today: LogicalDay("2026-10-21"))

        // Weekly from Wednesday 21 Oct: N N N R N N N, then N again on the 28th.
        let week = try ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25",
                        "2026-10-26", "2026-10-27", "2026-10-28"].map(shift(on:))
        #expect(week == [.night, .night, .night, .rest, .night, .night, .night, .night])
        let rule = try #require(try shifts.occurrence(for: "2026-10-22")?.recurrencePatternId)
        #expect(try db.query("SELECT savedPatternId FROM shift_recurrence_pattern WHERE id = ?;",
                             [.integer(rule)]).first?.int("savedPatternId") == id)
        #expect(try store.selection().currentId == id)
        // Four weeks ahead, so the screen's week and the reminders have shifts to read.
        #expect(try shift(on: "2026-11-17") != nil)
    }

    @Test("Refreshing twice writes nothing the second time")
    func refreshIsIdempotent() throws {
        let id = try store.save(threeNights())
        try store.use(id, today: LogicalDay("2026-10-21"))
        let count = { try db.query("SELECT COUNT(*) AS n FROM shift_occurrence;").first?.int("n") }
        let before = try count()
        try store.refresh(today: LogicalDay("2026-10-21"))
        try store.refresh(today: LogicalDay("2026-10-21"))
        #expect(try count() == before)
    }

    @Test("A one-day entry inside a saved pattern wins, and keeps the pattern's shift as a note")
    func oneDayEntryWinsAndKeepsAnote() throws {
        // Entered before the pattern: the 23rd would be a night.
        let scheduleId = try shifts.defaultScheduleId()
        try shifts.logOccurrence(ShiftOccurrenceDraft(scheduleId: scheduleId, date: "2026-10-23",
                                                      shiftType: .day, isManualOverride: true))
        let id = try store.save(threeNights(start: "2026-10-21"))
        try store.use(id, today: LogicalDay("2026-10-21"))

        let before = try #require(try shifts.occurrence(for: "2026-10-23"))
        #expect(before.shiftType == .day)
        #expect(before.isManualOverride)
        #expect(before.notes == "Saved pattern: night")

        // Entered after: the 24th is the pattern's rest day.
        try shifts.logOneDay(scheduleId: scheduleId, date: "2026-10-24", shift: .evening)
        let after = try #require(try shifts.occurrence(for: "2026-10-24"))
        #expect(after.shiftType == .evening)
        #expect(after.isManualOverride)
        #expect(after.notes == "Saved pattern: rest")
        #expect(SavedShiftPatternNote.shift(in: after.notes) == .rest)

        // The pattern running on does not take either day back.
        try store.refresh(today: LogicalDay("2026-10-25"))
        #expect(try shift(on: "2026-10-23") == .day)
        #expect(try shift(on: "2026-10-24") == .evening)
    }

    @Test("A one-day entry outside any saved pattern carries no note, as before")
    func oneDayEntryOutsideAPatternIsUnchanged() throws {
        let scheduleId = try shifts.defaultScheduleId()
        try shifts.applyPattern(ShiftRecurrencePatternDraft(scheduleId: scheduleId, shifts: [.night],
                                                            startDate: "2026-10-21"),
                                through: LogicalDay("2026-10-25"), timeModel: timeModel)
        try shifts.logOneDay(scheduleId: scheduleId, date: "2026-10-22", shift: .day)
        try shifts.logOneDay(scheduleId: scheduleId, date: "2026-12-01", shift: .day)
        #expect(try shifts.occurrence(for: "2026-10-22")?.notes == nil)
        #expect(try shifts.occurrence(for: "2026-12-01")?.notes == nil)
        #expect(try shifts.occurrence(for: "2026-10-22")?.isManualOverride == true)
    }

    @Test("A rotation entered over a running pattern keeps its days")
    func rotationOverAPatternKeepsItsDays() throws {
        let id = try store.save(threeNights(start: "2026-10-21"))
        try store.use(id, today: LogicalDay("2026-10-21"))
        try shifts.applyPattern(ShiftRecurrencePatternDraft(scheduleId: try shifts.defaultScheduleId(),
                                                            shifts: [.day], startDate: "2026-10-26"),
                                through: LogicalDay("2026-10-30"), timeModel: timeModel)
        try store.refresh(today: LogicalDay("2026-10-22"))
        #expect(try shift(on: "2026-10-26") == .day)
        #expect(try shift(on: "2026-11-01") == .night, "after the rotation's end the pattern runs on")
    }

    @Test("Past days are history: a refresh never rewrites a day before today")
    func pastDaysAreNotRewritten() throws {
        let a = try store.save(threeNights(start: "2026-10-21"))
        try store.use(a, today: LogicalDay("2026-10-21"))
        var other = threeNights(start: "2026-10-21")
        other.name = "Days"
        other.blocks = [ShiftBlock(.day, days: 1)]
        let b = try store.save(other)
        try store.use(b, today: LogicalDay("2026-10-25"))
        #expect(try shift(on: "2026-10-22") == .night)
        #expect(try shift(on: "2026-10-25") == .day)
    }

    @Test("Picking another pattern leaves a past one-day entry's note naming the pattern that ran then")
    func switchingPatternsKeepsHistoricalNotes() throws {
        let scheduleId = try shifts.defaultScheduleId()
        let nights = try store.save(threeNights(start: "2026-10-21"))
        try store.use(nights, today: LogicalDay("2026-10-21"))
        // The 23rd and the 27th are both nights under this pattern.
        try shifts.logOneDay(scheduleId: scheduleId, date: "2026-10-23", shift: .rest)
        try shifts.logOneDay(scheduleId: scheduleId, date: "2026-10-27", shift: .rest)
        #expect(try shifts.occurrence(for: "2026-10-23")?.notes == "Saved pattern: night")

        var other = threeNights(start: "2026-10-21")
        other.name = "Days"
        other.blocks = [ShiftBlock(.day, days: 1)]
        let days = try store.save(other)
        try store.use(days, today: LogicalDay("2026-10-25"))

        #expect(try shifts.occurrence(for: "2026-10-23")?.notes == "Saved pattern: night",
                "the days pattern never governed the 23rd")
        #expect(try shift(on: "2026-10-23") == .rest)
        #expect(try shifts.occurrence(for: "2026-10-27")?.notes == "Saved pattern: day",
                "a day from today on takes the new pattern's note")
    }

    // MARK: - Period end

    private func days(start: String = "2026-10-21", cadence: ShiftCadence = .weekly) -> SavedShiftPatternDraft {
        SavedShiftPatternDraft(name: "Days", blocks: [ShiftBlock(.day, days: 1)],
                               startDate: LogicalDay(start), cadence: cadence)
    }

    private func setReminder(_ on: Bool) throws {
        try NotificationRuleStore(db: db).setEnabled(on, for: .shiftPattern)
    }

    @Test("With the reminder on, the pattern set as next does not start by itself: the current one keeps running")
    func reminderOnNothingChangesUntilThePersonPicks() throws {
        let a = try store.save(threeNights())
        let b = try store.save(days())
        try store.use(a, today: LogicalDay("2026-10-22"))
        try store.setNext(b, today: LogicalDay("2026-10-22"))

        try store.refresh(today: LogicalDay("2026-10-28"))
        #expect(try store.selection().currentId == a)
        #expect(try store.selection().nextId == b)
        #expect(try shift(on: "2026-10-28") == .night)
        #expect(try shift(on: "2026-10-31") == .rest)
    }

    @Test("With the reminder removed, the pattern set as next starts at the period end",
          arguments: [(ShiftCadence.weekly, "2026-10-21", "2026-10-28"),
                      (ShiftCadence.monthly, "2026-10-15", "2026-11-15")])
    func reminderOffNextStartsAtPeriodEnd(cadence: ShiftCadence, start: String, periodEnd: String) throws {
        try setReminder(false)
        let a = try store.save(threeNights(start: start, cadence: cadence))
        // The next pattern's own start date is long before: it counts from the
        // period end it takes over at, so its first day is block one.
        let b = try store.save(SavedShiftPatternDraft(
            name: "Evenings", blocks: [ShiftBlock(.evening, days: 2), ShiftBlock(.rest, days: 2)],
            startDate: LogicalDay("2026-01-01"), cadence: .weekly))
        try store.use(a, today: LogicalDay("2026-10-22"))
        try store.setNext(b, today: LogicalDay("2026-10-22"))

        #expect(try store.selection().nextStartsOn == LogicalDay(periodEnd))
        let eve = timeModel.day(before: LogicalDay(periodEnd))!.value
        #expect(try shifts.occurrence(for: eve)?.recurrencePatternId != nil)
        #expect(try shift(on: eve) != .evening, "the last day of the period is still the current pattern's")
        let second = timeModel.day(after: LogicalDay(periodEnd))!.value
        let third = timeModel.day(after: LogicalDay(second))!.value
        #expect(try [periodEnd, second, third].map(shift(on:)) == [.evening, .evening, .rest])

        try store.refresh(today: LogicalDay(periodEnd))
        let selection = try store.selection()
        #expect(selection.currentId == b)
        #expect(selection.anchor == LogicalDay(periodEnd))
        #expect(selection.nextId == nil)
    }

    @Test("With the reminder removed and nothing set as next, the current pattern keeps running")
    func reminderOffNoNextKeepsRunning() throws {
        try setReminder(false)
        let a = try store.save(threeNights())
        try store.use(a, today: LogicalDay("2026-10-22"))

        try store.refresh(today: LogicalDay("2026-11-10"))
        #expect(try store.selection().currentId == a)
        // 4 Nov is a period start (weekly from 21 Oct): block one, a night.
        #expect(try shift(on: "2026-11-04") == .night)
        #expect(try shift(on: "2026-11-07") == .rest)
        #expect(try shift(on: "2026-12-07") != nil, "four weeks ahead of the new today")
    }

    @Test("Turning the reminder back on before the period end means the next pattern waits again")
    func reminderBackOnCancelsTheAutomaticStart() throws {
        try setReminder(false)
        let a = try store.save(threeNights())
        let b = try store.save(days())
        try store.use(a, today: LogicalDay("2026-10-22"))
        try store.setNext(b, today: LogicalDay("2026-10-22"))
        #expect(try shift(on: "2026-10-28") == .day)

        try setReminder(true)
        try store.refresh(today: LogicalDay("2026-10-23"))
        #expect(try store.selection().nextStartsOn == nil)
        #expect(try shift(on: "2026-10-28") == .night)
        try store.refresh(today: LogicalDay("2026-10-28"))
        #expect(try store.selection().currentId == a)
    }

    @Test("Switching the reminder off fixes the next start at once, so a late refresh does not push it a period on")
    func switchingTheReminderOffFixesTheNextStartAtOnce() throws {
        let a = try store.save(threeNights(start: "2026-10-21"))
        let b = try store.save(days())
        try store.use(a, today: LogicalDay("2026-10-22"))
        try store.setNext(b, today: LogicalDay("2026-10-22"))
        #expect(try store.selection().nextStartsOn == nil)

        // Switched off on the 25th, from any screen; the app next opens on the 28th.
        try store.setReminder(false, today: LogicalDay("2026-10-25"))
        #expect(try NotificationRuleStore(db: db).isEnabled(.shiftPattern) == false)
        #expect(try store.selection().nextStartsOn == LogicalDay("2026-10-28"))

        try store.refresh(today: LogicalDay("2026-10-28"))
        let selection = try store.selection()
        #expect(selection.currentId == b)
        #expect(selection.anchor == LogicalDay("2026-10-28"))
        #expect(try shift(on: "2026-10-28") == .day)

        // And back on: the store turns it on and the automatic start is dropped.
        try store.setReminder(true, today: LogicalDay("2026-10-28"))
        #expect(try NotificationRuleStore(db: db).isEnabled(.shiftPattern))
        #expect(try store.selection().nextStartsOn == nil)
    }

    @Test("The running pattern's next period starts on its next week or month boundary")
    func nextPeriodStart() throws {
        let a = try store.save(threeNights(start: "2027-01-31", cadence: .monthly))
        try store.use(a, today: LogicalDay("2027-02-10"))
        #expect(try store.nextPeriodStart(after: LogicalDay("2027-02-10")) == LogicalDay("2027-02-28"))
        #expect(try store.nextPeriodStart(after: LogicalDay("2027-02-28")) == LogicalDay("2027-03-31"))
        // Before the pattern's start, the first period's end.
        #expect(try store.nextPeriodStart(after: LogicalDay("2027-01-01")) == LogicalDay("2027-02-28"))
    }

    // MARK: - The period-end reminder

    private func riyadh(_ day: String, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let p = day.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
    }

    private func reminders(at now: Date) throws -> [PlannedNotification] {
        try NotificationPlanner(db: db, timeModel: timeModel, clock: FixedClock(now)).plan()
            .notifications.filter { $0.type == .shiftPattern }
    }

    @Test("The evening before a pattern's week ends, the app reminds the person to pick what runs next")
    func reminderFiresTheEveningBeforeThePeriodEnds() throws {
        let a = try store.save(threeNights())
        try store.use(a, today: LogicalDay("2026-10-22"))

        // The week from Wednesday 21 Oct ends on Tuesday 27th; the reminder is
        // at 18:00 that day.
        let planned = try reminders(at: riyadh("2026-10-26", 12))
        #expect(planned.map(\.identifier) == ["almanac.shift_pattern.2026-10-27"])
        #expect(planned.first?.fireAt == riyadh("2026-10-27", 18))
        #expect(planned.first?.body.contains("Three nights") == true)

        #expect(try reminders(at: riyadh("2026-10-23", 12)).isEmpty, "two days ahead is beyond 48 hours")
    }

    @Test("No reminder is planned with it switched off, or with no pattern running")
    func noReminderWhenOffOrIdle() throws {
        #expect(try reminders(at: riyadh("2026-10-26", 12)).isEmpty)
        let a = try store.save(threeNights())
        try store.use(a, today: LogicalDay("2026-10-22"))
        try setReminder(false)
        #expect(try reminders(at: riyadh("2026-10-26", 12)).isEmpty)
    }
}
