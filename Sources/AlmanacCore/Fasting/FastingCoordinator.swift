import Foundation

/// Where one religious fast day stands at a given instant — what the fasting
/// screen and the widget say, computed in one place so they cannot disagree.
public enum ReligiousFastPhase: Sendable, Hashable {
    case notAFastDay
    /// A fast day with no prayer times cached for it: no location yet, or the
    /// cache has not been built. The screen says so rather than inventing a
    /// window.
    case prayerTimesUnavailable
    /// Suhoor time: the fast begins at `fajr`.
    case beforeFajr(fajr: Date, maghrib: Date)
    /// Fasting since `fajr`, until `maghrib`.
    case fasting(fajr: Date, maghrib: Date)
    /// Broken by an intake at `at`, before `maghrib`.
    case broken(at: Date, maghrib: Date)
    /// Kept: Maghrib has come.
    case kept(maghrib: Date)
}

/// One calendar date's religious-fasting picture.
public struct ReligiousFastDay: Sendable, Hashable {
    public let date: String
    public let status: ReligiousFastDayStatus
    /// That date's cached times; empty when there are none.
    public let prayerTimes: [PrayerTime]
    public let session: FastingSession?

    public var fajr: Date? { prayerTimes.first { $0.name == "fajr" }?.timestamp }
    public var maghrib: Date? { prayerTimes.first { $0.name == "maghrib" }?.timestamp }

    /// Fajr to Maghrib, in hours — the length of the day's fast.
    public var fastLengthHours: Double? {
        guard let fajr, let maghrib, maghrib > fajr else { return nil }
        return maghrib.timeIntervalSince(fajr) / 3600
    }

    public func phase(at now: Date) -> ReligiousFastPhase {
        guard status.isFastDay else { return .notAFastDay }
        guard let fajr, let maghrib else { return .prayerTimesUnavailable }
        if now < fajr { return .beforeFajr(fajr: fajr, maghrib: maghrib) }
        if let end = session?.endTimestamp, end < maghrib { return .broken(at: end, maghrib: maghrib) }
        if now >= maghrib { return .kept(maghrib: maghrib) }
        return .fasting(fajr: fajr, maghrib: maghrib)
    }
}

/// The one call that makes fasting state true, and the reads a screen needs.
///
/// **Calendar dates, not logical days, for religious fasting.** A religious
/// fast is Fajr→Maghrib of one civil date, and Fajr can fall before the app's
/// 04:00 logical-day boundary (Riyadh's is 03:35 in June). Keyed by logical day,
/// a fast whose Fajr is 03:40 was looked for under the previous day. The
/// session's `logicalDay` column holds this calendar date for religious
/// sessions — the date the fast belongs to — which is what every reader of it
/// already asked by.
///
/// `refresh` derives yesterday as well as today: until the app is opened after
/// Maghrib, yesterday's fast is still open, and only a pass over it can close it
/// at the right instant rather than whenever the app is next opened.
public struct FastingCoordinator: @unchecked Sendable {
    private let db: Database
    private let clock: any Clock
    public let timeZone: TimeZone

    private var schedules: ReligiousFastScheduleStore { ReligiousFastScheduleStore(db: db, clock: clock) }
    private var sessions: FastingSessionStore { FastingSessionStore(db: db, clock: clock) }
    private var windows: NutritionWindowStore { NutritionWindowStore(db: db, clock: clock) }
    private var cache: PrayerTimeCacheStore { PrayerTimeCacheStore(db: db, clock: clock) }

    public init(db: Database, clock: any Clock = SystemClock(), timeZone: TimeZone = .current) {
        self.db = db
        self.clock = clock
        self.timeZone = timeZone
    }

    // MARK: - Making state true

    /// Ramadan's schedule rows exist; yesterday's and today's religious state
    /// is derived. Idempotent and cheap enough for every foreground and every
    /// screen load.
    @discardableResult
    public func refresh(at now: Date? = nil) throws -> [String: ReligiousFastingOutcome] {
        let instant = now ?? clock.now
        let today = calendarDate(instant)
        try schedules.ensureRamadanSchedules(around: today)
        var outcomes: [String: ReligiousFastingOutcome] = [:]
        for date in [shift(today, by: -1), today].compactMap({ $0 }) {
            outcomes[date] = try ensureDay(date, at: instant)
        }
        return outcomes
    }

    /// Re-derives the fast day an intake at `instant` could affect, right after
    /// it was logged, edited or deleted. Nil when that date has no cached prayer
    /// times — there is nothing to derive against, and the caller falls back to
    /// the session-only rule.
    @discardableResult
    public func reconcile(containing instant: Date, at now: Date? = nil) throws -> ReligiousFastingOutcome? {
        let date = calendarDate(instant)
        guard try cache.cachedDay(date) != nil else { return nil }
        return try ensureDay(date, at: now ?? clock.now)
    }

