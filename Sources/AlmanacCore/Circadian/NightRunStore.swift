import Foundation

/// One night of a run of night shifts.
public struct NightRunNight: Sendable, Hashable {
    public let day: LogicalDay
    /// 1 on the first night of the run.
    public let night: Int
    /// The run length this night is measured against.
    public let runLengthNights: Int

    /// The run is longer than its run length by this night.
    public var isPastRunLength: Bool { night > runLengthNights }
    /// This is the night the run passes its run length.
    public var passesRunLength: Bool { night == runLengthNights + 1 }
}

public enum NightRunError: Error, Equatable {
    case capOutOfRange
}

/// Runs of night shifts, read from the shifts the rest of the app reads.
///
/// A run is consecutive days whose shift is a night; any other day, or a day
/// with no shift, ends it. Its run length is the saved pattern's, or 3 nights.
/// Each night of a run takes `perNightPercent` of that day's readiness score,
/// from the first night, up to one cap for every pattern.
public struct NightRunStore: @unchecked Sendable {
    /// The run length used when a pattern has none, and for nights no saved
    /// pattern wrote.
    public static let defaultRunLengthNights = 3
    /// Owner, 2026-11-01: each night of a run takes 3% of the readiness score.
    public static let perNightPercent: Double = 3
    /// Owner, 2026-11-01: the cap until the person sets their own.
    public static let defaultCapPercent: Double = 15
    /// How far back a run is followed. Far longer than any run worth warning
    /// about, and it keeps one read bounded.
    static let lookBackDays = 60

    let db: Database
    let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel) {
        self.db = db
        self.timeModel = timeModel
    }

    private var shifts: ShiftScheduleStore { ShiftScheduleStore(db: db) }

    // MARK: - Counting

    /// Which night of a run `day` is: 1 on the first night, 0 when `day` is not
    /// a night shift.
    public func night(on day: LogicalDay) throws -> Int {
        var count = 0
        var cursor: LogicalDay? = day
        while let current = cursor, count < Self.lookBackDays,
              try shifts.occurrence(for: current.value)?.shiftType == .night {
            count += 1
            cursor = timeModel.day(before: current)
        }
        return count
    }

    /// The run length `day`'s run is measured against: that of the saved
    /// pattern that wrote a night of the run, the running pattern's for a run
    /// entered by hand, or the default.
    public func runLength(on day: LogicalDay) throws -> Int {
        let patterns = SavedShiftPatternStore(db: db, timeModel: timeModel)
        var cursor: LogicalDay? = day
        var looked = 0
        while let current = cursor, looked < Self.lookBackDays,
              let source = try shifts.newestSource(on: current.value), source.record.shiftType == .night {
            if let id = source.savedPatternId {
                return try patterns.pattern(id: id)?.runLengthNights ?? Self.defaultRunLengthNights
            }
            looked += 1
            cursor = timeModel.day(before: current)
        }
        if let id = try patterns.selection().currentId, let run = try patterns.pattern(id: id)?.runLengthNights {
            return run
        }
        return Self.defaultRunLengthNights
    }

    /// Every night shift from `first` through `last`, with its place in its run.
    public func nights(from first: LogicalDay, through last: LogicalDay) throws -> [NightRunNight] {
        var result: [NightRunNight] = []
        var cursor: LogicalDay? = first
        while let day = cursor, day <= last {
            let night = try night(on: day)
            if night > 0 {
                result.append(NightRunNight(day: day, night: night, runLengthNights: try runLength(on: day)))
            }
            cursor = timeModel.day(after: day)
        }
        return result
    }

    // MARK: - Readiness effect

    /// The share of `day`'s readiness score the run takes, in percent: nil when
    /// `day` is not a night shift.
    public func readinessEffectPercent(on day: LogicalDay) throws -> Double? {
        let night = try night(on: day)
        guard night > 0 else { return nil }
        return Self.effectPercent(night: night, capPercent: try capPercent())
    }

    public static func effectPercent(night: Int, capPercent: Double) -> Double {
        min(Double(night) * perNightPercent, capPercent)
    }

    /// The cap the person set, or the default.
    public func capPercent() throws -> Double {
        try db.query("""
        SELECT nightRunCapPercent FROM shift_schedule WHERE isActive = 1 ORDER BY id DESC LIMIT 1;
        """).first?.double("nightRunCapPercent") ?? Self.defaultCapPercent
    }

    /// Sets the cap for every pattern; nil goes back to the default.
    public func setCapPercent(_ percent: Double?) throws {
        if let percent, !(percent > 0 && percent <= 100) { throw NightRunError.capOutOfRange }
        let scheduleId = try shifts.defaultScheduleId()
        try db.run("UPDATE shift_schedule SET nightRunCapPercent = ? WHERE id = ?;",
                   [percent.map { SQLValue.real($0) } ?? .null, .integer(scheduleId)])
    }
}
