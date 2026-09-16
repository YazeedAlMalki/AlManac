import Foundation

/// A shift schedule not yet written to storage. Spec §5.5 `shift_schedule` —
/// just a named, activatable container; the actual per-day timing lives on
/// `shift_occurrence`.
public struct ShiftScheduleDraft: Sendable {
    public var name: String
    public var isActive: Bool

    public init(name: String = "My Schedule", isActive: Bool = true) {
        self.name = name
        self.isActive = isActive
    }
}

/// One dated shift occurrence not yet written to storage. Spec §5.5
/// `shift_occurrence` — the row that actually carries a day's shift timing
/// and, via `expectedSleepWindowStart`, the "intended sleep" instant that
/// `CaffeineLogStore` computes `caffeineContext` against.
public struct ShiftOccurrenceDraft: Sendable {
    public var scheduleId: Int64
    public var date: String  // YYYY-MM-DD
    public var shiftType: ShiftType
    public var shiftStartTime: Date?
    public var shiftEndTime: Date?
    public var expectedSleepWindowStart: Date?
    public var expectedSleepWindowEnd: Date?
    public var expectedWakeTime: Date?
    public var isManualOverride: Bool
    public var recurrencePatternId: Int64?
    public var notes: String?

    public init(scheduleId: Int64, date: String, shiftType: ShiftType,
                shiftStartTime: Date? = nil, shiftEndTime: Date? = nil,
                expectedSleepWindowStart: Date? = nil, expectedSleepWindowEnd: Date? = nil,
                expectedWakeTime: Date? = nil, isManualOverride: Bool = false,
                recurrencePatternId: Int64? = nil, notes: String? = nil) {
        self.scheduleId = scheduleId
        self.date = date
        self.shiftType = shiftType
        self.shiftStartTime = shiftStartTime
        self.shiftEndTime = shiftEndTime
        self.expectedSleepWindowStart = expectedSleepWindowStart
        self.expectedSleepWindowEnd = expectedSleepWindowEnd
        self.expectedWakeTime = expectedWakeTime
        self.isManualOverride = isManualOverride
        self.recurrencePatternId = recurrencePatternId
        self.notes = notes
    }
}

/// A recurrence pattern not yet written to storage. Spec §5.5
/// `shift_recurrence_pattern` — the rule (e.g. "4 on, 4 off") that a run of
/// `shift_occurrence` rows is generated from. This store does not expand
/// patterns into occurrences itself; it only persists the pattern row so
/// generated occurrences have something to link `recurrencePatternId` to.
public struct ShiftRecurrencePatternDraft: Sendable {
    public var scheduleId: Int64
    public var patternType: String
    public var shiftSequence: String
    public var startDate: String  // YYYY-MM-DD
    public var endDate: String?

    public init(scheduleId: Int64, patternType: String, shiftSequence: String,
                startDate: String, endDate: String? = nil) {
        self.scheduleId = scheduleId
        self.patternType = patternType
        self.shiftSequence = shiftSequence
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// A shift occurrence read from storage.
public struct ShiftOccurrenceRecord: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let scheduleId: Int64
    public let date: String
    public let shiftType: ShiftType
    public let shiftStartTime: Date?
    public let shiftEndTime: Date?
    public let expectedSleepWindowStart: Date?
    public let expectedSleepWindowEnd: Date?
    public let expectedWakeTime: Date?
    public let isManualOverride: Bool
    public let recurrencePatternId: Int64?
    public let notes: String?
    public let createdAt: Date
}

/// Minimal persistence for `shift_schedule` / `shift_occurrence` (spec §5.5).
///
/// This is intentionally small: creating schedules, logging dated
/// occurrences, and looking up the occurrence (or just the intended-sleep
/// instant) for a given date. There is no recurrence-pattern *expansion*
/// here — `shift_recurrence_pattern` rows are written by whatever UI or
/// import path generates them, and each generated day is expected to land
/// as its own `shift_occurrence` row referencing that pattern via
/// `recurrencePatternId`, exactly as the schema models it.
public struct ShiftScheduleStore: @unchecked Sendable {
    let db: Database

    public init(db: Database) {
        self.db = db
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    // MARK: - Write

    @discardableResult
    public func createSchedule(_ draft: ShiftScheduleDraft) throws -> Int64 {
        let now = iso(Date())
        try db.run("""
        INSERT INTO shift_schedule (name, isActive, createdAt, updatedAt)
        VALUES (?, ?, ?, ?);
        """, [
            .text(draft.name),
            .integer(draft.isActive ? 1 : 0),
            .text(now),
            .text(now)
        ])
        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw ShiftScheduleStoreError.insertFailed
        }
        return id
    }

