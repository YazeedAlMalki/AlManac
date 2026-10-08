import Foundation

/// Reads the real stores `NotificationSuppressionContext`'s own doc comment
/// names — `FastingSessionStore`, shift data (`ShiftScheduleStore`),
/// `ReadinessCycleStore`/`ReadinessRecordStore`, post-shift-sleep detection
/// (`SleepEpisodeStore`) — and assembles the five-axis context.
/// `NotificationSuppressionMatrix` itself never touches a store (its own
/// doc comment says so); this is the piece that closes that gap, per §14.1
/// step 2 ("load: current day type, active fasting session, today's shift,
/// prayer times, current time").
///
/// **Honest limitation, not an oversight:** `isDryFastActive`,
/// `isConfirmedIFActive` and `isReadinessAlreadyFinal` reflect the fasting
/// session and readiness cycle that are active *right now* in the
/// database — `FastingSessionStore.activeSession()` and
/// `ReadinessCycleStore.openCycle()` have no point-in-time variant, so
/// there is no way to ask "was a fast active at some other instant" from
/// the data this repo persists. `isNightShift` and `isPostShiftSleep` *can*
/// be evaluated for an arbitrary `instant`, since shift occurrences and
/// sleep episodes carry their own start/end timestamps — which is why this
/// type still takes one. This is not actually a gap in practice: §14.1's
/// architecture reruns the whole scheduling pass (and so this whole
/// assembly) on every log entry, shift change, and app launch, rather than
/// computing suppression once for a notification's future fire time and
/// trusting it to still hold — so `instant` should in practice always be
/// "now, or very close to it."
/// The axes of `NotificationSuppressionContext` that hold the same value at
/// every instant within one scheduling pass.
///
/// A separate type rather than a `NotificationSuppressionContext` with two
/// fields left false, so it cannot be passed to `shouldSuppress` by accident and
/// silently suppress nothing. Merging them back is `with(_:now:)`.
public struct NowOnlySuppressionAxes: Sendable, Hashable {
    public let isDryFastActive: Bool
    public let isConfirmedIFActive: Bool
    public let isReadinessAlreadyFinal: Bool

    public init(isDryFastActive: Bool, isConfirmedIFActive: Bool, isReadinessAlreadyFinal: Bool) {
        self.isDryFastActive = isDryFastActive
        self.isConfirmedIFActive = isConfirmedIFActive
        self.isReadinessAlreadyFinal = isReadinessAlreadyFinal
    }

    /// The full context at `instant`, given the two axes that do vary there.
    public func with(isNightShift: Bool, isPostShiftSleep: Bool) -> NotificationSuppressionContext {
        NotificationSuppressionContext(
            isDryFastActive: isDryFastActive,
            isConfirmedIFActive: isConfirmedIFActive,
            isNightShift: isNightShift,
            isPostShiftSleep: isPostShiftSleep,
            isReadinessAlreadyFinal: isReadinessAlreadyFinal)
    }
}

/// The instants a religious dry fast covers across a scheduling pass — the
/// one Appendix B axis that *can* be known in advance, because a fast is
/// Fajr→Maghrib of a known day.
///
/// Evaluating it "as of now" for every candidate was a real bug, not just an
/// approximation: during a fast, the pass suppressed every water reminder for
/// the next 48 hours *and tomorrow's suhoor* (Appendix B suppresses suhoor
/// during a dry fast), so a user who only opened the app in the daytime in
/// Ramadan was never told when suhoor ended. Per-instant spans fix both, and
/// also mute tomorrow's daytime water reminders before tomorrow's fast begins.
public struct DryFastSpans: Sendable, Hashable {
    public let spans: [DateInterval]
    /// A dry fast is running now that no span accounts for — a session with no
    /// schedule or no prayer times behind it. With nothing to say when it ends,
    /// it is treated as covering the whole pass, the old behaviour.
    public let unboundedNow: Bool

    public func contains(_ instant: Date) -> Bool {
        unboundedNow || spans.contains { instant >= $0.start && instant < $0.end }
    }
}

