import Foundation

/// A half-open range of logical days, `[from, to)`, ending on (and including)
/// a given day.
///
/// Built by calendar arithmetic on the `YYYY-MM-DD` text rather than by
/// subtracting seconds from a `Date`, because a logical day is a label, not an
/// instant: a range that crosses a daylight-saving change must still be seven
/// labels long.
public struct LogicalDayRange: Sendable, Hashable {
    public let from: String
    public let to: String
    /// Every day of the range, oldest first.
    public let days: [String]

    public init(endingOn lastDay: String, days count: Int) {
        let count = max(1, count)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let last = formatter.date(from: lastDay) else {
            self.from = lastDay
            self.to = lastDay
            self.days = []
            return
        }
        let labels = (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: last).map(formatter.string(from:))
        }
        self.days = labels
        self.from = labels.first ?? lastDay
        self.to = calendar.date(byAdding: .day, value: 1, to: last).map(formatter.string(from:)) ?? lastDay
    }
}

/// How a bowel movement's colour is counted: by one of BRD §6.3's six names,
/// as "not recorded", or — for a spelling outside the six, which the column's
/// free text allows — exactly as written. An unrecognised spelling is never
/// folded into the nearest named colour; that would be the history inventing a
/// colour the user did not record.
public enum DigestionColourTally: Sendable, Hashable {
    case named(StoolColor)
    case notRecorded
    case other(String)

    public init(stored: String?) {
        guard let stored, !stored.trimmingCharacters(in: .whitespaces).isEmpty else {
            self = .notRecorded
            return
        }
        self = StoolColor(rawValue: stored).map(DigestionColourTally.named) ?? .other(stored)
    }

    /// Words, always — BRD §6.20's "never colour alone".
    public var displayName: String {
        switch self {
        case .named(let colour): return colour.displayName
        case .notRecorded: return localized("Colour not recorded")
        case .other(let text): return text
        }
    }

    /// The six named colours in BRD order, then anything written by hand, then
    /// "not recorded" last.
    var sortKey: (Int, String) {
        switch self {
        case .named(let colour): return (StoolColor.allCases.firstIndex(of: colour) ?? 0, "")
        case .other(let text): return (StoolColor.allCases.count, text)
        case .notRecorded: return (StoolColor.allCases.count + 1, "")
        }
    }
}

/// What was recorded over a range: a day list, counts by Bristol type, by
/// colour name and by urine grade, and a count per day for a chart.
///
/// **It states, it never interprets.** Nothing here calls a type, a colour or a
/// grade concerning, normal or anything else — `docs/features/digestion.md` §3
/// holds the advisory back for clinician review, and a history that ranked
/// entries would be that advisory arriving by another door.
public struct DigestionHistory: Sendable {
    public struct Day: Sendable, Hashable, Identifiable {
        public let logicalDay: String
        /// Newest first, as the stores return them.
        public let bowelMovements: [BowelMovementEntry]
        public let urinations: [UrinationEntry]
        public var id: String { logicalDay }
    }

    public struct BristolCount: Sendable, Hashable {
        public let type: BristolType
        public let count: Int
    }

    public struct ColourCount: Sendable, Hashable {
        public let colour: DigestionColourTally
        public let count: Int
    }

    public struct GradeCount: Sendable, Hashable {
        public let grade: UrinationColorGrade
        public let count: Int
    }

    public struct DailyCount: Sendable, Hashable, Identifiable {
        public let logicalDay: String
        public let bowelMovements: Int
        public let urinations: Int
        public var id: String { logicalDay }
    }

    public let range: LogicalDayRange
    /// Only days with at least one entry, newest first.
    public let days: [Day]
    /// All seven types, in scale order, zeros included — a scale with gaps in
    /// it is not the scale.
    public let bristolCounts: [BristolCount]
    /// Only colours that occur. Six named colours with zeros would be a wall of
    /// "0" for a user who never records colour.
    public let colourCounts: [ColourCount]
    /// All eight grades, in order, zeros included.
    public let urinationGradeCounts: [GradeCount]
    /// Every day of the range, oldest first, zeros included.
    public let dailyCounts: [DailyCount]

    public var bowelMovementCount: Int { bristolCounts.reduce(0) { $0 + $1.count } }
    public var urinationCount: Int { urinationGradeCounts.reduce(0) { $0 + $1.count } }
    public var isEmpty: Bool { days.isEmpty }

    public init(range: LogicalDayRange,
                bowelMovements: [BowelMovementEntry],
                urinations: [UrinationEntry]) {
        self.range = range
        let inRange = Set(range.days)
        let bowel = bowelMovements.filter { inRange.contains($0.logicalDay) }
        let urine = urinations.filter { inRange.contains($0.logicalDay) }

        let bowelByDay = Dictionary(grouping: bowel, by: \.logicalDay)
        let urineByDay = Dictionary(grouping: urine, by: \.logicalDay)
        let byNewest: (Date, Date) -> Bool = { $0 > $1 }

        self.days = range.days.reversed().compactMap { day in
            let b = (bowelByDay[day] ?? []).sorted { byNewest($0.timestamp, $1.timestamp) }
            let u = (urineByDay[day] ?? []).sorted { byNewest($0.timestamp, $1.timestamp) }
            return b.isEmpty && u.isEmpty ? nil : Day(logicalDay: day, bowelMovements: b, urinations: u)
        }

        let bristol = Dictionary(grouping: bowel, by: \.bristolType).mapValues(\.count)
        self.bristolCounts = BristolType.allCases.map { BristolCount(type: $0, count: bristol[$0] ?? 0) }

        let colours = Dictionary(grouping: bowel) { DigestionColourTally(stored: $0.color) }.mapValues(\.count)
        self.colourCounts = colours
            .map { ColourCount(colour: $0.key, count: $0.value) }
            .sorted { $0.colour.sortKey < $1.colour.sortKey }

        let grades = Dictionary(grouping: urine, by: \.colorGrade).mapValues(\.count)
        self.urinationGradeCounts = UrinationColorGrade.allCases.map { GradeCount(grade: $0, count: grades[$0] ?? 0) }

        self.dailyCounts = range.days.map { day in
            DailyCount(logicalDay: day,
                       bowelMovements: bowelByDay[day]?.count ?? 0,
                       urinations: urineByDay[day]?.count ?? 0)
        }
    }
}

/// The one read the history screen makes: two range queries, one pass.
public struct DigestionHistoryReader: @unchecked Sendable {
    let db: Database

    public init(db: Database) { self.db = db }

    public func history(endingOn lastDay: String, days: Int) throws -> DigestionHistory {
        let range = LogicalDayRange(endingOn: lastDay, days: days)
        return DigestionHistory(
            range: range,
            bowelMovements: try DigestionStore(db: db).logs(from: range.from, to: range.to),
            urinations: try UrinationStore(db: db).logs(from: range.from, to: range.to))
    }
}
