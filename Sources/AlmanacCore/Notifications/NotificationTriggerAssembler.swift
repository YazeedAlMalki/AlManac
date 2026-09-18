import Foundation

/// Reads the real stores `NotificationTriggerTimeComputer`'s own doc
/// comment names as out of scope for it — `ShiftScheduleStore`,
/// `PrayerTimeCacheStore`, `ReligiousFastScheduleStore`, `SleepEpisodeStore`
/// — and calls that pure computer, mirroring how
/// `NotificationSuppressionContextAssembler` does the same job for the
/// suppression side. §14.1 step 2's "load ... prayer times, current time"
/// plus the trigger rules of §14.2, for one `LogicalDay` at a time.
public struct NotificationTriggerAssembler: @unchecked Sendable {
    private let timeModel: TimeModel
    private let shifts: ShiftScheduleStore
    private let prayerTimes: PrayerTimeCacheStore
    private let religiousFasts: ReligiousFastScheduleStore
    private let sleepEpisodes: SleepEpisodeStore
    private let nutritionLog: NutritionLogStore

    public init(db: Database, timeModel: TimeModel) {
        self.timeModel = timeModel
        self.shifts = ShiftScheduleStore(db: db)
        self.prayerTimes = PrayerTimeCacheStore(db: db)
        self.religiousFasts = ReligiousFastScheduleStore(db: db)
        self.sleepEpisodes = SleepEpisodeStore(db: db)
        self.nutritionLog = NutritionLogStore(db: db, zone: ZoneContext(timeModel.timeZone))
    }

    /// §14.2 — nil when `day` has no cached prayer times at all; not being a
    /// scheduled fast day is handled by the pure computer, not here.
    public func suhoorTrigger(for day: LogicalDay) throws -> Date? {
        guard let fajr = try time("fajr", on: day) else { return nil }
        return NotificationTriggerTimeComputer.suhoorTrigger(
            fajr: fajr, isFastDay: try religiousFasts.isFastDay(day.value))
    }

    /// §14.2 — nil when `day` has no cached prayer times at all.
    public func iftarTrigger(for day: LogicalDay) throws -> Date? {
        guard let maghrib = try time("maghrib", on: day) else { return nil }
        return NotificationTriggerTimeComputer.iftarTrigger(
            maghrib: maghrib, isFastDay: try religiousFasts.isFastDay(day.value))
    }

    /// §14.2 — empty when `day` has no shift occurrence, or one with no
    /// recorded wake/sleep-window instants (the ordinary case for a user
    /// without a shift schedule at all — spec §6.11).
    public func waterReminderTimes(for day: LogicalDay, intervalMinutes: Double = 90) throws -> [Date] {
        guard let occurrence = try shifts.occurrence(for: day.value),
              let wake = occurrence.expectedWakeTime,
              let sleepStart = occurrence.expectedSleepWindowStart else { return [] }
        return NotificationTriggerTimeComputer.waterReminderTimes(
            expectedWakeTime: wake, expectedSleepWindowStart: sleepStart, intervalMinutes: intervalMinutes)
    }

    /// §14.2 — nil when `day` has no shift occurrence with a recorded sleep
    /// window; the rule's user-set-time fallback is app-layer settings this
    /// assembler does not have access to.
    public func bedtimeTrigger(for day: LogicalDay, offsetMinutes: Double = 30) throws -> Date? {
        guard let sleepStart = try shifts.occurrence(for: day.value)?.expectedSleepWindowStart else { return nil }
        return NotificationTriggerTimeComputer.bedtimeTrigger(
            expectedSleepWindowStart: sleepStart, offsetMinutes: offsetMinutes)
    }

    /// §14.2 — end of `day`'s primary sleep episode when one has been
    /// classified; otherwise the day's own shift-derived `expectedWakeTime`;
    /// otherwise a 7-day trailing average of wake times from past primary
    /// episodes (the spec's other named fallback). Nil only when none of
    /// the three is available — the same "readiness waits for the user
    /// instead" case §8.2 step 4 already names for no primary sleep at all.
    public func readinessTrigger(for day: LogicalDay) throws -> Date? {
        let primaryEnd = try sleepEpisodes.episodes(for: day.value)
            .first { $0.effectiveType == .primary }?.end
        let estimated = try shifts.occurrence(for: day.value)?.expectedWakeTime
            ?? (try averageWakeTime(before: day))
        return NotificationTriggerTimeComputer.readinessTrigger(
            primarySleepEpisodeEnd: primaryEnd, estimatedWakeTime: estimated)
    }