public struct NotificationSuppressionContextAssembler: @unchecked Sendable {
    private let timeModel: TimeModel
    private let fastingSessions: FastingSessionStore
    private let religiousFasts: ReligiousFastScheduleStore
    private let prayerTimes: PrayerTimeCacheStore
    private let shifts: ShiftScheduleStore
    private let sleepEpisodes: SleepEpisodeStore
    private let readinessCycles: ReadinessCycleStore
    private let readinessRecords: ReadinessRecordStore

    public init(db: Database, timeModel: TimeModel) {
        self.timeModel = timeModel
        self.fastingSessions = FastingSessionStore(db: db)
        self.religiousFasts = ReligiousFastScheduleStore(db: db)
        self.prayerTimes = PrayerTimeCacheStore(db: db)
        self.shifts = ShiftScheduleStore(db: db)
        self.sleepEpisodes = SleepEpisodeStore(db: db)
        self.readinessCycles = ReadinessCycleStore(db: db)
        self.readinessRecords = ReadinessRecordStore(db: db)
    }

    public func context(at instant: Date) throws -> NotificationSuppressionContext {
        let now = try nowOnlyAxes()
        return NotificationSuppressionContext(
            isDryFastActive: now.isDryFastActive,
            isConfirmedIFActive: now.isConfirmedIFActive,
            isNightShift: try isWithinNightShift(at: instant),
            isPostShiftSleep: try isWithinPostShiftSleep(at: instant),
            isReadinessAlreadyFinal: now.isReadinessAlreadyFinal)
    }

    /// The three axes that cannot be evaluated at an arbitrary instant, read
    /// once and reusable for every instant a caller cares about.
    ///
    /// **This exists because calling `context(at:)` per candidate was a real
    /// performance bug.** `NotificationPlanner` evaluates suppression at each
    /// notification's own fire instant — correctly, because two of the five axes
    /// carry their own timestamps — and a 48-hour window can hold twenty-odd
    /// candidates. Each `context(at:)` call issued about seven queries: the
    /// active fast, two shift occurrences, two days of sleep episodes, the open
    /// cycle, and its record. That is roughly 140 queries for one scheduling
    /// pass, on a pass that runs on **every foreground activation**.
    ///
    /// Three of the five axes do not vary within a pass at all — a dry fast is
    /// either active at every candidate's fire instant or at none of them, and
    /// today's readiness is final or it is not. Only `isNightShift` and
    /// `isPostShiftSleep` depend on the instant. Splitting them means a pass
    /// costs about four queries instead of one hundred and forty, and the answer
    /// is identical.
    public func nowOnlyAxes() throws -> NowOnlySuppressionAxes {
        let fasting = try fastingSessions.activeSession()
        let isConfirmedIF = fasting.map {
            $0.sessionType == .ifPlanned || $0.sessionType == .ifConfirmedSuggestion
        } ?? false
        return NowOnlySuppressionAxes(
            isDryFastActive: fasting?.isDryFast ?? false,
            isConfirmedIFActive: isConfirmedIF,
            isReadinessAlreadyFinal: try isOpenReadinessCycleFinal())
    }

    /// The dry-fast spans from a day before `instant` to the end of `horizon`:
    /// each scheduled fast day with cached prayer times contributes
    /// `[Fajr, end)`, where `end` is Maghrib — or the moment its session was
    /// broken, since a fast that is over no longer mutes anything.
    public func dryFastSpans(around instant: Date, horizon: TimeInterval,
                             nowOnly: NowOnlySuppressionAxes) throws -> DryFastSpans {
        var spans: [DateInterval] = []
        var cursor = instant.addingTimeInterval(-86_400)
        let last = calendarDateString(instant.addingTimeInterval(horizon))
        var seen = Set<String>()
        while true {
            let date = calendarDateString(cursor)
            if seen.insert(date).inserted, try religiousFasts.isFastDay(date),
               let times = try prayerTimes.cachedDay(date)?.times,
               let fajr = times.first(where: { $0.name == "fajr" })?.timestamp,
               let maghrib = times.first(where: { $0.name == "maghrib" })?.timestamp {
                let session = try fastingSessions.sessions(for: date).first { $0.sessionType == .religious }
                let end = min(session?.endTimestamp ?? maghrib, maghrib)
                if end > fajr { spans.append(DateInterval(start: fajr, end: end)) }
            }
            if date >= last { break }
            cursor = cursor.addingTimeInterval(86_400)
        }
        let coveredNow = spans.contains { instant >= $0.start && instant < $0.end }
        return DryFastSpans(spans: spans, unboundedNow: nowOnly.isDryFastActive && !coveredNow)
    }

