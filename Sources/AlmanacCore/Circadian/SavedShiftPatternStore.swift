import Foundation

/// A saved shift pattern not yet written to storage (shifts-profile spec,
/// section 2): a name, blocks of days on one shift, a start date the person
/// picks, a weekly or monthly cadence counted from it, and a run length in
/// nights, which may be left unset.
public struct SavedShiftPatternDraft: Sendable, Hashable {
    public var name: String
    public var blocks: [ShiftBlock]
    public var startDate: LogicalDay
    public var cadence: ShiftCadence
    public var runLengthNights: Int?

    public init(name: String, blocks: [ShiftBlock], startDate: LogicalDay, cadence: ShiftCadence,
                runLengthNights: Int? = nil) {
        self.name = name
        self.blocks = blocks
        self.startDate = startDate
        self.cadence = cadence
        self.runLengthNights = runLengthNights
    }
}

/// A saved shift pattern read from storage.
public struct SavedShiftPattern: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let scheduleId: Int64
    public let name: String
    public let blocks: [ShiftBlock]
    public let startDate: LogicalDay
    public let cadence: ShiftCadence
    public let runLengthNights: Int?
}

public enum SavedShiftPatternError: Error, Equatable {
    case missingName
    case noBlocks
    case blockWithNoDays
    case runLengthNotPositive
    case unknownPattern(Int64)
}

