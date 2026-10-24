import Foundation

/// Turns a stored recurrence rule (§5.5 `shift_recurrence_pattern`) into the
/// dated shifts the rest of the app reads.
///
/// `shiftSequence` is a JSON array with one `ShiftType` raw value per day,
/// repeating from `startDate`. A weekly pattern is seven entries; "four on,
/// four off" is eight.
///
/// A saved pattern (`savedPatternId` set) also has a cadence, every week or
/// every month from `startDate`. Its sequence repeats inside each period and
/// starts again from the first day at each period's start.
public enum ShiftPatternExpander {

    /// One draft per day from the pattern's start through `last` (or the
    /// pattern's own end date, whichever comes first).
    public static func occurrences(for pattern: ShiftRecurrencePatternDraft,
                                   patternId: Int64? = nil,
                                   through last: LogicalDay,
                                   timeModel: TimeModel) throws -> [ShiftOccurrenceDraft] {
        let cadence = pattern.savedPatternId == nil ? nil : ShiftCadence(patternType: pattern.patternType)
        guard pattern.patternType != "monthly_rotation" || cadence != nil else {
            throw ShiftPatternError.unsupportedPatternType(pattern.patternType)
        }
        // Strict, not `compactMap`: dropping an unrecognised name would pull
        // every later day one place forward and nothing would say so.
        let sequence = try JSONDecoder().decode([String].self, from: Data(pattern.shiftSequence.utf8))
            .map { name -> ShiftType in
                guard let shift = ShiftType(rawValue: name) else { throw ShiftPatternError.unknownShiftType(name) }
                return shift
            }

        guard !sequence.isEmpty else { throw ShiftPatternError.emptySequence }

        let start = LogicalDay(pattern.startDate)
        let finalDay = pattern.endDate.map { min(LogicalDay($0), last) } ?? last
        var drafts: [ShiftOccurrenceDraft] = []
        var cursor: LogicalDay? = start
        // Days since the current period began. Without a cadence the whole
        // run is one period.
        var dayInPeriod = 0
        var period = 0
        var nextPeriodStart = cadence?.periodStart(1, from: start)
        while let day = cursor, day <= finalDay {
            if let boundary = nextPeriodStart, day >= boundary {
                period += 1
                dayInPeriod = 0
                nextPeriodStart = cadence?.periodStart(period + 1, from: start)
            }
            drafts.append(ShiftOccurrenceDraft(scheduleId: pattern.scheduleId, date: day.value,
                                               shiftType: sequence[dayInPeriod % sequence.count],
                                               recurrencePatternId: patternId))
            dayInPeriod += 1
            cursor = timeModel.day(after: day)
        }
        return drafts
    }
}

/// Consecutive days on one shift: "3 nights" is `ShiftBlock(.night, days: 3)`.
public struct ShiftBlock: Sendable, Hashable, Codable {
    public var shift: ShiftType
    public var days: Int

    public init(_ shift: ShiftType, days: Int) {
        self.shift = shift
        self.days = days
    }

    /// One shift per day, block after block.
    public static func days(of blocks: [ShiftBlock]) -> [ShiftType] {
        blocks.flatMap { Array(repeating: $0.shift, count: max(0, $0.days)) }
    }
}

/// How often a saved pattern starts again: every week, or every month, counted
/// from its start date.
public enum ShiftCadence: String, Sendable, Hashable, Codable, CaseIterable {
    case weekly
    case monthly

    /// The `shift_recurrence_pattern.patternType` a saved pattern is stored as.
    public var patternType: String {
        switch self {
        case .weekly: return "weekly_rotation"
        case .monthly: return "monthly_rotation"
        }
    }

    public init?(patternType: String) {
        guard let match = Self.allCases.first(where: { $0.patternType == patternType }) else { return nil }
        self = match
    }

    /// The first day of period `index`, where period 0 starts on `anchor`.
    ///
    /// Months count from the anchor itself, never from the previous period:
    /// from 31 January the periods start on 28 February and then 31 March,
    /// not 28 March. Calendar dates only, in UTC, so no time zone or day
    /// boundary can move a date.
    public func periodStart(_ index: Int, from anchor: LogicalDay) -> LogicalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = anchor.value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return anchor
        }
        let shifted: Date?
        switch self {
        case .weekly: shifted = calendar.date(byAdding: .day, value: 7 * index, to: start)
        case .monthly: shifted = calendar.date(byAdding: .month, value: index, to: start)
        }
        guard let date = shifted else { return anchor }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return LogicalDay(String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
    }

    /// The period that contains `day`: its index and first day, and the
    /// first day of the period after it. Nil before `anchor`.
    public func period(containing day: LogicalDay, from anchor: LogicalDay)
        -> (index: Int, start: LogicalDay, nextStart: LogicalDay)? {
        guard day >= anchor else { return nil }
        var index = 0
        var next = periodStart(1, from: anchor)
        while next <= day {
            index += 1
            next = periodStart(index + 1, from: anchor)
        }
        return (index, periodStart(index, from: anchor), next)
    }
}

public enum ShiftPatternError: Error, Equatable {
    case unsupportedPatternType(String)
    case unknownShiftType(String)
    case emptySequence
}

extension ShiftRecurrencePatternDraft {
    /// A day-by-day rotation from the shifts themselves, so a caller never
    /// writes the JSON `shiftSequence` holds.
    public init(scheduleId: Int64, shifts: [ShiftType], startDate: String, endDate: String? = nil) {
        // Encoding an array of plain strings cannot fail; "[]" is the honest
        // fallback and `ShiftPatternExpander` refuses it by name.
        let json = (try? JSONEncoder().encode(shifts.map(\.rawValue)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.init(scheduleId: scheduleId, patternType: "custom", shiftSequence: json,
                  startDate: startDate, endDate: endDate)
    }

    /// A saved pattern's rule: its blocks, one shift per day, repeating inside
    /// each week or month from `startDate`.
    public init(scheduleId: Int64, blocks: [ShiftBlock], cadence: ShiftCadence, startDate: String,
                savedPatternId: Int64) {
        self.init(scheduleId: scheduleId, shifts: ShiftBlock.days(of: blocks), startDate: startDate)
        self.patternType = cadence.patternType
        self.savedPatternId = savedPatternId
    }
}
