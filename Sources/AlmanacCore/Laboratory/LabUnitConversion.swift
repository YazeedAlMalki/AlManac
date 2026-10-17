import Foundation

/// Unit conversion for charting one analyte across laboratories —
/// `docs/features/laboratory.md` §8, applied.
///
/// - **R8.1** The source unit text is never changed: conversion produces a
///   value *beside* the source value, with the factor and class it used
///   (R8.2). Nothing here writes to storage.
/// - **R8.3** Decimal scaling within one dimension is applied generally. Mass ↔
///   substance amount needs an analyte-specific factor (molar mass), and the
///   catalog holds none yet, so it is not converted and says so. Activity
///   units need a per-assay factor, so two different activity units are not
///   converted either.
///
/// A percentage, a ratio and a titer are all dimensionless and are still not
/// interchangeable; `UnitRegistry` keeps them as separate dimensions, and so
/// does this.
public enum LabUnitConversion {
    /// R8's four classes.
    public enum ConversionClass: String, Sendable, Hashable {
        case decimalScaling = "decimal_scaling"
        case dimensionless
        case massToSubstance = "mass_to_substance"
        case activity
    }

    public enum Reason: String, Sendable, Hashable {
        /// One of the units is not in `UnitRegistry`.
        case unknownUnit = "unknown_unit"
        /// The units measure different things (a percentage and a ratio).
        case differentDimension = "different_dimension"
        /// Mass ↔ substance amount: needs the analyte's molar mass.
        case needsAnalyteFactor = "needs_analyte_factor"
        /// Two different activity units: needs a per-assay factor.
        case activityUnits = "activity_units"
        /// There is no number to convert (a coded or text result).
        case notNumeric = "not_numeric"
    }

    public enum Outcome: Sendable, Hashable {
        case converted(value: Double, unit: String, factor: Double, conversionClass: ConversionClass)
        case notConverted(Reason)
    }

    public static func convert(_ value: Double?, from source: String?, to target: String) -> Outcome {
        guard let value else { return .notConverted(.notNumeric) }
        guard let source,
              let left = UnitRegistry.table[UnitRegistry.key(source)],
              let right = UnitRegistry.table[UnitRegistry.key(target)] else {
            return .notConverted(.unknownUnit)
        }
        let massOrSubstance: Set<UnitDimension> = [.massPerVolume, .substancePerVolume]
        guard left.dimension == right.dimension else {
            if massOrSubstance.contains(left.dimension) && massOrSubstance.contains(right.dimension) {
                return .notConverted(.needsAnalyteFactor)
            }
            return .notConverted(.differentDimension)
        }
        let conversionClass = Self.conversionClass(of: left.dimension)
        let sameUnit = UnitRegistry.key(source) == UnitRegistry.key(target)
        if conversionClass == .activity && !sameUnit {
            return .notConverted(.activityUnits)
        }
        let factor = left.scale / right.scale
        return .converted(value: value * factor, unit: target, factor: factor, conversionClass: conversionClass)
    }

    static func conversionClass(of dimension: UnitDimension) -> ConversionClass {
        switch dimension {
        case .percentage, .ratio, .titer: return .dimensionless
        case .activityPerVolume: return .activity
        case .massPerVolume, .substancePerVolume, .mass, .volume, .cellsPerVolume: return .decimalScaling
        }
    }

    // MARK: - A series in one unit

    public struct Reading: Sendable, Hashable {
        public let id: String
        public let value: Double?
        public let unit: String?
        public init(id: String, value: Double?, unit: String?) {
            self.id = id
            self.value = value
            self.unit = unit
        }
    }

    public struct Point: Sendable, Hashable {
        public let id: String
        public let value: Double
        public let sourceValue: Double
        public let sourceUnit: String
        public let factor: Double
        public let conversionClass: ConversionClass
    }

    public struct Excluded: Sendable, Hashable {
        public let id: String
        public let reason: Reason
    }

    public struct Series: Sendable, Hashable {
        /// The unit every point is in: the latest reading's. Nil when no
        /// reading has a unit.
        public let unit: String?
        public let points: [Point]
        /// Readings that could not join the series, each with why — a reading
        /// left off a chart must never disappear without a reason.
        public let excluded: [Excluded]
    }

    /// Puts readings (oldest first) into the unit of the latest one that has a
    /// number and a unit. Unconfirmed choice of target unit — `CONTEXT.md`.
    public static func series(_ readings: [Reading]) -> Series {
        guard let target = readings.last(where: { $0.value != nil && $0.unit != nil })?.unit else {
            return Series(unit: nil, points: [],
                          excluded: readings.map { Excluded(id: $0.id, reason: $0.value == nil ? .notNumeric : .unknownUnit) })
        }
        var points: [Point] = []
        var excluded: [Excluded] = []
        for reading in readings {
            switch convert(reading.value, from: reading.unit, to: target) {
            case let .converted(value, _, factor, conversionClass):
                points.append(Point(id: reading.id, value: value, sourceValue: reading.value ?? value,
                                    sourceUnit: reading.unit ?? target, factor: factor,
                                    conversionClass: conversionClass))
            case let .notConverted(reason):
                excluded.append(Excluded(id: reading.id, reason: reason))
            }
        }
        return Series(unit: target, points: points, excluded: excluded)
    }
}

/// When to measure an analyte again, from the person's own history.
///
/// **Unconfirmed build rule** (`CONTEXT.md`, "Laboratory (2026-10-15)"): the
/// suggested day is the last result's day plus the median of the intervals
/// between the person's own consecutive results for that analyte, from at
/// least three results on distinct days. No clinical interval is used or
/// invented; a person with no cadence yet gets no suggestion.
public enum LabRetestSuggestion {
    public static let minimumResults = 3

    public struct Suggestion: Sendable, Hashable {
        public let lastDay: String
        public let typicalIntervalDays: Int
        public let suggestedDay: String
        /// Distinct result days the cadence was read from.
        public let basedOn: Int
        /// The suggested day is today or earlier.
        public let isDue: Bool
    }

    /// The `YYYY-MM-DD` of each result dated to at least a day. Coarser dates
    /// (month, year, unknown) are left out rather than guessed into a day.
    public static func collectionDays(_ times: [PartialDateTime]) -> [String] {
        times.filter { $0.precision.rank >= TimePrecision.day.rank && $0.text.count >= 10 }
            .map { String($0.text.prefix(10)) }
    }

    public static func suggest(collectionDays: [String], today: String) -> Suggestion? {
        let days = Array(Set(collectionDays)).sorted()
        guard days.count >= minimumResults else { return nil }
        let dates = days.compactMap(Self.date(from:))
        guard dates.count == days.count, let last = dates.last, let lastDay = days.last else { return nil }
        let intervals = zip(dates, dates.dropFirst()).map { pair in
            Self.calendar.dateComponents([.day], from: pair.0, to: pair.1).day ?? 0
        }.sorted()
        let middle = intervals.count / 2
        let median = intervals.count.isMultiple(of: 2)
            ? Int((Double(intervals[middle - 1] + intervals[middle]) / 2).rounded())
            : intervals[middle]
        guard median > 0,
              let next = Self.calendar.date(byAdding: .day, value: median, to: last) else { return nil }
        let suggestedDay = Self.formatter.string(from: next)
        return Suggestion(lastDay: lastDay, typicalIntervalDays: median, suggestedDay: suggestedDay,
                          basedOn: days.count, isDue: suggestedDay <= today)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func date(from day: String) -> Date? { formatter.date(from: day) }
}