/// Saved shift patterns, and which one is running.
///
/// Patterns sit beside the Rotation entry, which is unchanged: a rotation is
/// written once, to an end date; a saved pattern keeps running, one week or
/// month at a time, until the person picks another.
public struct SavedShiftPatternStore: @unchecked Sendable {
    let db: Database
    let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel) {
        self.db = db
        self.timeModel = timeModel
    }

    private var shifts: ShiftScheduleStore { ShiftScheduleStore(db: db) }

    private func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    // MARK: - Patterns

    /// Saves `draft` into the schedule the shift editor writes into, and
    /// returns its id. Saving does not start it: nothing changes until the
    /// person picks a pattern to use.
    @discardableResult
    public func save(_ draft: SavedShiftPatternDraft) throws -> Int64 {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SavedShiftPatternError.missingName }
        guard !draft.blocks.isEmpty else { throw SavedShiftPatternError.noBlocks }
        guard draft.blocks.allSatisfy({ $0.days > 0 }) else { throw SavedShiftPatternError.blockWithNoDays }
        if let run = draft.runLengthNights, run <= 0 { throw SavedShiftPatternError.runLengthNotPositive }

        let blocks = String(decoding: try JSONEncoder().encode(draft.blocks), as: UTF8.self)
        let scheduleId = try shifts.defaultScheduleId()
        let stamp = now()
        try db.run("""
        INSERT INTO saved_shift_pattern
            (scheduleId, name, blocks, startDate, cadence, runLengthNights, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .integer(scheduleId), .text(name), .text(blocks), .text(draft.startDate.value),
            .text(draft.cadence.rawValue),
            draft.runLengthNights.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(stamp), .text(stamp)
        ])
        guard let id = try db.query("SELECT last_insert_rowid() AS id;").first?.int("id") else {
            throw ShiftScheduleStoreError.insertFailed
        }
        return id
    }

    /// Sets a pattern's run length in nights; nil goes back to the default.
    public func setRunLength(_ nights: Int?, for id: Int64) throws {
        if let nights, nights <= 0 { throw SavedShiftPatternError.runLengthNotPositive }
        guard try pattern(id: id) != nil else { throw SavedShiftPatternError.unknownPattern(id) }
        try db.run("UPDATE saved_shift_pattern SET runLengthNights = ?, updatedAt = ? WHERE id = ?;",
                   [nights.map { SQLValue.integer(Int64($0)) } ?? .null, .text(now()), .integer(id)])
    }

    /// Every saved pattern, oldest first.
    public func patterns() throws -> [SavedShiftPattern] {
        try db.query("""
        SELECT id, scheduleId, name, blocks, startDate, cadence, runLengthNights
        FROM saved_shift_pattern ORDER BY id;
        """).compactMap(Self.pattern(from:))
    }

    public func pattern(id: Int64) throws -> SavedShiftPattern? {
        try db.query("""
        SELECT id, scheduleId, name, blocks, startDate, cadence, runLengthNights
        FROM saved_shift_pattern WHERE id = ?;
        """, [.integer(id)]).first.flatMap(Self.pattern(from:))
    }

    private static func pattern(from row: Row) -> SavedShiftPattern? {
        guard let id = row.int("id"), let scheduleId = row.int("scheduleId"),
              let name = row.string("name"), let startDate = row.string("startDate"),
              let cadence = row.string("cadence").flatMap(ShiftCadence.init(rawValue:)),
              let blocks = row.string("blocks").flatMap({
                  try? JSONDecoder().decode([ShiftBlock].self, from: Data($0.utf8))
              }) else { return nil }
        return SavedShiftPattern(id: id, scheduleId: scheduleId, name: name, blocks: blocks,
                                 startDate: LogicalDay(startDate), cadence: cadence,
                                 runLengthNights: row.int("runLengthNights").map(Int.init))
    }
}

/// Which saved pattern is running, counted from which day, and which one the
/// person set to run next.
public struct SavedShiftPatternSelection: Sendable, Hashable {
    public var currentId: Int64?
    /// The day the running pattern's weeks or months count from: its own start
    /// date when the person picked it, or the period end it took over at.
    public var anchor: LogicalDay?
    public var nextId: Int64?
    /// Set only while the period-end reminder is off: the day the next pattern
    /// starts by itself.
    public var nextStartsOn: LogicalDay?

    public static let none = SavedShiftPatternSelection()
}

/// The note a one-day entry keeps when it falls inside a saved pattern: the
/// pattern's shift for that day. Stored in English and read back by `shift`,
/// so the screen can show it in the app's language.
public enum SavedShiftPatternNote {
    static let prefix = "Saved pattern: "

    public static func text(for shift: ShiftType) -> String { prefix + shift.rawValue }

    public static func shift(in notes: String?) -> ShiftType? {
        guard let notes, notes.hasPrefix(prefix) else { return nil }
        return ShiftType(rawValue: String(notes.dropFirst(prefix.count)))
    }
}

extension SavedShiftPatternStore {
    /// How far ahead a running pattern's shifts are written: four weeks, the
    /// same as the Rotation entry's default, so the Shifts & rhythm week and
    /// the 48-hour reminders always have shifts to read.
    public static let horizonDays = 28

    // MARK: - Selection

    public func selection() throws -> SavedShiftPatternSelection {
        guard let row = try db.query("""
        SELECT currentSavedPatternId, currentSavedPatternAnchor, nextSavedPatternId, nextSavedPatternStartsOn
        FROM shift_schedule WHERE isActive = 1 ORDER BY id DESC LIMIT 1;
        """).first else { return .none }
        return SavedShiftPatternSelection(
            currentId: row.int("currentSavedPatternId"),
            anchor: row.string("currentSavedPatternAnchor").map(LogicalDay.init),
            nextId: row.int("nextSavedPatternId"),
            nextStartsOn: row.string("nextSavedPatternStartsOn").map(LogicalDay.init))
    }

    private func write(_ selection: SavedShiftPatternSelection) throws {
        let scheduleId = try shifts.defaultScheduleId()
        try db.run("""
        UPDATE shift_schedule
        SET currentSavedPatternId = ?, currentSavedPatternAnchor = ?,
            nextSavedPatternId = ?, nextSavedPatternStartsOn = ?, updatedAt = ?
        WHERE id = ?;
        """, [
            selection.currentId.map { SQLValue.integer($0) } ?? .null,
            selection.anchor.map { SQLValue.text($0.value) } ?? .null,
            selection.nextId.map { SQLValue.integer($0) } ?? .null,
            selection.nextStartsOn.map { SQLValue.text($0.value) } ?? .null,
            .text(now()), .integer(scheduleId)
        ])
    }

    /// The person picks `id` to run now. It runs from its own start date, and
    /// its shifts replace the app's from today on; days before today, and
    /// days the person entered one at a time, are left as they are.
    public func use(_ id: Int64, today: LogicalDay) throws {
        guard let pattern = try pattern(id: id) else { throw SavedShiftPatternError.unknownPattern(id) }
        var selection = try selection()
        selection.currentId = id
        selection.anchor = pattern.startDate
        if selection.nextId == id { selection.nextId = nil }
        selection.nextStartsOn = nil
        try db.transaction {
            try write(selection)
            try refresh(today: today, force: true)
        }
    }

    /// The pattern to run after the current one, or nil for none. With the
    /// period-end reminder on it does not start by itself: the reminder asks.
    public func setNext(_ id: Int64?, today: LogicalDay) throws {
        if let id, try pattern(id: id) == nil { throw SavedShiftPatternError.unknownPattern(id) }
        var selection = try selection()
        selection.nextId = id == selection.currentId ? nil : id
        selection.nextStartsOn = nil
        try db.transaction {
            try write(selection)
            try refresh(today: today)
        }
    }

    // MARK: - Period end

    /// Switches the period-end reminder on or off and brings the running
    /// pattern up to date in the same step. Every screen that changes this
    /// reminder goes through here: left to the next refresh, a next pattern
    /// would be counted from a later today and start a whole period late.
    public func setReminder(_ on: Bool, today: LogicalDay) throws {
        try db.transaction {
            try NotificationRuleStore(db: db).setEnabled(on, for: .shiftPattern)
            try refresh(today: today, force: false)
        }
    }

    /// The first day of the running pattern's next week or month, after
    /// `today`. Nil with no pattern running.
    public func nextPeriodStart(after today: LogicalDay) throws -> LogicalDay? {
        let selection = try selection()
        guard let id = selection.currentId, let anchor = selection.anchor,
              let pattern = try pattern(id: id) else { return nil }
        return Self.nextPeriodStart(pattern.cadence, anchor: anchor, after: today)
    }

    static func nextPeriodStart(_ cadence: ShiftCadence, anchor: LogicalDay, after today: LogicalDay) -> LogicalDay {
        guard let period = cadence.period(containing: today, from: anchor) else {
            return cadence.periodStart(1, from: anchor)
        }
        return period.nextStart
    }

    // MARK: - Writing the running pattern's shifts

    /// Brings the running pattern's shifts up to date as of `today`, four
    /// weeks ahead. Safe to call any number of times: a day that already has
    /// the right shift is not written again.
    ///
    /// At each period end the current pattern keeps running, unless the
    /// period-end reminder is off and a next pattern is set: then the next one
    /// starts at the period end, counting its weeks or months from there.
    ///
    /// A day the person entered by hand keeps their entry and gets the
    /// pattern's shift as a note. A day a Rotation entry wrote keeps the
    /// rotation's shift, unless `force` (the person just picked this pattern).
    /// A day before today is never rewritten.
    public func refresh(today: LogicalDay) throws {
        try db.transaction { try refresh(today: today, force: false) }
    }

    private func refresh(today: LogicalDay, force: Bool) throws {
        var selection = try selection()
        let reminderOn = try NotificationRuleStore(db: db).isEnabled(.shiftPattern)

        // A next pattern whose start day has come takes over.
        if let startsOn = selection.nextStartsOn, let nextId = selection.nextId, today >= startsOn {
            selection = SavedShiftPatternSelection(currentId: nextId, anchor: startsOn)
            try write(selection)
        }
        guard let currentId = selection.currentId, let anchor = selection.anchor,
              let current = try pattern(id: currentId) else { return }

        // With the reminder off, a next pattern starts at the period end;
        // with it on, nothing changes until the person picks.
        let startsOn: LogicalDay? = (!reminderOn && selection.nextId != nil)
            ? selection.nextStartsOn ?? Self.nextPeriodStart(current.cadence, anchor: anchor, after: today)
            : nil
        if startsOn != selection.nextStartsOn {
            selection.nextStartsOn = startsOn
            try write(selection)
        }

        var horizonEnd = today
        for _ in 1..<Self.horizonDays { horizonEnd = timeModel.day(after: horizonEnd) ?? horizonEnd }

        let firstDay = force ? anchor : max(anchor, today)
        if let startsOn, let nextId = selection.nextId, let next = try pattern(id: nextId) {
            if let lastOfCurrent = timeModel.day(before: startsOn), lastOfCurrent >= firstDay {
                try write(current, anchor: anchor, from: firstDay, through: min(lastOfCurrent, horizonEnd),
                          today: today, force: force)
            }
            if startsOn <= horizonEnd {
                try write(next, anchor: startsOn, from: max(startsOn, today), through: horizonEnd,
                          today: today, force: false)
            }
        } else {
            try write(current, anchor: anchor, from: firstDay, through: horizonEnd, today: today, force: force)
        }
    }

    private func write(_ pattern: SavedShiftPattern, anchor: LogicalDay, from first: LogicalDay,
                       through last: LogicalDay, today: LogicalDay, force: Bool) throws {
        guard first <= last else { return }
        let draft = ShiftRecurrencePatternDraft(scheduleId: pattern.scheduleId, blocks: pattern.blocks,
                                                cadence: pattern.cadence, startDate: anchor.value,
                                                savedPatternId: pattern.id)
        let ruleId = try ruleId(for: draft)
        for day in try ShiftPatternExpander.occurrences(for: draft, patternId: ruleId, through: last,
                                                        timeModel: timeModel)
        where LogicalDay(day.date) >= first {
            guard let existing = try shifts.newestSource(on: day.date) else {
                try shifts.logOccurrence(day)
                continue
            }
            // A day before today is history: not its shift, and not the note
            // of whichever pattern ran then.
            if LogicalDay(day.date) < today { continue }
            let record = existing.record
            if record.isManualOverride {
                // Their entry wins. The note is only ever the pattern's: a
                // note the person or anything else wrote is left alone.
                let note = SavedShiftPatternNote.text(for: day.shiftType)
                if record.notes != note, record.notes == nil || SavedShiftPatternNote.shift(in: record.notes) != nil {
                    try shifts.setNotes(note, onOccurrence: record.id)
                }
                continue
            }
            if record.recurrencePatternId == ruleId, record.shiftType == day.shiftType { continue }
            if existing.savedPatternId == nil, !force { continue }
            try shifts.logOccurrence(day)
        }
    }

    /// The rule row a pattern's shifts point at, from `anchor`: reused when
    /// one exists, so a refresh adds no rows.
    private func ruleId(for draft: ShiftRecurrencePatternDraft) throws -> Int64 {
        if let id = try db.query("""
            SELECT id FROM shift_recurrence_pattern
            WHERE savedPatternId = ? AND startDate = ? AND patternType = ? AND shiftSequence = ?
            ORDER BY id DESC LIMIT 1;
            """, [.integer(draft.savedPatternId ?? 0), .text(draft.startDate), .text(draft.patternType),
                  .text(draft.shiftSequence)]).first?.int("id") {
            return id
        }
        return try shifts.createRecurrencePattern(draft)
    }
}
