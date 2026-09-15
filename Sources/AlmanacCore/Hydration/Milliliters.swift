import Foundation

/// A volume, always milliliters.
///
/// Exists only at the Swift API boundary, to make passing fluid ounces or a
/// glass count where the store expects mL a type error rather than a silent
/// unit bug. The storage column (`hydration_log.amount_ml`) stays a plain
/// `REAL`, matching the rest of this codebase's convention of not adding a
/// separate `unit` column where there is only ever one unit to vary over.
public struct Milliliters: Sendable, Hashable, Comparable, Codable {
    public let value: Double

    public init(_ value: Double) { self.value = value }

    public static let zero = Milliliters(0)

    public static func < (a: Milliliters, b: Milliliters) -> Bool { a.value < b.value }
    public static func + (a: Milliliters, b: Milliliters) -> Milliliters { Milliliters(a.value + b.value) }
}
