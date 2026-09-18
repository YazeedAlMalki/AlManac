import Foundation

/// Per-type trigger-instant arithmetic from tech spec §14.2. Pure and
/// stateless, exactly like `NotificationSuppressionMatrix` — every function
/// takes the primitives it needs, already resolved to real instants, and
/// returns when a notification of that type should fire. Nothing here reads
/// a store; `NotificationTriggerAssembler` is the piece that supplies those
/// primitives from the real ones, mirroring how `NotificationSuppressionMatrix`
/// and `NotificationSuppressionContextAssembler` divide the suppression side.
///
/// Only the types §14.2 fully specifies from data this repo already
/// persists are here. Three named types are deliberately absent, flagged
/// rather than guessed at:
/// - **Meal** and **Supplement** reminders are plain user-set clock times
///   (§14.2: "user sets preferred times" / "user sets time per supplement
///   plan") — there is no trigger *to compute*, so there is nothing for
///   this type to do for them; scheduling a stored time-of-day is app-layer
///   work, not core logic.
/// - **Contextual: Pre-workout Snack Suggestion** needs "planned workout
///   start" (§14.2), and nothing in this repo yet represents a *future,
///   scheduled* workout — `PrescribedWorkoutStore` is a reusable template
///   with no time attached, and `WorkoutSessionStore` only records sessions
///   that already happened. Building this needs a workout-scheduling
///   feature that doesn't exist yet, not just wiring.
/// - **Contextual: Pre-meal Hydration Suggestion** needs "usual meal time,
///   derived from last 14 days of logged meal timestamps" (§14.2).
///   `NutritionLogStore` records `eatenAt` as a `PartialDateTime`, which can
///   carry coarser-than-minute precision or be entirely unknown — resolving
///   "usual time of day" correctly needs its own careful pass, left for a
///   later slice rather than rushed here.
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
}
