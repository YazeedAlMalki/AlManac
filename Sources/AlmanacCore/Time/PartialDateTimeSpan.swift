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
        let local = PartialDateTime.localText(s)
        switch local.count {
        case 0: return .unknown
        case 4: return .year
        case 7: return .month
        case 10: return .day
        case 13: return .hour
        case 16: return .minute
        case let n where n >= 19: return .instant
        default: return nil
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
        guard isKnown, Self.shapeMatches(text, precision) else { return nil }

        if precision == .instant {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let parsedText: String
            if Self.explicitOffset(text) != nil { parsedText = text.uppercased() }
            else {
                let offset = zone.offsetMinutes ?? 0
                let suffix = String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 60, abs(offset) % 60)
                parsedText = text + suffix
            }
            guard let instant = formatter.date(from: parsedText)
                    ?? PartialDateTime.fractionalFormatter.date(from: parsedText) else { return nil }
            return (instant, instant.addingTimeInterval(1))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: (Self.explicitOffset(text) ?? zone.offsetMinutes ?? 0) * 60)
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
        // With no offset the span was resolved in UTC, which is a convenience,
        // not a fact. The true instant can be up to 14 hours either side, so
        // the overlap test widens by that much — never wrongly excluding — and
        // the answer can never be `.definite`, because definite membership is
        // exactly the claim an unknown offset cannot support.
        guard let possible = possibleSpan else { return nil }
        if possible.end <= range.start || possible.start >= range.end { return nil }
        if hasKnownOffset && possible.start >= range.start && possible.end <= range.end { return .definite }
        return .potential
    }

    /// Bounds of uncertainty, not invented occurrence times.
    var possibleSpan: (start: Date, end: Date)? {
        guard let span else { return nil }
        let margin = hasKnownOffset ? 0 : Self.maxOffset
        return (span.start.addingTimeInterval(-margin), span.end.addingTimeInterval(margin))
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
        guard isKnown, Self.shapeMatches(text, precision) else { return false }
        if Self.explicitOffset(text) != nil { return true }
        return zone.offsetMinutes.map { abs($0) <= 14 * 60 } ?? false
    }

    static func explicitOffset(_ text: String) -> Int? {
        guard text.contains("T") else { return nil }
        if text.hasSuffix("Z") || text.hasSuffix("z") { return 0 }
        guard let range = text.range(of: #"[+-][0-9]{2}:?[0-9]{2}$"#, options: .regularExpression) else { return nil }
        let suffix = String(text[range]).replacingOccurrences(of: ":", with: "")
        guard let h = Int(suffix.dropFirst().prefix(2)), let m = Int(suffix.suffix(2)),
              h <= 14, m < 60, h != 14 || m == 0 else { return nil }
        return (suffix.first == "-" ? -1 : 1) * (h * 60 + m)
    }

    static func localText(_ text: String) -> String {
        guard explicitOffset(text) != nil else { return text }
        if text.hasSuffix("Z") || text.hasSuffix("z") { return String(text.dropLast()) }
        let suffixLength = text.suffix(6).contains(":") ? 6 : 5
        return String(text.dropLast(suffixLength))
    }
}
