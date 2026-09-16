import Foundation

/// Spec §5.4 `circadian_context.contextType`.
///
/// `firstDayAfterNight` is in the schema's enumeration but §13.1's algorithm
/// never assigns it — it is left unassigned here rather than given an invented
/// rule. When the spec's own notification work (§14) needs it, the rule comes
/// from there.
public enum CircadianContextType: String, Sendable, Hashable, Codable {
    case stableDay = "stable_day"
    case stableEvening = "stable_evening"
    case stableNight = "stable_night"
    case transitionEarlier = "transition_earlier"
    case transitionLater = "transition_later"
    case firstDayAfterNight = "first_day_after_night"
    case recovery
    case irregular
    case unknown
}

public struct CircadianContext: Sendable, Hashable, Codable {
    public let date: LogicalDay
    public let shiftType: ShiftType?
    public let contextType: CircadianContextType
    /// 1, 2, 3… for the transition states; nil otherwise.
    public let transitionDayN: Int?

    public init(date: LogicalDay, shiftType: ShiftType?,
                contextType: CircadianContextType, transitionDayN: Int? = nil) {
        self.date = date
        self.shiftType = shiftType
        self.contextType = contextType
        self.transitionDayN = transitionDayN
    }
}

/// Technical Specification §13 — circadian context engine.
///
/// Runs once per readiness cycle, after primary sleep is identified. Pure: it
/// reads a shift history and returns a context, so §13.1 is testable without a
/// schedule in a database.
///
/// The engine is deliberately conservative. A user with no shift schedule at
/// all — the ordinary case, and one §6.11 requires stay fully supported — gets
/// `.unknown`, which suppresses nothing and filters nothing. It never guesses a
/// shift from sleep timing.
public enum CircadianContextEngine {

    /// §13.1 — consecutive days on one shift type before it counts as stable.
    public static let stableRunDays = 5
    /// How long after a change the transition states persist.
    public static let transitionWindowDays = 3

    /// Determines the context for `anchor` from a date-keyed shift history.
    ///
    /// `history` needs only the days leading up to `anchor`; missing days are
    /// treated as unscheduled, which ends a run rather than extending it.
    public static func determine(
        anchor: LogicalDay,
        history: [LogicalDay: ShiftType],
        timeModel: TimeModel
    ) -> CircadianContext {

        guard let current = history[anchor] else {
            return CircadianContext(date: anchor, shiftType: nil, contextType: .unknown)
        }

        // A rest day is a rest day whatever surrounds it.
        if current == .rest {
            return CircadianContext(date: anchor, shiftType: current, contextType: .recovery)
        }

        let run = runLength(endingAt: anchor, of: current, history: history, timeModel: timeModel)

        if run >= stableRunDays {
            switch current {
            case .day:     return CircadianContext(date: anchor, shiftType: current, contextType: .stableDay)
            case .evening: return CircadianContext(date: anchor, shiftType: current, contextType: .stableEvening)
            case .night:   return CircadianContext(date: anchor, shiftType: current, contextType: .stableNight)
            // split, on-call and custom have no stable state in §5.4's
            // enumeration — a rotating pattern is not a settled rhythm.
            case .split, .onCall, .custom, .rest:
                return CircadianContext(date: anchor, shiftType: current, contextType: .irregular)
            }
        }

        let previous = previousShift(before: anchor, history: history, timeModel: timeModel)

        if run <= transitionWindowDays, let previous, previous != current,
           let direction = transitionDirection(from: previous, to: current) {
            return CircadianContext(date: anchor, shiftType: current,
                                    contextType: direction, transitionDayN: run)
        }

        // Settled onto one type but not yet for long enough to call it stable,
        // or a pattern that does not resolve to a direction at all.
        return CircadianContext(date: anchor, shiftType: current, contextType: .irregular)
    }

    /// How many consecutive days up to and including `anchor` carry `shift`.
    static func runLength(endingAt anchor: LogicalDay, of shift: ShiftType,
                          history: [LogicalDay: ShiftType], timeModel: TimeModel) -> Int {
        var run = 0
        var day: LogicalDay? = anchor
        while let d = day, history[d] == shift {
            run += 1
            day = previousDay(d, timeModel: timeModel)
        }
        return run
    }

    /// The most recent scheduled shift before the current run began.
    static func previousShift(before anchor: LogicalDay, history: [LogicalDay: ShiftType],
                              timeModel: TimeModel) -> ShiftType? {
        guard let current = history[anchor] else { return nil }
        var day = previousDay(anchor, timeModel: timeModel)
        while let d = day {
            guard let shift = history[d] else { return nil }
            if shift != current { return shift }
            day = previousDay(d, timeModel: timeModel)
        }
        return nil
    }

    /// Whether the move shifts the working day earlier or later.
    ///
    /// Ranked day < evening < night. Coming off nights onto days moves
    /// everything earlier; the reverse moves it later. Split, on-call and
    /// custom have no position on that line, so a move involving them has no
    /// direction and falls through to `irregular`.
    static func transitionDirection(from previous: ShiftType, to current: ShiftType)
        -> CircadianContextType? {
        guard let a = rank(previous), let b = rank(current) else { return nil }
        if b < a { return .transitionEarlier }
        if b > a { return .transitionLater }
        return nil
    }

    static func rank(_ shift: ShiftType) -> Int? {
        switch shift {
        case .day: return 0
        case .evening: return 1
        case .night: return 2
        case .split, .onCall, .custom, .rest: return nil
        }
    }

    static func previousDay(_ day: LogicalDay, timeModel: TimeModel) -> LogicalDay? {
        guard let start = timeModel.start(of: day) else { return nil }
        return timeModel.logicalDay(start.addingTimeInterval(-12 * 3600))
    }
}
