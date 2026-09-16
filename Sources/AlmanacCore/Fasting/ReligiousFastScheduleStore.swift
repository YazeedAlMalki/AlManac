import Foundation

/// One correction to a calculated fast day — §11.2's "calendar honesty":
/// the app's Hijri calculation is never treated as final.
public struct ManualCorrection: Sendable, Hashable, Codable {
    public let date: String
    /// `"add_fast"` or `"remove_fast"`.
    public let action: String
    public let reason: String?

    public init(date: String, action: String, reason: String? = nil) {
        self.date = date
        self.action = action
        self.reason = reason
    }
}

/// A `religious_fast_schedule` row read from storage.
public struct ReligiousFastSchedule: Sendable, Hashable, Identifiable {
    public let id: Int64
    /// `"ramadan"`, `"mon_thu"`, or `"white_days"`.
    public let scheduleType: String
    public let hijriYear: Int?
    public let startGregorianDate: String?
    public let endGregorianDate: String?
    public let isActive: Bool
    public let manualCorrections: [ManualCorrection]
    public let createdAt: Date
    public let updatedAt: Date
}

/// Religious fasting-day detection (§11.2) over `religious_fast_schedule`.
///
/// `scheduleType` drives *how* a date is matched, not just what's stored:
/// - `"ramadan"` matches against its own `startGregorianDate`/
///   `endGregorianDate` — a fixed span computed once (`ramadanRange`) when
///   the schedule row is created, not recomputed live on every check.
///   Ramadan happens once a year with clear boundaries, so a stored range
///   is the natural fit.
/// - `"mon_thu"` and `"white_days"` are standing, perpetually-recurring
///   rules (while `isActive`) — matched live against the date's weekday or
///   Hijri day-of-month, since there is no fixed span to store.
///
/// A manual correction always wins over the calculated result, in either
/// direction (`"add_fast"` or `"remove_fast"`) — §11.2's calendar-honesty
/// requirement that the app's own Hijri calculation is never final.
public struct ReligiousFastScheduleStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    @discardableResult
    public func createSchedule(scheduleType: String, hijriYear: Int? = nil,
                                startGregorianDate: String? = nil, endGregorianDate: String? = nil) throws -> Int64 {
        let now = nowText
        try db.run("""
        INSERT INTO religious_fast_schedule
            (scheduleType, hijriYear, startGregorianDate, endGregorianDate, isActive, manualCorrections, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, 1, '[]', ?, ?);
        """, [
            .text(scheduleType),
            hijriYear.map { SQLValue.integer(Int64($0)) } ?? .null,
            startGregorianDate.map { SQLValue.text($0) } ?? .null,
            endGregorianDate.map { SQLValue.text($0) } ?? .null,
            .text(now), .text(now)
        ])
        guard let row = try db.query("SELECT last_insert_rowid() as id;").first, let id = row.int("id") else {
            throw ReligiousFastScheduleStoreError.insertFailed
        }
        return id
    }

    public func deactivate(id: Int64) throws {
        try db.run("UPDATE religious_fast_schedule SET isActive = 0, updatedAt = ? WHERE id = ?;",
                    [.text(nowText), .integer(id)])
    }

    public func addManualCorrection(id: Int64, date: String, action: String, reason: String? = nil) throws {
        guard let existing = try schedule(id: id) else { throw ReligiousFastScheduleStoreError.notFound }
        let corrections = existing.manualCorrections + [ManualCorrection(date: date, action: action, reason: reason)]
        let json = encodeCorrections(corrections)
        try db.run("UPDATE religious_fast_schedule SET manualCorrections = ?, updatedAt = ? WHERE id = ?;",
                    [.text(json), .text(nowText), .integer(id)])
    }

    // MARK: - Read

    public func schedule(id: Int64) throws -> ReligiousFastSchedule? {
        try db.query("\(Self.columns) FROM religious_fast_schedule WHERE id = ?;",
                      [.integer(id)]).first.flatMap(rowToSchedule)
    }

    public func schedules(activeOnly: Bool = true) throws -> [ReligiousFastSchedule] {
        let sql = activeOnly
            ? "\(Self.columns) FROM religious_fast_schedule WHERE isActive = 1 ORDER BY id;"
            : "\(Self.columns) FROM religious_fast_schedule ORDER BY id;"
        return try db.query(sql).compactMap(rowToSchedule)
    }

    /// Is `date` (`"YYYY-MM-DD"`) a religious fast day, per every active
    /// schedule and every manual correction recorded against it?
    public func isFastDay(_ date: String) throws -> Bool {
        guard let parsed = Self.gregorianDate(from: date) else { return false }
        let active = try schedules(activeOnly: true)

        // A manual correction always wins. If more than one schedule has a
        // correction for the same date (unusual — corrections are normally
        // one-per-schedule-per-date), the most recently added one across all
        // of them applies.
        var override: ManualCorrection?
        for schedule in active {
            for correction in schedule.manualCorrections where correction.date == date {
                override = correction
            }
        }
        if let override { return override.action == "add_fast" }

        return active.contains { Self.matches($0, date: date, parsed: parsed) }
    }

    /// The Gregorian span of Hijri month 9 (Ramadan) in `hijriYear`, for
    /// populating a new `"ramadan"` schedule row's
    /// `startGregorianDate`/`endGregorianDate`.
    public static func ramadanRange(hijriYear: Int) -> (start: String, end: String)? {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = hijriYear
        comps.month = 9
        comps.day = 1
        guard let start = islamic.date(from: comps),
              let daysInMonth = islamic.range(of: .day, in: .month, for: start)?.count,
              let end = islamic.date(byAdding: .day, value: daysInMonth - 1, to: start) else { return nil }
        return (dateString(start), dateString(end))
    }

    // MARK: - Private

    private static func matches(_ schedule: ReligiousFastSchedule, date: String, parsed: Date) -> Bool {
        switch schedule.scheduleType {
        case "ramadan":
            guard let start = schedule.startGregorianDate, let end = schedule.endGregorianDate else { return false }
            return date >= start && date <= end
        case "mon_thu":
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let weekday = calendar.component(.weekday, from: parsed)
            return weekday == 2 || weekday == 5 // Monday, Thursday
        case "white_days":
            var islamic = Calendar(identifier: .islamicUmmAlQura)
            islamic.timeZone = TimeZone(identifier: "UTC")!
            let day = islamic.component(.day, from: parsed)
            return (13...15).contains(day)
        default:
            return false
        }
    }

    private static func gregorianDate(from dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let columns = """
        SELECT id, scheduleType, hijriYear, startGregorianDate, endGregorianDate, isActive,
               manualCorrections, createdAt, updatedAt
        """

    private func encodeCorrections(_ corrections: [ManualCorrection]) -> String {
        guard let data = try? JSONEncoder().encode(corrections),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private func rowToSchedule(_ row: Row) -> ReligiousFastSchedule? {
        guard let id = row.int("id"), let scheduleType = row.string("scheduleType"),
              let createdAt = row.string("createdAt").flatMap(iso8601ToDate),
              let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) else { return nil }

        let corrections: [ManualCorrection] = (row.string("manualCorrections") ?? "[]").data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([ManualCorrection].self, from: $0) } ?? []

        return ReligiousFastSchedule(
            id: id, scheduleType: scheduleType,
            hijriYear: row.int("hijriYear").map(Int.init),
            startGregorianDate: row.string("startGregorianDate"),
            endGregorianDate: row.string("endGregorianDate"),
            isActive: row.int("isActive") == 1,
            manualCorrections: corrections,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum ReligiousFastScheduleStoreError: Error, Sendable {
    case insertFailed
    case notFound
}
