import Foundation

/// The mood a person usually logs on a shift type.
public struct ExpectedMood: Sendable, Hashable {
    public let shift: ShiftType
    /// Mean of the past days' moods, each day one vote, on the 1–10 scale.
    public let average: Double
    public let dayCount: Int

    public init(shift: ShiftType, average: Double, dayCount: Int) {
        self.shift = shift
        self.average = average
        self.dayCount = dayCount
    }
}

/// How a logged mood stands against the expected one.
public enum MoodComparison: String, Sendable, Hashable {
    case higher
    case asExpected
    case lower
}

/// Expected mood on shift days (shifts-profile spec, section 4).
///
/// The person's own average on past days of the same shift type: no number
/// anyone chose, only their history. Shown once there are 14 such days, the
/// same threshold at which a shift type's readiness baseline activates, and
/// over the latest 28 of them, the same window. Read-only: a logged mood is
/// never changed by being compared.
public struct ShiftMoodExpectation: @unchecked Sendable {
    public static let activationDays = ReadinessBaselineService.shiftBaselineActivationDays
    public static let windowDays = ReadinessBaselineService.windowDays

    let db: Database
    let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel) {
        self.db = db
        self.timeModel = timeModel
    }

    /// The expected mood on `day`, or nil when `day` is not a shift day (no
    /// shift, or a rest day) or there are fewer than 14 past days on its shift
    /// type with a mood logged.
    public func expected(on day: LogicalDay) throws -> ExpectedMood? {
        let shifts = ShiftScheduleStore(db: db)
        guard let shift = try shifts.occurrence(for: day.value)?.shiftType, shift != .rest else { return nil }

        let days = try db.query("""
        SELECT logicalDay, AVG(score) AS mood FROM mood_log
        WHERE logicalDay < ? GROUP BY logicalDay ORDER BY logicalDay DESC;
        """, [.text(day.value)])
        var votes: [Double] = []
        for row in days where votes.count < Self.windowDays {
            guard let date = row.string("logicalDay"), let mood = row.double("mood"),
                  try shifts.occurrence(for: date)?.shiftType == shift else { continue }
            votes.append(mood)
        }
        guard votes.count >= Self.activationDays else { return nil }
        return ExpectedMood(shift: shift, average: votes.reduce(0, +) / Double(votes.count), dayCount: votes.count)
    }

    /// The logged mood against the expected one, both as whole numbers on the
    /// scale the person logs in: no threshold of its own.
    public static func compare(logged: Int, with expected: ExpectedMood) -> MoodComparison {
        let usual = Int(expected.average.rounded())
        if logged > usual { return .higher }
        if logged < usual { return .lower }
        return .asExpected
    }
}
