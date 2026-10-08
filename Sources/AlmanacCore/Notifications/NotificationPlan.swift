import Foundation

/// One notification the app intends to deliver, resolved to a real fire
/// instant and to the words it will say.
///
/// Deliberately a value type with no `UNNotificationRequest` in it: the
/// request type is Darwin-only and cannot be constructed in a test, so the
/// planner's output is this instead and the app-side scheduler adapts it. That
/// is the same split `NotificationSuppressionMatrix` already documents for the
/// same reason.
public struct PlannedNotification: Sendable, Hashable {
    public let identifier: String
    public let type: NotificationType
    public let fireAt: Date
    public let title: String
    public let body: String

    public var id: String { identifier }

    public init(identifier: String, type: NotificationType, fireAt: Date, title: String, body: String) {
        self.identifier = identifier
        self.type = type
        self.fireAt = fireAt
        self.title = title
        self.body = body
    }
}

/// The complete set of notifications that should be pending right now.
///
/// A *snapshot*, not a schedule: it says what should be waiting when it was
/// computed, and the scheduler reconciles the OS against it. §14.1's
/// architecture reruns the whole pass on every log entry, shift change and app
/// launch precisely because a snapshot goes stale — the plan carries no claim
/// to still be true later.
public struct NotificationPlan: Sendable, Hashable {
    public let computedAt: Date
    /// Sorted by fire time, then identifier, so two runs over unchanged state
    /// produce byte-identical plans and a diff between them is empty by
    /// construction rather than by luck.
    public let notifications: [PlannedNotification]

    public init(computedAt: Date, notifications: [PlannedNotification]) {
        self.computedAt = computedAt
        self.notifications = notifications.sorted {
            $0.fireAt == $1.fireAt ? $0.identifier < $1.identifier : $0.fireAt < $1.fireAt
        }
    }

    public static func empty(_ at: Date) -> NotificationPlan { NotificationPlan(computedAt: at, notifications: []) }
}

/// The per-type wording §14.2 specifies, as pure functions.
///
/// Separate from the planner so the copy is testable without a database, and
/// so the §14.3 discretion rules have one place to be checked: nothing here
/// reads a lab value, a Bristol stool score, a digestion advisory or a photo,
/// because none of these types has any of those in its inputs to leak.
public enum NotificationText {

    /// §14.2 — "shift-aware label — never 'morning' for evening/night
    /// schedules". `shiftType` is the day's own shift; nil means no schedule,
    /// which is the ordinary case and reads as a conventional day.
    public static func readinessTitle(shiftType: ShiftType?) -> String {
        switch shiftType {
        case .night, .onCall: return localized("Post-sleep check-in")
        case .evening, .split: return localized("Check-in")
        case .rest, .custom, .day, .none: return localized("Morning check-in")
        }
    }

    // Computed rather than stored, so a notification is worded in the language
    // the app runs in when it is scheduled (#4).
    public static var readinessBody: String {
        localized("How are you feeling? Log your mood and soreness to finalise today's readiness.")
    }

    public static var waterTitle: String { localized("Time to hydrate") }
    public static var waterBody: String { localized("Log a drink to stay on track.") }

    /// §14.2 — "Fajr is at [time]." The time is formatted by the caller and
    /// interpolated here, so the only formatting rule lives in one place.
    public static func suhoorTitle(fajrText: String) -> String {
        localized("Suhoor — 20 minutes remaining")
    }

    public static func suhoorBody(fajrText: String) -> String {
        localized("Fajr is at %@. The fast begins soon.", fajrText)
    }

    public static var iftarTitle: String { localized("Iftar time") }
    public static var iftarBody: String { localized("Maghrib has arrived. Your fast has ended.") }

    /// "Asr" — the prayer's name and nothing else, the way a call to prayer
    /// announces it.
    public static func prayerTitle(_ name: String) -> String {
        PrayerTime.displayName(name)
    }

    /// "It is time for Asr (15:16)." The time is formatted by the caller.
    public static func prayerBody(_ name: String, timeText: String) -> String {
        localized("It is time for %@ (%@).", PrayerTime.displayName(name), timeText)
    }

    /// "Asr" — the prayer's name and nothing else, the way a call to prayer
    /// announces it.
    public static func prayerTitle(_ name: String) -> String {
        PrayerTime.displayName(name)
    }

    /// "It is time for Asr (15:16)." The time is formatted by the caller.
    public static func prayerBody(_ name: String, timeText: String) -> String {
        "It is time for \(PrayerTime.displayName(name)) (\(timeText))."
    }

    public static func mealTitle(_ mealType: NutritionMealType) -> String {
        switch mealType {
        case .breakfast: return localized("Time for breakfast")
        case .lunch: return localized("Time for lunch")
        case .dinner: return localized("Time for dinner")
        case .snack: return localized("Snack time")
        }
    }

    public static func mealBody(_ mealType: NutritionMealType) -> String {
        localized("Log your %@ to keep today's totals honest.", mealNoun(mealType))
    }

    /// The meal as it reads inside a sentence: "your breakfast", "your snack".
    private static func mealNoun(_ mealType: NutritionMealType) -> String {
        switch mealType {
        case .breakfast: return localized("breakfast")
        case .lunch: return localized("lunch")
        case .dinner: return localized("dinner")
        case .snack: return localized("snack")
        }
    }

    public static var bedtimeTitle: String { localized("Wind down soon") }
    public static var bedtimeBody: String { localized("Your sleep window is approaching. Settle in when you can.") }

    public static func supplementTitle(_ name: String) -> String {
        localized("Time for %@", name)
    }

    public static var supplementBody: String { localized("Log your dose to keep today's adherence accurate.") }

    /// §14.2 — "~60 min before usual meal time". `leadMinutes` is the caller's
    /// resolved lead (60 by default); the copy says "about an hour" only when
    /// that is actually the lead, rather than always claiming an hour it did
    /// not use.
    public static func contextualHydrationBody(mealType: NutritionMealType, leadMinutes: Double) -> String {
        leadMinutes >= 55 && leadMinutes <= 65
            ? localized("Your usual %@ is about an hour away. Drinking 200 ml now can help with hunger.",
                        mealNoun(mealType))
            : localized("Your usual %@ is about %@ minutes away. Drinking 200 ml now can help with hunger.",
                        mealNoun(mealType), NumberDisplay.localized(String(Int(leadMinutes.rounded()))))
    }

    public static var contextualHydrationTitle: String { localized("Before your usual meal") }

    /// §14.2 — "Your workout is in [X] hours." This type is never scheduled:
    /// §14.2 computes it "at log time and at app launch" and it has no lead
    /// time in the spec, so it is delivered immediately by the app layer rather
    /// than planned ahead. The planner still routes it through here so the one
    /// place that words a notification is still the one place.
    public static func contextualSnackBody(hoursUntilWorkout: Double) -> String {
        hoursUntilWorkout < 1
            ? localized("Your workout is in %@ minutes. Consider a snack — a banana or similar fast carb.",
                        NumberDisplay.localized(String(Int((hoursUntilWorkout * 60).rounded()))))
            : localized("Your workout is in %@ hours. Consider a snack — a banana or similar fast carb.",
                        NumberDisplay.localized(String(format: "%.1f", hoursUntilWorkout)))
    }

    public static var contextualSnackTitle: String { localized("Before your workout") }
}
