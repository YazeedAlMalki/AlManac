import Foundation

/// One correction to a calculated fast day — §11.2's "calendar honesty":
/// the app's Hijri calculation is never treated as final.
public struct ManualCorrection: Sendable, Hashable, Codable {
    public let date: String
    /// `"add_fast"`, `"remove_fast"`, or `"clear"` — the last withdraws the
    /// user's earlier word on the date and hands it back to the calculation,
    /// while keeping the history of what they said (§11.2: "all manual
    /// corrections logged").
    public let action: String
    public let reason: String?
    /// When the correction was made. Optional because corrections written
    /// before it existed have none; those order as oldest. With it, "the most
    /// recent correction wins" means most recent in time rather than whichever
    /// schedule row happened to be read last.
    public let recordedAt: Date?

    public static let addFast = "add_fast"
    public static let removeFast = "remove_fast"
    public static let clear = "clear"

    public init(date: String, action: String, reason: String? = nil, recordedAt: Date? = nil) {
        self.date = date
        self.action = action
        self.reason = reason
        self.recordedAt = recordedAt
    }
}

/// Why a day is a religious fast day by the calendar — what the fasting screen
/// says it is, rather than only that it is.
public enum ReligiousFastKind: String, Sendable, Hashable, CaseIterable {
    case ramadan
    case monday
    case thursday
    case whiteDay = "white_day"

    public var label: String {
        switch self {
        case .ramadan: return localized("Ramadan")
        case .monday: return localized("Monday")
        case .thursday: return localized("Thursday")
        case .whiteDay: return localized("White Day")
        }
    }
}

/// A date in the Umm al-Qura calendar — the calendar §3 of
/// `docs/features/fasting.md` settled on, and the one `AdhanCalculator` reads
/// Ramadan from for its Isha rule.
public struct HijriDate: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let day: Int

    static let monthNames = [
        "Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Ula", "Jumada al-Akhirah",
        "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah"
    ]

    /// The month's name in the language the app runs in. `monthNames` stays
    /// English: it is the key, and the order is the calendar's.
    public var monthName: String {
        (1...12).contains(month) ? localized(Self.monthNames[month - 1]) : "\(month)"
    }

    /// "17 Ramadan 1448 AH"; in Arabic, "17 رمضان 1448 هـ".
    public var text: String { localized("%@ %@ %@ AH", "\(day)", monthName, "\(year)") }

    /// The Umm al-Qura date of a `"YYYY-MM-DD"` civil date.
    public init?(gregorian date: String) {
        guard let parsed = ReligiousFastScheduleStore.gregorianDate(from: date) else { return nil }
        let parts = ReligiousFastScheduleStore.islamicCalendar.dateComponents([.year, .month, .day], from: parsed)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Eid al-Fitr (1 Shawwal), Eid al-Adha (10 Dhu al-Hijjah) and the days of
    /// Tashreeq (11–13 Dhu al-Hijjah). Fasting on them is prohibited, so a
    /// recurring voluntary rule must never make them fast days — White Days'
    /// 13th falls on one every Dhu al-Hijjah, and a Monday or Thursday can.
    public var isProhibitedFastDay: Bool {
        (month == 10 && day == 1) || (month == 12 && (10...13).contains(day))
    }
}

/// Everything known about one date: what the calendar says, what the user
/// said, and the answer that wins.
public struct ReligiousFastDayStatus: Sendable, Hashable {
    public let date: String
    /// The answer: a manual correction when there is one, else the calculation.
    public let isFastDay: Bool
    /// What the active schedules alone say, before any correction.
    public let calculatedIsFastDay: Bool
    /// Every calendar reason that applies, in a stable order. Empty when the
    /// calculation says no (including on a prohibited day).
    public let kinds: [ReligiousFastKind]
    /// The correction in force, when the user's word decides this date.
    public let correction: ManualCorrection?
    public let hijri: HijriDate?

    /// True when the user's correction disagrees with the calculation — the
    /// state a screen should label, since it is the one the app did not work
    /// out for itself.
    public var isCorrected: Bool { correction != nil && isFastDay != calculatedIsFastDay }
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
///
/// A fourth `scheduleType`, `"manual"`, carries corrections for days no rule
/// covers (a make-up day, Ashura, Arafah). It matches nothing by itself; it is
/// where `setManualFastDay` writes, so every correction the user makes lives on
/// one row in the order they made them.
public struct ReligiousFastScheduleStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public static let ramadan = "ramadan"
    public static let monThu = "mon_thu"
    public static let whiteDays = "white_days"
    public static let manual = "manual"

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

