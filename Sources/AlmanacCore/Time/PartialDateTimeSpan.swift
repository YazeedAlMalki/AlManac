import Foundation

/// How a stored partial date relates to a query range.
///
/// The distinction exists because a coarse value denotes a *span*, not an
/// instant. "March 2019" is not the same claim as "1 March 2019, 00:00", and a
/// range query that treats it as the latter makes the record vanish from any
/// range that starts later in March. That is the failure this type prevents.
public enum RangeFit: String, Codable, Sendable, Hashable {
    /// Every instant the stored value could denote lies inside the range.
    case definite
    /// The span overlaps the range but also extends outside it, so the record
    /// *may* belong to the range. Returned and labelled, never dropped.
    case potential
}

/// A half-open query range, built from ISO-8601 prefixes of any precision.
public struct DateRange: Sendable, Hashable {
    public let start: Date
    public let end: Date

    /// `from` and `to` are ISO-8601 prefixes: "2019", "2019-03", "2019-03-15",
    /// or a full instant. Each is resolved to the first instant of its span.
    public init?(from: String, to: String) {
        guard let a = PartialDateTime(inferringPrecisionFrom: from)?.span?.start,
              let b = PartialDateTime(inferringPrecisionFrom: to)?.span?.start else { return nil }
        self.start = a
        self.end = b
    }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// The bounds as canonical UTC ISO-8601 text.
    ///
    /// For SQL, where stored instants are UTC strings. Comparing a stored
    /// `...Z` value against a caller's `+03:00` text lexically is wrong by the
    /// size of the offset; normalising both to UTC first is the fix.
    public var utcTextBounds: (start: String, end: String) {
        (DateRange.utcFormatter.string(from: start), DateRange.utcFormatter.string(from: end))
    }

    static let utcFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

extension PartialDateTime {

    /// Builds a value from an ISO-8601 prefix, taking precision from its shape.
    public init?(inferringPrecisionFrom text: String) {
        guard let precision = PartialDateTime.inferPrecision(text) else { return nil }
        self.init(storedText: text, precision: precision)
    }

    static func inferPrecision(_ s: String) -> TimePrecision? {
        switch s.count {
        case 0:              return .unknown
        case 4:              return .year
        case 7:              return .month
        case 10:             return .day
        case 13:             return .hour
        case 16:             return .minute
        case let n where n >= 19: return .instant
        default:             return nil
        }
    }

    /// The half-open span of instants this value could denote.
    ///
    /// Derived for querying only — **nothing here is written back to storage**,
    /// so a month-precision record stays `"2019-03"` on disk. This answers
    /// "which instants could that label cover", which is a different question
    /// from "what time did this happen", and the second is still unknown.
    ///
    /// Resolved in the record's own offset when it has one, otherwise in UTC.
    /// For a coarse value with no offset that means the span can be up to a day
    /// out at its edges, which is why such a record reports `.potential` rather
    /// than `.definite` near a boundary.
    public var span: (start: Date, end: Date)? {
        guard isKnown else { return nil }

        if precision == .instant {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let instant = formatter.date(from: text)
                    ?? PartialDateTime.fractionalFormatter.date(from: text) else { return nil }
            return (instant, instant.addingTimeInterval(1))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: (zone.offsetMinutes ?? 0) * 60)
            ?? TimeZone(secondsFromGMT: 0)!

        let characters = Array(text)
        func number(_ lower: Int, _ upper: Int) -> Int? {
            guard characters.count >= upper else { return nil }
            return Int(String(characters[lower..<upper]))
        }

        guard let year = number(0, 4) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = 1; components.day = 1
        components.hour = 0; components.minute = 0; components.second = 0

        var unit: Calendar.Component = .year
        if precision.rank >= TimePrecision.month.rank {
            guard let month = number(5, 7) else { return nil }
            components.month = month; unit = .month
        }
        if precision.rank >= TimePrecision.day.rank {
            guard let day = number(8, 10) else { return nil }
            components.day = day; unit = .day
        }
        if precision.rank >= TimePrecision.hour.rank {
            guard let hour = number(11, 13) else { return nil }
            components.hour = hour; unit = .hour
        }
        if precision.rank >= TimePrecision.minute.rank {
            guard let minute = number(14, 16) else { return nil }
            components.minute = minute; unit = .minute
        }

        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: unit, value: 1, to: start) else { return nil }
        return (start, end)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `nil` when the value cannot belong to the range at all.
    ///
    /// A coarse value whose span merely *overlaps* the range comes back as
    /// `.potential` instead of being dropped, because dropping it would assert
    /// that it happened outside the range — which the record does not say.
    public func fit(in range: DateRange) -> RangeFit? {
        guard let span else { return nil }

        // With no offset the span was resolved in UTC, which is a convenience,
        // not a fact. The true instant can be up to 14 hours either side, so
        // the overlap test widens by that much — never wrongly excluding — and
        // the answer can never be `.definite`, because definite membership is
        // exactly the claim an unknown offset cannot support.
        let known = hasKnownOffset
        let lower = known ? span.start : span.start.addingTimeInterval(-PartialDateTime.maxOffset)
        let upper = known ? span.end : span.end.addingTimeInterval(PartialDateTime.maxOffset)

        if upper <= range.start || lower >= range.end { return nil }
        guard known else { return .potential }
        if span.start >= range.start && span.end <= range.end { return .definite }
        return .potential
    }

    /// The widest real UTC offset, used only to widen an uncertain span.
    static let maxOffset: TimeInterval = 14 * 3600

    /// Whether this value's instant is pinned to a real point on the timeline.
    ///
    /// True when the stored text carries its own offset (`Z` or `±hh:mm`) or a
    /// zone was recorded alongside it. False for a bare label such as
    /// `"2019-03"` or `"2019-03-14T08:10"` with no recorded zone — those name a
    /// wall-clock reading whose instant depends on where the person was.
    public var hasKnownOffset: Bool {
        if zone.offsetMinutes != nil { return true }
        guard isKnown, !text.isEmpty else { return false }
        if text.hasSuffix("Z") || text.hasSuffix("z") { return true }
        // ±hh:mm or ±hhmm at the end, after the time part.
        let tail = text.suffix(6)
        if tail.count == 6, let sign = tail.first, sign == "+" || sign == "-" { return true }
        let short = text.suffix(5)
        if short.count == 5, let sign = short.first, sign == "+" || sign == "-" { return true }
        return false
    }
}