    /// `ReligiousFastingService.ensureDay` for one calendar date, fed from the
    /// prayer cache.
    @discardableResult
    public func ensureDay(_ date: String, at now: Date) throws -> ReligiousFastingOutcome {
        let times = try cache.cachedDay(date)?.times ?? []
        let nextFajr = try shift(date, by: 1).flatMap { try cache.cachedDay($0) }?
            .times.first { $0.name == "fajr" }?.timestamp
        return try ReligiousFastingService.ensureDay(
            anchorDate: date, prayerTimes: times,
            scheduleStore: schedules, sessionStore: sessions, windowStore: windows,
            nextDayFajr: nextFajr,
            timezoneOffset: timeZone.secondsFromGMT(for: now) / 60,
            at: now)
    }

    // MARK: - The user's choices

    /// The user's word on one date, then the date re-derived so the session
    /// follows at once.
    public func setManualFastDay(_ date: String, isFast: Bool?, reason: String? = nil, at now: Date? = nil) throws {
        try schedules.setManualFastDay(date, isFast: isFast, reason: reason)
        try ensureDay(date, at: now ?? clock.now)
    }

    public func setRamadanEnabled(_ enabled: Bool, at now: Date? = nil) throws {
        let instant = now ?? clock.now
        try schedules.setRamadanEnabled(enabled, asOf: calendarDate(instant))
        try refresh(at: instant)
    }

    public func setRecurringEnabled(_ scheduleType: String, enabled: Bool, at now: Date? = nil) throws {
        try schedules.setRecurringEnabled(scheduleType, enabled: enabled)
        try refresh(at: now)
    }

    // MARK: - Reading

    public func day(_ date: String) throws -> ReligiousFastDay {
        ReligiousFastDay(date: date,
                         status: try schedules.status(date),
                         prayerTimes: try cache.cachedDay(date)?.times ?? [],
                         session: try sessions.sessions(for: date).first { $0.sessionType == .religious })
    }

    public func today(at now: Date? = nil) throws -> ReligiousFastDay {
        try day(calendarDate(now ?? clock.now))
    }

    /// The fast days among the next `days` dates after `now`'s, with their
    /// reasons — the "coming up" list.
    public func upcoming(after now: Date? = nil, days: Int = 30) throws -> [ReligiousFastDayStatus] {
        guard let tomorrow = shift(calendarDate(now ?? clock.now), by: 1) else { return [] }
        return try schedules.statuses(from: tomorrow, days: days).filter(\.isFastDay)
    }

    /// The night window a screen should show at `now`: the one running, or the
    /// one that ended most recently (last night's, during the day). Nil when
    /// neither of the last two nights was a fast night.
    public func currentNightWindow(at now: Date? = nil) throws -> NutritionWindow? {
        let instant = now ?? clock.now
        if let running = try windows.window(containing: instant), running.windowType == .nightNutritionWindow {
            return running
        }
        let today = calendarDate(instant)
        for date in [today, shift(today, by: -1)].compactMap({ $0 }) {
            if let window = try windows.window(date: date, windowType: .nightNutritionWindow),
               window.endTimestamp <= instant {
                return window
            }
        }
        return nil
    }

    /// What was eaten and drunk in a night window up to `now` — the read half of
    /// §7.2, which had no screen at all.
    public func contents(of window: NutritionWindow, at now: Date? = nil) throws -> [FastingIntakeLog.Intake] {
        try FastingIntakeLog(db: db).intakes(from: window.startTimestamp,
                                             to: min(window.endTimestamp, now ?? clock.now))
    }

    // MARK: - Intermittent suggestion

    /// §11.1's suggestion: the instant the suggested fast would start from (the
    /// last food log), when "No calories have been logged for N hours" is true
    /// right now. Nil when a fast is already running, when today is a religious
    /// fast day (BRD §6.13: "IF auto-suggestion disabled"), or when there is no
    /// food log in the lookback at all — a fresh install has not "not eaten for
    /// 14 hours", it has not logged anything yet.
    public func intermittentSuggestionStart(at now: Date? = nil, thresholdHours: Double = 14) throws -> Date? {
        let instant = now ?? clock.now
        guard try sessions.activeSession() == nil,
              try !schedules.isFastDay(calendarDate(instant)) else { return nil }
        let service = IFSuggestionService(db: db, clock: clock, zone: ZoneContext(timeZone, at: instant))
        guard let hours = try service.hoursSinceLastCalorieEntry(before: instant),
              IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: hours, thresholdHours: thresholdHours)
        else { return nil }
        return instant.addingTimeInterval(-hours * 3600)
    }

    // MARK: - Dates

    /// The civil `"YYYY-MM-DD"` an instant falls on in this coordinator's zone.
    public func calendarDate(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: instant)
    }

    public func shift(_ date: String, by days: Int) -> String? {
        guard let parsed = ReligiousFastScheduleStore.gregorianDate(from: date),
              let moved = ReligiousFastScheduleStore.utcCalendar.date(byAdding: .day, value: days, to: parsed)
        else { return nil }
        return ReligiousFastScheduleStore.dateString(moved)
    }
}
