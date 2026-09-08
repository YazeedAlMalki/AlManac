import Foundation

/// How precisely a time is known.
///
/// A report that printed only "March 2019" is stored at `.month` and stays
/// there. Nothing below the stated precision is ever invented.
public enum TimePrecision: String, Codable, Sendable, CaseIterable, Hashable {
    case unknown, year, month, day, hour, minute, instant

    public var rank: Int {
        switch self {
        case .unknown: return 0
        case .year:    return 1
        case .month:   return 2
        case .day:     return 3
        case .hour:    return 4
        case .minute:  return 5
        case .instant: return 6
        }
    }

    /// Whether records at this precision may be ordered against each other
    /// inside a single day. Coarser records group as time-unknown instead.
    public var isOrderableWithinDay: Bool { rank >= TimePrecision.minute.rank }
}

/// Time-zone context as known at the moment a time was recorded.
///
/// Both members are optional because a historical paper report frequently
/// states neither. An unknown zone is a recorded fact, not a reason to
/// substitute the device's current one.
public struct ZoneContext: Codable, Sendable, Hashable {
    public let offsetMinutes: Int?
    public let identifier: String?

    public init(offsetMinutes: Int? = nil, identifier: String? = nil) {
        self.offsetMinutes = offsetMinutes
        self.identifier = identifier
    }

    public static let unknown = ZoneContext()
    public var isKnown: Bool { offsetMinutes != nil || identifier != nil }

    public init(_ timeZone: TimeZone, at instant: Date = Date()) {
        self.offsetMinutes = timeZone.secondsFromGMT(for: instant) / 60
        self.identifier = timeZone.identifier
    }
}

/// A time known only to a stated precision.
///
/// `text` is an ISO-8601 **prefix**, never padded:
/// `"2019"`, `"2019-03"`, `"2019-03-14"`, `"2019-03-14T08:10"`,
/// `"2019-03-14T08:10:32Z"`. Because the prefixes sort lexically in
/// chronological order, a coarse value sorts at the start of its own span,
/// which is where a time-unknown record belongs.
public struct PartialDateTime: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let text: String
    public let precision: TimePrecision
    public let zone: ZoneContext

    public init(text: String, precision: TimePrecision, zone: ZoneContext = .unknown) {
        self.text = text
        self.precision = precision
        self.zone = zone
    }

    public static let unknown = PartialDateTime(text: "", precision: .unknown, zone: .unknown)

    /// A fully known instant. The only constructor that produces `.instant`.
    public init(instant: Date, zone: ZoneContext) {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let minutes = zone.offsetMinutes {
            f.timeZone = TimeZone(secondsFromGMT: minutes * 60) ?? TimeZone(secondsFromGMT: 0)!
        } else {
            f.timeZone = TimeZone(secondsFromGMT: 0)!
        }
        self.text = f.string(from: instant)
        self.precision = .instant
        self.zone = zone
    }

    /// Reads a stored value back, deriving precision from its shape.
    /// Returns nil for text that is not an ISO-8601 prefix.
    public init?(storedText: String, precision: TimePrecision, zone: ZoneContext = .unknown) {
        if precision == .unknown {
            self.init(text: "", precision: .unknown, zone: zone)
            return
        }
        guard PartialDateTime.shapeMatches(storedText, precision) else { return nil }
        self.init(text: storedText, precision: precision, zone: zone)
    }

    static func shapeMatches(_ s: String, _ p: TimePrecision) -> Bool {
        func digits(_ t: Substring) -> Bool { t.allSatisfy(\.isNumber) }
        switch p {
        case .unknown: return s.isEmpty
        case .year:    return s.count == 4 && digits(s[...])
        case .month:   return s.count == 7 && s.dropFirst(4).first == "-"
        case .day:     return s.count == 10 && s.dropFirst(7).first == "-"
        case .hour:    return s.count == 13 && s.contains("T")
        case .minute:  return s.count == 16 && s.contains("T")
        case .instant: return s.count >= 19 && s.contains("T")
        }
    }

    /// The `yyyy-MM-dd` prefix when the value is at least day-precise.
    /// Nil for month, year and unknown — those name no single day.
    public var datePrefix: String? {
        guard precision.rank >= TimePrecision.day.rank, text.count >= 10 else { return nil }
        return String(text.prefix(10))
    }

    public var isKnown: Bool { precision != .unknown }
    public var description: String { isKnown ? text : "unknown" }

    /// Total order. Unknown sorts last; otherwise chronological by prefix,
    /// with coarser precision first when one prefixes the other.
    public static func < (a: PartialDateTime, b: PartialDateTime) -> Bool {
        switch (a.isKnown, b.isKnown) {
        case (false, false): return false
        case (false, true):  return false
        case (true, false):  return true
        case (true, true):
            if a.text != b.text { return a.text < b.text }
            return a.precision.rank < b.precision.rank
        }
    }
}
