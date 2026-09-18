import Foundation

/// Per-type trigger-instant arithmetic from tech spec §14.2. Pure and
/// stateless, exactly like `NotificationSuppressionMatrix` — every function
/// takes the primitives it needs, already resolved to real instants, and
/// returns when a notification of that type should fire. Nothing here reads
/// a store; `NotificationTriggerAssembler` is the piece that supplies those
/// primitives from the real ones, mirroring how `NotificationSuppressionMatrix`
/// and `NotificationSuppressionContextAssembler` divide the suppression side.
///
/// **Meal** and **Supplement** reminders (§14.2: "user sets preferred
/// times" / "user sets time per supplement plan") have no function here —
/// they are plain stored clock times (`MealReminderSettingsStore`,
/// Migration029; `supplement_plan.reminderMinuteOfDay`, Migration030), and
/// resolving a stored minute-of-day to a real instant for a given day is
/// arithmetic simple enough to live directly in
/// `NotificationTriggerAssembler` (`mealReminderTrigger`,
/// `supplementReminderTriggers`) — there's no *rule* here to keep pure and
/// separate the way every other type in this enum has one.
///
/// **Contextual: Pre-workout Snack Suggestion** needed "planned workout
/// start" (§14.2), which nothing in this repo represented before
/// `PlannedWorkoutStore` (Migration031) — see that migration's doc comment
/// for why it's a new, deliberately thin table rather than reusing
/// `PrescribedWorkoutStore` (a template with no time attached) or
/// `WorkoutSessionStore` (records of sessions already completed).
/// `shouldSuggestPreWorkoutSnack` below is built now that a planned start
/// exists to compare against.
public enum NotificationTriggerTimeComputer {

    /// §14.2 — 20 minutes before Fajr, only on a scheduled religious fast day.
    public static func suhoorTrigger(fajr: Date, isFastDay: Bool) -> Date? {
        guard isFastDay else { return nil }
        return fajr.addingTimeInterval(-20 * 60)
    }

    /// §14.2 — at Maghrib itself, only on a scheduled religious fast day.
    public static func iftarTrigger(maghrib: Date, isFastDay: Bool) -> Date? {
        guard isFastDay else { return nil }
        return maghrib
    }

    /// §14.2 — "every `intervalMinutes` minutes during the user's active
    /// window" (`expectedWakeTime` to `expectedSleepWindowStart` minus 2
    /// hours). The spec does not say whether the first reminder fires
    /// exactly at wake time or one interval after it — read here as "one
    /// interval after", i.e. the window's own start is never itself a
    /// reminder instant, only fixed as flagged rather than silently
    /// resolved either way. Empty, not a crash, when the window is inverted
    /// or the interval is non-positive — a wake time after the trimmed
    /// sleep window can happen on a short-rest day, which simply gets no
    /// scheduled water reminders that day.
    public static func waterReminderTimes(expectedWakeTime: Date, expectedSleepWindowStart: Date,
                                          intervalMinutes: Double = 90) -> [Date] {
        guard intervalMinutes > 0 else { return [] }
        let windowEnd = expectedSleepWindowStart.addingTimeInterval(-2 * 3600)
        guard windowEnd > expectedWakeTime else { return [] }

        var times: [Date] = []
        var next = expectedWakeTime.addingTimeInterval(intervalMinutes * 60)
        while next <= windowEnd {
            times.append(next)
            next = next.addingTimeInterval(intervalMinutes * 60)
        }
        return times
    }

    /// §14.2 — `offsetMinutes` before `expectedSleepWindowStart` (default
    /// 30, the spec's own example — "e.g., 30 min before"). The rule's
    /// other half, "falls back to user-set time", is app-layer settings
    /// this type does not have; the caller decides what to do when it has
    /// no `expectedSleepWindowStart` to pass in at all, which is why this
    /// takes a non-optional rather than resolving that fallback itself.
    public static func bedtimeTrigger(expectedSleepWindowStart: Date, offsetMinutes: Double = 30) -> Date {
        expectedSleepWindowStart.addingTimeInterval(-offsetMinutes * 60)
    }

    /// §14.2 — "end of detected primary sleep episode OR estimated wake
    /// time (from shift schedule or 7-day average wake time)". Which
    /// estimate applies is a store-reading decision the caller has already
    /// made by the time it calls this — this just applies the "primary
    /// episode wins if there is one" precedence.
    public static func readinessTrigger(primarySleepEpisodeEnd: Date?, estimatedWakeTime: Date?) -> Date? {
        primarySleepEpisodeEnd ?? estimatedWakeTime
    }

    /// §14.2 — `leadMinutes` (default 60, "~60 min before usual meal time")
    /// before an already-resolved `usualMealTime`. Deriving that usual time
    /// from 14 days of logged meals is store-reading work the caller has
    /// already done — see `NotificationTriggerAssembler.
    /// contextualHydrationTrigger(for:before:)`.
    public static func contextualHydrationTrigger(usualMealTime: Date, leadMinutes: Double = 60) -> Date {
        usualMealTime.addingTimeInterval(-leadMinutes * 60)
    }

    /// §14.2 — "when gap between last logged meal and planned workout start
    /// > user's configured threshold (default: 3 hours)... Computed at log
    /// time and at app launch." Unlike every other function in this enum,
    /// which each name a future instant to schedule a notification *for*,
    /// this rule is a live condition re-checked at specific moments (a meal
    /// gets logged, the app launches) rather than something scheduled ahead
    /// of time — the spec never gives this suggestion a lead time the way
    /// it gives hydration's "~60 min before" or bedtime's "30 min before".
    /// So this returns whether to suggest *right now*, not a `Date`; the
    /// caller fires the suggestion immediately when it returns `true`.
    ///
    /// `false` when there's no last meal to compare against at all (a
    /// gap needs two points), or when the planned workout isn't actually
    /// upcoming relative to that meal (`plannedWorkoutStart <= lastMealTime`
    /// — a workout already covered by, or before, the last meal has no
    /// "time until" to be short on).
    public static func shouldSuggestPreWorkoutSnack(lastMealTime: Date?, plannedWorkoutStart: Date,
                                                     thresholdHours: Double = 3) -> Bool {
        guard let lastMealTime, plannedWorkoutStart > lastMealTime else { return false }
        let gapHours = plannedWorkoutStart.timeIntervalSince(lastMealTime) / 3600
        return gapHours > thresholdHours
    }
}
