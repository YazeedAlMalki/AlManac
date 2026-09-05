import Foundation

/// A logical day. Not a calendar date — the day a body-monitor entry belongs to.
///
/// Stored as a plain `yyyy-MM-dd` string because it is a label, not an instant:
/// arithmetic on it must go through `TimeModel`, which knows the boundary rule.
public struct LogicalDay: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { value }
    public static func < (a: LogicalDay, b: LogicalDay) -> Bool { a.value < b.value }
}

/// Where a logical day starts.
///
/// The Technical Spec defines Almanac's actual rule; that text is unavailable,
/// so the rule is **injected rather than assumed**. `.midnight` is a neutral
/// placeholder, not a decision. `.wakeOffset` is here because a sleep-tracking
/// product almost always needs a boundary in the small hours — an entry at
/// 01:30 usually belongs to the night before, not to the new date.
public enum DayBoundary: Sendable, Hashable {
    case midnight
    /// Day starts this many hours after midnight. 4 means 03:59 belongs to the
    /// previous logical day and 04:00 starts a new one.
    case wakeOffset(hours: Int)

    var offsetHours: Int {
        switch self {
        case .midnight: return 0
        case .wakeOffset(let h): return h
        }
    }
}

/// Maps instants to logical days in a specific timezone.
///
/// All conversions go through `Calendar` with an explicit timezone, so DST
/// transitions and non-Gregorian display calendars stay the calendar's problem
/// rather than becoming arithmetic on 86,400.
public struct TimeModel: Sendable {
    public let timeZone: TimeZone
    public let boundary: DayBoundary
    private let calendar: Calendar

    public init(timeZone: TimeZone, boundary: DayBoundary = .midnight) {
        self.timeZone = timeZone
        self.boundary = boundary
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
    }

    /// The logical day an instant belongs to.
    public func logicalDay(_ instant: Date) -> LogicalDay {
        let shifted = instant.addingTimeInterval(-Double(boundary.offsetHours) * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return LogicalDay(String(format: "%04d-%02d-%02d",
                                 parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
    }

    /// The instant a logical day begins. Nil only for an unparseable label.
    public func start(of day: LogicalDay) -> Date? {
        let bits = day.value.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = boundary.offsetHours
        comps.minute = 0; comps.second = 0
        comps.timeZone = timeZone
        return calendar.date(from: comps)
    }

    /// The half-open interval [start, end) covering a logical day.
    ///
    /// Computed by adding one calendar day, not 86,400 seconds — so a DST
    /// spring-forward day is 23 hours and a fall-back day is 25, which is what
    /// the user actually lived through.
    public func bounds(of day: LogicalDay) -> (start: Date, end: Date)? {
        guard let start = start(of: day),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }

    public func day(after day: LogicalDay) -> LogicalDay? {
        guard let start = start(of: day),
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return logicalDay(next)
    }

    public func contains(_ instant: Date, in day: LogicalDay) -> Bool {
        guard let b = bounds(of: day) else { return false }
        return instant >= b.start && instant < b.end
    }

    /// Riyadh: UTC+3, no DST. The project's home timezone.
    public static func riyadh(boundary: DayBoundary = .midnight) -> TimeModel {
        TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh") ?? TimeZone(secondsFromGMT: 3 * 3600)!,
                  boundary: boundary)
    }
}