    /// §14.2 — "usual [meal] time, derived from last 14 days of logged meal
    /// timestamps". Only entries strictly before `day` count (never `day`
    /// itself — the same non-circularity the 7-day wake average keeps:
    /// today's own, possibly not-yet-logged meal cannot be part of the
    /// average used to predict it). Nil when the window has no qualifying
    /// entry for `mealType` at all.
    public func contextualHydrationTrigger(for mealType: NutritionMealType, before day: LogicalDay,
                                            leadMinutes: Double = 60) throws -> Date? {
        guard let usual = try usualMealTime(for: mealType, before: day) else { return nil }
        return NotificationTriggerTimeComputer.contextualHydrationTrigger(
            usualMealTime: usual, leadMinutes: leadMinutes)
    }

    // MARK: - Private

    private func time(_ name: String, on day: LogicalDay) throws -> Date? {
        try prayerTimes.cachedDay(day.value)?.times.first { $0.name == name }?.timestamp
    }

    /// §14.2's "7-day average wake time": the arithmetic mean of the wake
    /// instants (primary-episode ends) of the up-to-7 logical days before
    /// `day` that have one, expressed as a time-of-day and applied to
    /// `day`'s own calendar date. Nil when none of those days has a primary
    /// episode.
    ///
    /// Plain arithmetic mean of seconds-since-midnight, not a circular
    /// mean: correct for the ordinary case (a wake time that clusters well
    /// away from midnight) and not attempted for someone whose wake time
    /// straddles midnight, which needs a circular average to average
    /// correctly and isn't handled here — flagged, not silently wrong.
    private func averageWakeTime(before day: LogicalDay) throws -> Date? {
        var wakeSecondsOfDay: [Double] = []
        var cursor = day
        for _ in 0..<7 {
            guard let previous = timeModel.day(before: cursor) else { break }
            cursor = previous
            if let end = try sleepEpisodes.episodes(for: previous.value)
                .first(where: { $0.effectiveType == .primary })?.end {
                wakeSecondsOfDay.append(secondsSinceLocalMidnight(end))
            }
        }
        guard !wakeSecondsOfDay.isEmpty, let dayStart = midnight(of: day) else { return nil }
        let average = wakeSecondsOfDay.reduce(0, +) / Double(wakeSecondsOfDay.count)
        return dayStart.addingTimeInterval(average)
    }

    private func secondsSinceLocalMidnight(_ instant: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let midnight = calendar.startOfDay(for: instant)
        return instant.timeIntervalSince(midnight)
    }

    private func midnight(of day: LogicalDay) -> Date? {
        let bits = day.value.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.timeZone = timeModel.timeZone
        return calendar.date(from: comps)
    }

    /// The arithmetic mean of seconds-since-local-midnight of every
    /// qualifying `mealType` entry logged in `[day - 14, day)`, applied to
    /// `day`'s own calendar date. "Qualifying" means a *stated* `eatenAt`
    /// (`basis == .occurrence`, never the `.recorded` fallback `logged`
    /// uses for entries with no eaten time at all — a log-time says nothing
    /// about when the user usually eats) at minute-or-finer precision
    /// (`isOrderableWithinDay`) — a day/month/year-only entry names no
    /// time-of-day to average in.
    ///
    /// Plain mean, not circular: the same limitation the 7-day wake average
    /// above carries, for the same reason.
    private func usualMealTime(for mealType: NutritionMealType, before day: LogicalDay) throws -> Date? {
        guard let dayStart = midnight(of: day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        guard let windowStart = calendar.date(byAdding: .day, value: -14, to: dayStart) else { return nil }

        let entries = try nutritionLog.logged(from: calendarDateString(windowStart), to: day.value)
        let secondsOfDay: [Double] = entries.compactMap { placed in
            guard placed.entry.mealType == mealType,
                  placed.basis == .occurrence,
                  placed.occurrence.precision.isOrderableWithinDay,
                  let instant = placed.occurrence.span?.start else { return nil }
            return secondsSinceLocalMidnight(instant)
        }
        guard !secondsOfDay.isEmpty else { return nil }
        let average = secondsOfDay.reduce(0, +) / Double(secondsOfDay.count)
        return dayStart.addingTimeInterval(average)
    }

    private func calendarDateString(_ instant: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeModel.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: instant)
    }
}
