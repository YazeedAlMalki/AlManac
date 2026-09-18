import Foundation

/// One of the nine notification types the tech spec's §14.2 scheduling
/// rules and Appendix B suppression matrix both name.
public enum NotificationType: String, Sendable, Hashable, CaseIterable {
    case readiness
    case water
    case meal
    case bedtime
    case supplement
    case suhoor
    case iftar
    case contextualSnack = "contextual_snack"
    case contextualHydration = "contextual_hydration"
}

/// The five state axes Appendix B suppresses against, at the moment a
/// notification would fire. Each is a plain fact a caller already has (or
/// can get from `FastingSessionStore`, shift data, `ReadinessCycleStore`,
/// post-shift-sleep detection) — this type does not read any store itself.
///
/// Field-level definitions, quoted directly from the spec's footnotes:
/// - `isDryFastActive`: `fastingSession.isDryFast = 1 AND fastingSession.isActive = 1`
/// - `isConfirmedIFActive`: `fastingSession.sessionType IN ('if_planned','if_confirmed_suggestion') AND fastingSession.isActive = 1`
/// - `isNightShift`: `shift_occurrence.shiftType = 'night' AND current time is within shift hours`
/// - `isPostShiftSleep`: current time is within a detected post-shift sleep episode
/// - `isReadinessAlreadyFinal`: today's readiness cycle already has a final submission
public struct NotificationSuppressionContext: Sendable, Hashable {
    public var isDryFastActive: Bool
    public var isConfirmedIFActive: Bool
    public var isNightShift: Bool
    public var isPostShiftSleep: Bool
    public var isReadinessAlreadyFinal: Bool

    public init(isDryFastActive: Bool = false, isConfirmedIFActive: Bool = false, isNightShift: Bool = false,
                isPostShiftSleep: Bool = false, isReadinessAlreadyFinal: Bool = false) {
        self.isDryFastActive = isDryFastActive
        self.isConfirmedIFActive = isConfirmedIFActive
        self.isNightShift = isNightShift
        self.isPostShiftSleep = isPostShiftSleep
        self.isReadinessAlreadyFinal = isReadinessAlreadyFinal
    }
}

/// Appendix B, transcribed verbatim: whether one notification type should be
/// suppressed given the current state. Pure and stateless — no storage, no
/// `UNUserNotificationCenter` (Darwin-only, not available on Linux, the same
/// reason `WorkoutHealthKitMatcher` stops at pure matching logic). What
/// actually schedules and cancels notifications is `Native/Almanac/
/// NotificationScheduler.swift` (iOS-app-target, currently hydration-only);
/// this is the piece that decides what it *should* schedule, ready for that
/// caller to consult per type, per §14.1 step 3 ("apply suppression matrix").
///
/// A "—" cell in the spec's table (an axis the spec doesn't name for that
/// row at all) means that axis never suppresses that type — `iftar` has no
/// "🚫" cell anywhere in the table, so it is never suppressed by any of
/// these five axes.
public enum NotificationSuppressionMatrix {
    public static func shouldSuppress(_ type: NotificationType, in context: NotificationSuppressionContext) -> Bool {
        switch type {
        case .readiness:
            // "During post-shift sleep" and "readiness already final" suppress;
            // dry fast / confirmed IF / night shift are explicitly "✅ send".
            return context.isPostShiftSleep || context.isReadinessAlreadyFinal
        case .water:
            return context.isDryFastActive || context.isPostShiftSleep
        case .meal:
            return context.isConfirmedIFActive || context.isPostShiftSleep
        case .bedtime:
            return context.isNightShift || context.isPostShiftSleep
        case .supplement:
            // Only post-shift sleep suppresses; every other axis is "✅ send".
            return context.isPostShiftSleep
        case .suhoor:
            // Appendix B's own cell reads "🚫 (send = end of fast approaching)"
            // for "during dry fast" — a genuinely confusing footnote, since
            // suhoor fires 20 minutes *before* Fajr (§14.2), i.e. before the
            // fast has started, so `isDryFastActive` should already be false
            // at the real trigger time and this branch is not expected to be
            // reached in practice. Transcribed literally (🚫 = suppress)
            // rather than silently reinterpreted — flagged here, not resolved,
            // the same discipline `spec-reconciliation.md` uses elsewhere.
            return context.isDryFastActive
        case .iftar:
            return false
        case .contextualSnack:
            return context.isConfirmedIFActive || context.isPostShiftSleep
        case .contextualHydration:
            return context.isDryFastActive || context.isPostShiftSleep
        }
    }
}
