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

        if let existing = try sessionStore.sessions(for: anchorDate).first(where: { $0.sessionType == .religious }) {
            guard existing.isActive else { return .alreadyEnded(sessionId: existing.id) }
            guard now >= maghrib else { return .alreadyActive(sessionId: existing.id) }
            try sessionStore.endScheduled(id: existing.id, at: maghrib)
            return .sessionEnded(sessionId: existing.id)
        }

        let id = try sessionStore.start(
            FastingSessionDraft(startTimestamp: fajr, sessionType: .religious, isDryFast: true,
                                 timezoneOffset: timezoneOffset),
            logicalDay: anchorDate)

        if let nextDayFajr {
            try windowStore.createWindow(date: anchorDate, windowType: "night_nutrition_window",
                                          startTimestamp: maghrib, endTimestamp: nextDayFajr,
                                          fajrTimestamp: nextDayFajr, maghribTimestamp: maghrib)
        }

        return .sessionCreated(sessionId: id)
    }
}