    // MARK: - Private

    /// `shift_occurrence.date` is a plain calendar date, matching how every
    /// existing caller of `ShiftScheduleStore` addresses it (e.g. the
    /// `ShiftAwareCaffeineContext` tests use `"2026-09-17"` style dates, not
    /// `LogicalDay`'s 04:00-boundary label) — not the 4am-boundary logical
    /// day the rest of this file uses for sleep episodes. A night shift that
    /// started "yesterday" and is still running now is still filed under
    /// yesterday's date, so both today's and yesterday's occurrence are
    /// checked. `shiftStartTime`/`shiftEndTime` are full instants
    /// (Migration014), not times-of-day, so a plain range check is correct
    /// regardless of whether the shift crosses midnight.
    private func isWithinNightShift(at instant: Date) throws -> Bool {
        try isWithinNightShift(at: instant, occurrences: try nightOccurrences(around: instant))
    }

    /// The night shift window covering `instant`, from occurrences already read.
    ///
    /// The batched form, and the reason `NotificationPlanner` is not issuing two
    /// shift queries per candidate. See `nowOnlyAxes()` for the whole argument;
    /// this is the same split applied to the two axes that genuinely do vary.
    func isWithinNightShift(at instant: Date, occurrences: [ShiftOccurrenceRecord]) -> Bool {
        for occurrence in occurrences where occurrence.shiftType == .night {
            guard let start = occurrence.shiftStartTime, let end = occurrence.shiftEndTime else { continue }
            if instant >= start && instant <= end { return true }
        }
        return false
    }

    /// Night-shift occurrences for the two calendar dates an instant can fall in.
    ///
    /// Two dates, not two queries per candidate: a night shift that started
    /// "yesterday" and is still running is filed under yesterday's date.
    func nightOccurrences(around instant: Date) throws -> [ShiftOccurrenceRecord] {
        var found: [ShiftOccurrenceRecord] = []
        for date in [calendarDateString(instant), calendarDateString(instant.addingTimeInterval(-86400))] {
            if let occurrence = try shifts.occurrence(for: date) { found.append(occurrence) }
        }
        return found
    }

    /// Mirrors the night-shift lookup, but keyed by logical day (04:00
    /// boundary) rather than calendar date, since that is what
    /// `SleepEpisodeStore.episodes(for:)` is keyed on — a post-shift episode
    /// classified under yesterday's logical day can still be running past
    /// the 04:00 boundary into today's.
    private func isWithinPostShiftSleep(at instant: Date) throws -> Bool {
        try isWithinPostShiftSleep(at: instant, episodes: try postShiftEpisodes(around: instant))
    }

    /// The batched form. An episode spanning now may be filed under today's
    /// logical day or yesterday's — the 04:00 boundary means a post-shift sleep
    /// that started before it is still running after it.
    func isWithinPostShiftSleep(at instant: Date, episodes: [StoredSleepEpisode]) -> Bool {
        episodes.contains {
            $0.effectiveType == .postShift && instant >= $0.start && instant <= $0.end
        }
    }

    func postShiftEpisodes(around instant: Date) throws -> [StoredSleepEpisode] {
        let today = timeModel.logicalDay(instant)
        var days = [today]
        if let yesterday = timeModel.day(before: today) { days.append(yesterday) }
        var found: [StoredSleepEpisode] = []
        for day in days {
            found.append(contentsOf: try sleepEpisodes.episodes(for: day.value)
                .filter { $0.effectiveType == .postShift })
        }
        return found
    }

    /// Whether the currently open readiness cycle already has a `.final`
    /// record. No open cycle at all (nothing started yet this cycle) is
    /// "not final" rather than an error — there is nothing to suppress
    /// against.
    private func isOpenReadinessCycleFinal() throws -> Bool {
        guard let cycle = try readinessCycles.openCycle() else { return false }
        return try readinessRecords.record(cycleId: cycle.id)?.state == .final
    }

    private func calendarDateString(_ instant: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeModel.timeZone
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: instant)
    }
}