    public func activate(id: Int64) throws {
        try db.run("UPDATE religious_fast_schedule SET isActive = 1, updatedAt = ? WHERE id = ?;",
                    [.text(nowText), .integer(id)])
    }

    public func addManualCorrection(id: Int64, date: String, action: String, reason: String? = nil) throws {
        guard let existing = try schedule(id: id) else { throw ReligiousFastScheduleStoreError.notFound }
        let correction = ManualCorrection(date: date, action: action, reason: reason, recordedAt: clock.now)
        let corrections = existing.manualCorrections + [correction]
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
        try status(date).isFastDay
    }

    /// The whole answer for `date`: the calculation, the correction, and which
    /// one wins. A manual correction always wins (§11.2's calendar honesty);
    /// among several for the same date, the most recently made one does, and a
    /// `"clear"` hands the date back to the calculation.
    public func status(_ date: String) throws -> ReligiousFastDayStatus {
        try status(date, active: try schedules(activeOnly: true))
    }

    /// `status` for `days` consecutive dates from `date` — the fasting screen's
    /// "coming up" list — reading the schedules once rather than per day.
    public func statuses(from date: String, days: Int) throws -> [ReligiousFastDayStatus] {
        guard let start = Self.gregorianDate(from: date) else { return [] }
        let active = try schedules(activeOnly: true)
        return try (0..<max(0, days)).compactMap { offset in
            guard let day = Self.utcCalendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return try status(Self.dateString(day), active: active)
        }
    }

    private func status(_ date: String, active: [ReligiousFastSchedule]) throws -> ReligiousFastDayStatus {
        let hijri = HijriDate(gregorian: date)
        guard let parsed = Self.gregorianDate(from: date) else {
            return ReligiousFastDayStatus(date: date, isFastDay: false, calculatedIsFastDay: false,
                                          kinds: [], correction: nil, hijri: nil)
        }

        var winning: ManualCorrection?
        for schedule in active {
            for correction in schedule.manualCorrections where correction.date == date {
                let incoming = correction.recordedAt ?? .distantPast
                if incoming >= (winning?.recordedAt ?? .distantPast) { winning = correction }
            }
        }
        if winning?.action == ManualCorrection.clear { winning = nil }

        var kinds: [ReligiousFastKind] = []
        for schedule in active {
            for kind in Self.kinds(schedule, date: date, parsed: parsed, hijri: hijri) where !kinds.contains(kind) {
                kinds.append(kind)
            }
        }
        kinds.sort { ReligiousFastKind.allCases.firstIndex(of: $0)! < ReligiousFastKind.allCases.firstIndex(of: $1)! }
        let calculated = !kinds.isEmpty
        let answer = winning.map { $0.action == ManualCorrection.addFast } ?? calculated
        return ReligiousFastDayStatus(date: date, isFastDay: answer, calculatedIsFastDay: calculated,
                                      kinds: kinds, correction: winning, hijri: hijri)
    }

    // MARK: - The user's choices

    /// Whether Ramadan is observed: the newest Ramadan row's own flag, and on
    /// when there is none yet — §6.13's "day pre-typed Religious Fast by
    /// Ramadan schedule (user-correctable)".
    public func isRamadanEnabled() throws -> Bool {
        try schedules(activeOnly: false)
            .filter { $0.scheduleType == Self.ramadan }
            .max { ($0.hijriYear ?? 0) < ($1.hijriYear ?? 0) }?.isActive ?? true
    }

    /// Makes sure this Hijri year's Ramadan (when it has not yet ended) and next
    /// year's have a schedule row, so Ramadan arrives without anyone having to
    /// remember to set it up — the absence of exactly this is why no fast day
    /// was ever detected in the running app. A new row inherits the user's
    /// last choice, so turning Ramadan off is not undone by the next year
    /// arriving. Never creates a past year's row: that would re-label days the
    /// user has already lived.
    @discardableResult
    public func ensureRamadanSchedules(around date: String) throws -> [Int64] {
        guard let hijri = HijriDate(gregorian: date) else { return [] }
        let existing = try schedules(activeOnly: false).filter { $0.scheduleType == Self.ramadan }
        let enabled = try isRamadanEnabled()
        var created: [Int64] = []
        for year in [hijri.year, hijri.year + 1] {
            guard !existing.contains(where: { $0.hijriYear == year }),
                  let range = Self.ramadanRange(hijriYear: year), range.end >= date else { continue }
            let id = try createSchedule(scheduleType: Self.ramadan, hijriYear: year,
                                        startGregorianDate: range.start, endGregorianDate: range.end)
            if !enabled { try deactivate(id: id) }
            created.append(id)
        }
        return created
    }

