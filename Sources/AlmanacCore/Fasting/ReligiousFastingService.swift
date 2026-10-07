import Foundation

/// What `ReligiousFastingService.ensureDay` did on one call — mostly useful
/// for tests and logging; nothing in the fasting state itself depends on
/// this being read.
public enum ReligiousFastingOutcome: Sendable, Hashable {
    case notAFastDay
    /// A fast day with no prayer times for it — nothing can be derived, and
    /// nothing is invented.
    case prayerTimesUnavailable
    /// A fast day whose Fajr has not come yet. No session exists before it:
    /// everything before Fajr is suhoor.
    case notStartedYet
    case sessionCreated(sessionId: Int64)
    case alreadyActive(sessionId: Int64)
    /// Ended at Maghrib — the fast was kept.
    case sessionEnded(sessionId: Int64)
    /// Ended before Maghrib, at the first intake after Fajr.
    case sessionBroken(sessionId: Int64, at: Date)
    case alreadyEnded(sessionId: Int64)
    /// The day stopped being a fast day (the user said so) and the session the
    /// calendar had created for it was removed.
    case sessionRemoved(sessionId: Int64)
}

/// §11.2's auto-creation/auto-end, composing
/// `ReligiousFastScheduleStore` + `FastingSessionStore` + `NutritionWindowStore`.
/// None of those three know about religious fasting as a *combined* concept
/// — this is where they meet, the same role `ReligiousFastingService`'s
/// sibling `ReadinessCycleLinkingService` and `FastingAwareNutritionLog`
/// play elsewhere in this repo.
///
/// ## A religious session is derived, not accumulated
///
/// `ensureDay` does not apply events to a session; it computes what the session
/// *is* from four facts and writes that:
///
/// - whether the date is a fast day (schedule + the user's corrections),
/// - Fajr and Maghrib (the prayer cache),
/// - the first intake of any kind at or after Fajr (`FastingIntakeLog`),
/// - the current time.
///
/// Before Fajr there is no session (everything then is suhoor). From Fajr it is
/// open; at the first intake it is broken; at Maghrib, unbroken, it is kept.
/// Because it is recomputed on every call, it is right however the facts
/// changed — a drink logged from the widget, a meal moved in an editor, an
/// entry deleted, water imported from Apple Health, prayer times recalculated
/// after travel, the day un-marked. The event-driven alternative needs every
/// write path to remember to call it, which is the failure this repo has
/// already recorded once ("the seventh path added later will be the one that
/// forgets"); here a forgotten path costs one refresh of staleness.
///
/// The dry-fast break rule is the owner's (2026-09-29): any intake ends it,
/// water included, as `end` rather than `invalidate` — the hours before the
/// intake were genuinely fasted.
public enum ReligiousFastingService {
    @discardableResult
    public static func ensureDay(anchorDate: String, prayerTimes: [PrayerTime],
                                  scheduleStore: ReligiousFastScheduleStore,
                                  sessionStore: FastingSessionStore,
                                  windowStore: NutritionWindowStore,
                                  nextDayFajr: Date?,
                                  timezoneOffset: Int?,
                                  at now: Date) throws -> ReligiousFastingOutcome {
        let existing = try sessionStore.sessions(for: anchorDate).first { $0.sessionType == .religious }

        guard try scheduleStore.isFastDay(anchorDate) else {
            // Un-marking a day takes back what marking it created: the session
            // and the night window, and the window's claim on the entries in it.
            try removeNightWindow(date: anchorDate, windowStore: windowStore)
            if let existing {
                try sessionStore.delete(id: existing.id)
                return .sessionRemoved(sessionId: existing.id)
            }
            return .notAFastDay
        }
        guard let fajr = prayerTimes.first(where: { $0.name == "fajr" })?.timestamp,
              let maghrib = prayerTimes.first(where: { $0.name == "maghrib" })?.timestamp,
              maghrib > fajr else {
            return .prayerTimesUnavailable
        }

        try ensureNightWindow(date: anchorDate, maghrib: maghrib, nextDayFajr: nextDayFajr, windowStore: windowStore)

        guard now >= fajr else {
            // An older build created the session at any hour, so a session can
            // exist before its own Fajr. It has not begun; it goes.
            if let existing {
                try sessionStore.delete(id: existing.id)
            }
            return .notStartedYet
        }

        // Inclusive of `now`: an entry logged this instant has happened. One
        // stamped in the future (an editor allows it) has not, and does not
        // break a fast that is still being kept.
        let breakingIntake = try FastingIntakeLog(db: sessionStore.db)
            .intakes(from: fajr, to: maghrib)
            .first { $0.at <= now }
        let derivedEnd: Date? = breakingIntake?.at ?? (now >= maghrib ? maghrib : nil)

        guard let existing else {
            if derivedEnd == nil {
                try yieldActiveIntermittentSession(to: fajr, now: now, sessionStore: sessionStore)
            }
            let id = try sessionStore.start(
                FastingSessionDraft(startTimestamp: fajr, sessionType: .religious, isDryFast: true,
                                     timezoneOffset: timezoneOffset),
                logicalDay: anchorDate)
            if let derivedEnd {
                try sessionStore.setDerivedEnd(id: id, end: derivedEnd)
            }
            return .sessionCreated(sessionId: id)
        }

        if existing.startTimestamp != fajr {
            try sessionStore.moveStart(id: existing.id, to: fajr)
        }
        let unchanged = existing.endTimestamp == derivedEnd && !existing.isInvalidated
            && existing.isActive == (derivedEnd == nil)
        if unchanged {
            return derivedEnd == nil ? .alreadyActive(sessionId: existing.id) : .alreadyEnded(sessionId: existing.id)
        }
        if derivedEnd == nil {
            // Reopening: the intake that had broken it was deleted or moved.
            try yieldActiveIntermittentSession(to: fajr, now: now, sessionStore: sessionStore,
                                               keeping: existing.id)
        }
        try sessionStore.setDerivedEnd(id: existing.id, end: derivedEnd)
        if let breakingIntake { return .sessionBroken(sessionId: existing.id, at: breakingIntake.at) }
        return derivedEnd == nil ? .alreadyActive(sessionId: existing.id) : .sessionEnded(sessionId: existing.id)
    }

