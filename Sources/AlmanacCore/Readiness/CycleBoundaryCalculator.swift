import Foundation

/// A readiness cycle's time window. `end` is nil for the still-open cycle —
/// the same "open means no end yet" convention `ReadinessCycleStore.openCycle()`
/// already uses for `cycleEndTimestamp`.
public struct CycleWindow: Sendable, Hashable {
    public let start: Date
    public let end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }
}

/// Computes a readiness cycle's boundary from a wake time or, when sleep
/// tracking is off, a fixed calendar-day rule (Ticket 1, 2026-09-18 handoff).
///
/// Pure and stateless — no HealthKit, no storage. `ReadinessCycleStore`
/// remains the place bare cycle rows get persisted; this is only the "what
/// window should this cycle have" decision the store's own doc comment
/// flags as not yet built.
public enum CycleBoundaryCalculator {
    /// Where the wake time for a cycle comes from.
    public enum WakeSource: Sendable, Hashable {
        /// A wake time detected from real sleep data.
        case detected(Date)
        /// A user-entered wake time, substituting for a missing sleep entry.
        /// Computed identically to `.detected` (decision 1.2).
        case manual(Date)
        /// Sleep tracking is off — no wake-time concept applies (decision 1.3).
        case trackingOff
    }

    /// `now`/`timeZone` only matter for `.trackingOff`; a real or manual wake
    /// time is self-sufficient.
    public static func window(for source: WakeSource, now: Date, timeZone: TimeZone) -> CycleWindow {
        switch source {
        case .detected(let wake), .manual(let wake):
            return CycleWindow(start: wake, end: nil)
        case .trackingOff:
            return calendarDayWindow(now: now, timeZone: timeZone)
        }
    }

    /// Decision 1.3: with tracking off, the cycle is a fixed calendar day
    /// rolling over at 23:59:00 local — not midnight, and not the 04:00
    /// `DayBoundary.almanac` rule other domains use (that rule is about
    /// which logical day a *logged entry* belongs to; this is about when a
    /// readiness cycle itself resets, a separate product decision).
    private static func calendarDayWindow(now: Date, timeZone: TimeZone) -> CycleWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 23
        comps.minute = 59
        comps.second = 0
        let todayRollover = calendar.date(from: comps)!

        if now >= todayRollover {
            let nextRollover = calendar.date(byAdding: .day, value: 1, to: todayRollover)!
            return CycleWindow(start: todayRollover, end: nextRollover)
        } else {
            let previousRollover = calendar.date(byAdding: .day, value: -1, to: todayRollover)!
            return CycleWindow(start: previousRollover, end: todayRollover)
        }
    }
}
