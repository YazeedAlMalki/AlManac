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
        case .night, .onCall: return "Post-sleep check-in"
        case .evening, .split: return "Check-in"
        case .rest, .custom, .day, .none: return "Morning check-in"
        }
    }

    public static let readinessBody =
        "How are you feeling? Log your mood and soreness to finalise today's readiness."

    public static let waterTitle = "Time to hydrate"
    public static let waterBody = "Log a drink to stay on track."

    /// §14.2 — "Fajr is at [time]." The time is formatted by the caller and
    /// interpolated here, so the only formatting rule lives in one place.
    public static func suhoorTitle(fajrText: String) -> String {
        "Suhoor — 20 minutes remaining"
    }

    public static func suhoorBody(fajrText: String) -> String {
        "Fajr is at \(fajrText). The fast begins soon."
    }

    public static let iftarTitle = "Iftar time"
    public static let iftarBody = "Maghrib has arrived. Your fast has ended."

    public static func mealTitle(_ mealType: NutritionMealType) -> String {
        switch mealType {
        case .breakfast: return "Time for breakfast"
        case .lunch: return "Time for lunch"
        case .dinner: return "Time for dinner"
        case .snack: return "Snack time"
        }
    }

    public static func mealBody(_ mealType: NutritionMealType) -> String {
        "Log your \(mealType.rawValue) to keep today's totals honest."
    }

    public static let bedtimeTitle = "Wind down soon"
    public static let bedtimeBody = "Your sleep window is approaching. Settle in when you can."

    public static func supplementTitle(_ name: String) -> String {
        "Time for \(name)"
    }

    public static let supplementBody = "Log your dose to keep today's adherence accurate."

    /// §14.2 — "~60 min before usual meal time". `leadMinutes` is the caller's
    /// resolved lead (60 by default); the copy says "about an hour" only when
    /// that is actually the lead, rather than always claiming an hour it did
    /// not use.
    public static func contextualHydrationBody(mealType: NutritionMealType, leadMinutes: Double) -> String {
        let lead = leadMinutes >= 55 && leadMinutes <= 65
            ? "about an hour"
            : "about \(Int(leadMinutes.rounded())) minutes"
        return "Your usual \(mealType.rawValue) is \(lead) away. Drinking 200 ml now can help with hunger."
    }

    public static let contextualHydrationTitle = "Before your usual meal"

    /// §14.2 — "Your workout is in [X] hours." This type is never scheduled:
    /// §14.2 computes it "at log time and at app launch" and it has no lead
    /// time in the spec, so it is delivered immediately by the app layer rather
    /// than planned ahead. The planner still routes it through here so the one
    /// place that words a notification is still the one place.
    public static func contextualSnackBody(hoursUntilWorkout: Double) -> String {
        let hours = hoursUntilWorkout < 1
            ? "\(Int((hoursUntilWorkout * 60).rounded())) minutes"
            : String(format: "%.1f hours", hoursUntilWorkout)
        return "Your workout is in \(hours). Consider a snack — a banana or similar fast carb."
    }

    public static let contextualSnackTitle = "Before your workout"
}