    @discardableResult
    public func logOccurrence(_ draft: ShiftOccurrenceDraft) throws -> Int64 {
        try db.run("""
        INSERT INTO shift_occurrence
            (scheduleId, date, shiftType, shiftStartTime, shiftEndTime,
             expectedSleepWindowStart, expectedSleepWindowEnd, expectedWakeTime,
             isManualOverride, recurrencePatternId, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .integer(draft.scheduleId),
            .text(draft.date),
            .text(draft.shiftType.rawValue),
            draft.shiftStartTime.map { SQLValue.text(iso($0)) } ?? .null,
            draft.shiftEndTime.map { SQLValue.text(iso($0)) } ?? .null,
            draft.expectedSleepWindowStart.map { SQLValue.text(iso($0)) } ?? .null,
            draft.expectedSleepWindowEnd.map { SQLValue.text(iso($0)) } ?? .null,
            draft.expectedWakeTime.map { SQLValue.text(iso($0)) } ?? .null,
            .integer(draft.isManualOverride ? 1 : 0),
            draft.recurrencePatternId.map { SQLValue.integer($0) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(iso(Date()))
        ])
        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw ShiftScheduleStoreError.insertFailed
        }
        return id
    }

    @discardableResult
    public func createRecurrencePattern(_ draft: ShiftRecurrencePatternDraft) throws -> Int64 {
        try db.run("""
        INSERT INTO shift_recurrence_pattern
            (scheduleId, patternType, shiftSequence, startDate, endDate, createdAt)
        VALUES (?, ?, ?, ?, ?, ?);
        """, [
            .integer(draft.scheduleId),
            .text(draft.patternType),
            .text(draft.shiftSequence),
            .text(draft.startDate),
            draft.endDate.map { SQLValue.text($0) } ?? .null,
            .text(iso(Date()))
        ])
        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw ShiftScheduleStoreError.insertFailed
        }
        return id
    }

    // MARK: - Read

    /// The shift occurrence for a given date, if one has been logged.
    /// Nil when the user has no shift schedule for that day — the ordinary
    /// case, and one that must stay fully supported (spec §6.11).
    public func occurrence(for date: String) throws -> ShiftOccurrenceRecord? {
        try db.query("""
        SELECT id, scheduleId, date, shiftType, shiftStartTime, shiftEndTime,
               expectedSleepWindowStart, expectedSleepWindowEnd, expectedWakeTime,
               isManualOverride, recurrencePatternId, notes, createdAt
        FROM shift_occurrence WHERE date = ?
        ORDER BY id DESC LIMIT 1;
        """, [.text(date)]).first.flatMap(rowToOccurrence)
    }

    /// The intended-sleep instant for a date, derived from that day's shift
    /// occurrence. Returns nil with no crash when there is no occurrence for
    /// the date, or when one exists but never had a sleep window recorded —
    /// callers (e.g. `CaffeineLogStore`) treat nil as "unclassified" rather
    /// than falling back to a fixed clock time.
    public func intendedSleepTimestamp(for date: String) throws -> Date? {
        try occurrence(for: date)?.expectedSleepWindowStart
    }

    // MARK: - Private

    private func rowToOccurrence(_ row: Row) -> ShiftOccurrenceRecord? {
        guard let id = row.int("id"),
              let scheduleId = row.int("scheduleId"),
              let date = row.string("date"),
              let shiftTypeRaw = row.string("shiftType"),
              let shiftType = ShiftType(rawValue: shiftTypeRaw) else { return nil }

        return ShiftOccurrenceRecord(
            id: id,
            scheduleId: scheduleId,
            date: date,
            shiftType: shiftType,
            shiftStartTime: row.string("shiftStartTime").flatMap(iso8601ToDate),
            shiftEndTime: row.string("shiftEndTime").flatMap(iso8601ToDate),
            expectedSleepWindowStart: row.string("expectedSleepWindowStart").flatMap(iso8601ToDate),
            expectedSleepWindowEnd: row.string("expectedSleepWindowEnd").flatMap(iso8601ToDate),
            expectedWakeTime: row.string("expectedWakeTime").flatMap(iso8601ToDate),
            isManualOverride: (row.int("isManualOverride") ?? 0) != 0,
            recurrencePatternId: row.int("recurrencePatternId"),
            notes: row.string("notes"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }
}

public enum ShiftScheduleStoreError: Error {
    case insertFailed
}
