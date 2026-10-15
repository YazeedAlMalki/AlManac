import Foundation

/// A run of days' circadian context, for a screen that shows the week rather
/// than only today (§13, BRD §6.11).
///
/// Derived from the shift occurrences the user has entered, by running
/// `CircadianContextEngine` for each day — not read back from the
/// `circadian_context` table, which holds a row only for days a readiness
/// cycle has reached. A day in last week the app was closed for still has a
/// shift, and so still has a context.
public struct CircadianTimeline: @unchecked Sendable {
    private let db: Database
    private let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel) {
        self.db = db
        self.timeModel = timeModel
    }

    /// One context per logical day from `first` through `last`, inclusive.
    public func days(from first: LogicalDay, through last: LogicalDay) throws -> [CircadianContext] {
        let shifts = ShiftScheduleStore(db: db)
        var history: [LogicalDay: ShiftType] = [:]
        for day in logicalDays(from: lookbackStart(before: first), through: last) {
            if let occurrence = try shifts.occurrence(for: day.value) {
                history[day] = occurrence.shiftType
            }
        }
        return logicalDays(from: first, through: last).map {
            CircadianContextEngine.determine(anchor: $0, history: history, timeModel: timeModel)
        }
    }

    /// How far back the engine needs to see to give `first` the same answer it
    /// would give with unlimited history. A run of `stableRunDays` is already
    /// stable, so counting further back changes nothing; and a transition is
    /// at most `transitionWindowDays` long and needs one day before it to name
    /// the shift it came from — which is fewer days than the stable run.
    private func lookbackStart(before first: LogicalDay) -> LogicalDay {
        var start = first
        for _ in 0..<CircadianContextEngine.stableRunDays {
            guard let previous = timeModel.day(before: start) else { break }
            start = previous
        }
        return start
    }

    private func logicalDays(from first: LogicalDay, through last: LogicalDay) -> [LogicalDay] {
        var days: [LogicalDay] = []
        var cursor: LogicalDay? = first
        while let day = cursor, day <= last {
            days.append(day)
            cursor = timeModel.day(after: day)
        }
        return days
    }
}