    // MARK: - Private

    /// Only one session can be active (`idx_fasting_session_one_active`). An
    /// intermittent fast still running when a religious one begins is
    /// subsumed by it: it ends at Fajr (or at its own start, if it began after
    /// Fajr), keeping the hours it really ran, so the religious fast can open.
    /// Whatever else is active is ended the same way; in practice that is only
    /// ever an intermittent fast, because `FastingCoordinator` closes
    /// yesterday's religious fast at its own Maghrib before it opens today's.
    /// Without this the religious session's insert failed on the index and the
    /// fasting screen showed a constraint error on every fast day.
    private static func yieldActiveIntermittentSession(to fajr: Date, now: Date,
                                                       sessionStore: FastingSessionStore,
                                                       keeping keptID: Int64? = nil) throws {
        guard let active = try sessionStore.activeSession(), active.id != keptID else { return }
        let end = max(min(fajr, now), active.startTimestamp)
        try sessionStore.endScheduled(id: active.id, at: end)
    }

    /// The night window `Maghrib(D)→Fajr(D+1)`, upserted on every call so it
    /// follows recalculated prayer times. It needs tomorrow's Fajr for its end;
    /// without one it waits for a later call rather than giving up on the day —
    /// the first call of a day routinely runs before tomorrow is cached, and the
    /// version that only built the window alongside a new session lost it for
    /// the whole day.
    ///
    /// Entries are re-resolved only when the window is new or its bounds moved:
    /// marking the day late must claim an iftar already logged, and a moved
    /// boundary must release entries now outside it, but a refresh that changes
    /// nothing should not rewrite the night's rows.
    private static func ensureNightWindow(date: String, maghrib: Date, nextDayFajr: Date?,
                                          windowStore: NutritionWindowStore) throws {
        guard let nextDayFajr, nextDayFajr > maghrib else { return }
        let current = try windowStore.window(date: date, windowType: .nightNutritionWindow)
        if let current, current.startTimestamp == maghrib, current.endTimestamp == nextDayFajr { return }
        let windowID = try windowStore.createWindow(date: date, windowType: .nightNutritionWindow,
                                                    startTimestamp: maghrib, endTimestamp: nextDayFajr,
                                                    fajrTimestamp: nextDayFajr, maghribTimestamp: maghrib)
        _ = try NightNutritionWindowAssigner(db: windowStore.db).assignUnassigned(inWindow: windowID)
    }

    private static func removeNightWindow(date: String, windowStore: NutritionWindowStore) throws {
        guard let window = try windowStore.window(date: date, windowType: .nightNutritionWindow) else { return }
        for table in ["nutrition_log", "hydration_log"] {
            try windowStore.db.run("UPDATE \(table) SET nutrition_window_id = NULL WHERE nutrition_window_id = ?;",
                                   [.integer(window.id)])
        }
        try windowStore.db.run("DELETE FROM nutrition_window WHERE id = ?;", [.integer(window.id)])
    }
}
