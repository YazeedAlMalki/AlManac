import Foundation

/// What `ReligiousFastingService.ensureDay` did on one call — mostly useful
/// for tests and logging; nothing in the fasting state itself depends on
/// this being read.
public enum ReligiousFastingOutcome: Sendable, Hashable {
    case notAFastDay
    case sessionCreated(sessionId: Int64)
    case alreadyActive(sessionId: Int64)
    case sessionEnded(sessionId: Int64)
    case alreadyEnded(sessionId: Int64)
}

/// §11.2's auto-creation/auto-end, composing
/// `ReligiousFastScheduleStore` + `FastingSessionStore` + `NutritionWindowStore`.
/// None of those three know about religious fasting as a *combined* concept
/// — this is where they meet, the same role `ReligiousFastingService`'s
/// sibling `ReadinessCycleLinkingService` and `FastingAwareNutritionLog`
/// play elsewhere in this repo.
///
/// `ensureDay` is idempotent and pull-based, not scheduled — there is no
/// background job or notification trigger in this repo yet (§14 is a
/// separate slice), so a caller (a dashboard refresh, an app-launch check)
/// calls this whenever it wants the day's religious-fasting state to be
/// correct, the same pattern `ReadinessCycleStore.ensureCycle` and
/// `PrayerTimeEngine.ensureCache` already use.
///
/// **Deliberately not built:** wiring a calorie entry during an active
/// religious session into `FastingSessionStore.recordNutritionEntry`'s
/// break/invalidate/shorten logic. §11.1's rules were written for
/// intermittent fasting; whether/how they apply to a dry religious fast
/// (arguably any calorie entry, even water, should invalidate a dry fast,
/// which §11.1 doesn't cover) is a real product question this pass doesn't
/// answer, not an oversight to fix silently here.
public enum ReligiousFastingService {
    @discardableResult
    public static func ensureDay(anchorDate: String, prayerTimes: [PrayerTime],
                                  scheduleStore: ReligiousFastScheduleStore,
                                  sessionStore: FastingSessionStore,
                                  windowStore: NutritionWindowStore,
                                  nextDayFajr: Date?,
                                  timezoneOffset: Int?,
                                  at now: Date) throws -> ReligiousFastingOutcome {
        guard try scheduleStore.isFastDay(anchorDate) else { return .notAFastDay }
        guard let fajr = prayerTimes.first(where: { $0.name == "fajr" })?.timestamp,
              let maghrib = prayerTimes.first(where: { $0.name == "maghrib" })?.timestamp else {
            return .notAFastDay
        }

        let id: Int64
        let outcome: ReligiousFastingOutcome
        if let existing = try sessionStore.sessions(for: anchorDate).first(where: { $0.sessionType == .religious }) {
            id = existing.id
            if !existing.isActive {
                outcome = .alreadyEnded(sessionId: existing.id)
            } else if now >= maghrib {
                try sessionStore.endScheduled(id: existing.id, at: maghrib)
                outcome = .sessionEnded(sessionId: existing.id)
            } else {
                outcome = .alreadyActive(sessionId: existing.id)
            }
        } else {
            id = try sessionStore.start(
                FastingSessionDraft(startTimestamp: fajr, sessionType: .religious, isDryFast: true,
                                     timezoneOffset: timezoneOffset),
                logicalDay: anchorDate)
            outcome = .sessionCreated(sessionId: id)
        }

        // The window is ensured on *every* call, not only when the session is
        // first created. The first `ensureDay` of a day routinely runs before
        // tomorrow's Fajr is in the prayer cache, so it creates the session
        // with no window; every later call then returned at the already-exists
        // branch above, and the window was lost for the rest of the day — which
        // left every suhoor and iftar entry in it unassigned. The window needs
        // an end timestamp, so it genuinely cannot be built without `nextDayFajr`;
        // what it can do is wait for one instead of giving up on the day.
        //
        // Idempotent by lookup, because this runs on every refresh and
        // `nutrition_window` has no uniqueness constraint on (date, windowType).
        if let nextDayFajr,
           try windowStore.window(date: anchorDate, windowType: .nightNutritionWindow) == nil {
            let windowID = try windowStore.createWindow(date: anchorDate, windowType: .nightNutritionWindow,
                                                        startTimestamp: maghrib, endTimestamp: nextDayFajr,
                                                        fajrTimestamp: nextDayFajr, maghribTimestamp: maghrib)
            // Marking the day as a fast has to claim what is already logged. The
            // user marks the day at some point during it — often after eating
            // iftar — so without this the window opens over entries that predate
            // it and they stay unassigned for good, until the next whole-history
            // rebuild happens to reach them. Scoped to the one window just
            // created, because this runs on every refresh.
            _ = try NightNutritionWindowAssigner(db: windowStore.db)
                .assignUnassigned(inWindow: windowID)
        }

        return outcome
    }
}