    /// Turns Ramadan on or off from `date` onward. Rows for a Ramadan that has
    /// already ended keep their flag: switching off this year does not
    /// retroactively un-fast last year.
    public func setRamadanEnabled(_ enabled: Bool, asOf date: String) throws {
        try ensureRamadanSchedules(around: date)
        for schedule in try schedules(activeOnly: false)
        where schedule.scheduleType == Self.ramadan && (schedule.endGregorianDate ?? "") >= date {
            if enabled { try activate(id: schedule.id) } else { try deactivate(id: schedule.id) }
        }
    }

    /// Whether a standing rule (`"mon_thu"` or `"white_days"`) is on.
    public func isRecurringEnabled(_ scheduleType: String) throws -> Bool {
        try schedules(activeOnly: true).contains { $0.scheduleType == scheduleType }
    }

    /// Turns a standing rule on (reactivating its row, or creating one) or off.
    public func setRecurringEnabled(_ scheduleType: String, enabled: Bool) throws {
        precondition(scheduleType == Self.monThu || scheduleType == Self.whiteDays,
                     "only the two standing rules are switched this way")
        let rows = try schedules(activeOnly: false).filter { $0.scheduleType == scheduleType }
        if enabled {
            guard !rows.contains(where: \.isActive) else { return }
            if let latest = rows.last { try activate(id: latest.id) } else {
                try createSchedule(scheduleType: scheduleType)
            }
        } else {
            for row in rows where row.isActive { try deactivate(id: row.id) }
        }
    }

    /// The user's word on one date: a fast (`true`), not a fast (`false`), or
    /// back to whatever the calendar says (`nil`). Written to the `"manual"`
    /// row so it survives a rule being switched off, and logged, never
    /// overwritten.
    public func setManualFastDay(_ date: String, isFast: Bool?, reason: String? = nil) throws {
        let id = try manualScheduleID()
        let action = isFast.map { $0 ? ManualCorrection.addFast : ManualCorrection.removeFast } ?? ManualCorrection.clear
        try addManualCorrection(id: id, date: date, action: action, reason: reason)
    }

    private func manualScheduleID() throws -> Int64 {
        if let existing = try schedules(activeOnly: true).first(where: { $0.scheduleType == Self.manual }) {
            return existing.id
        }
        return try createSchedule(scheduleType: Self.manual)
    }

    /// The Gregorian span of Hijri month 9 (Ramadan) in `hijriYear`, for
    /// populating a new `"ramadan"` schedule row's
    /// `startGregorianDate`/`endGregorianDate`.
    public static func ramadanRange(hijriYear: Int) -> (start: String, end: String)? {
        let islamic = islamicCalendar
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

    /// The calendar reasons one schedule gives for `date`. Ramadan is a stored
    /// span; the two standing rules are matched live, and never on a day on
    /// which fasting is prohibited.
    private static func kinds(_ schedule: ReligiousFastSchedule, date: String, parsed: Date,
                              hijri: HijriDate?) -> [ReligiousFastKind] {
        switch schedule.scheduleType {
        case ramadan:
            guard let start = schedule.startGregorianDate, let end = schedule.endGregorianDate,
                  date >= start && date <= end else { return [] }
            return [.ramadan]
        case monThu:
            guard hijri?.isProhibitedFastDay != true else { return [] }
            switch utcCalendar.component(.weekday, from: parsed) {
            case 2: return [.monday]
            case 5: return [.thursday]
            default: return []
            }
        case whiteDays:
            guard let hijri, !hijri.isProhibitedFastDay, (13...15).contains(hijri.day) else { return [] }
            return [.whiteDay]
        default:
            return []
        }
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let islamicCalendar: Calendar = {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func gregorianDate(from dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
