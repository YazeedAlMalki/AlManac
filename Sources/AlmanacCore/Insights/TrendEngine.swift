import Foundation

/// `String`-backed rather than a bare enum, because `TrendSnapshotStore` round-
/// trips this through a TEXT column. It used to do so via
/// `String(describing:)`, which happened to produce `"up"` and matched the
/// reader by luck; a case rename would have silently written a value nothing
/// could read back. A raw value makes the storage representation a decision
/// rather than an accident of the debugger's description.
public enum TrendDirection: String, Sendable, Hashable, CaseIterable {
    case up, down, flat
}

public struct TrendSnapshot: Sendable, Hashable {
    public let average: Double
    public let minimum: Double
    public let maximum: Double
    public let direction: TrendDirection
}

/// Rolling summary + directional change for one metric's recent values, per
/// the Slice 10 handoff's trend-dashboard scope (readiness, sleep, steps,
/// training load for v1). Update cadence (reactive vs. nightly batch) and
/// the trend horizon (7/14/28-day) are caller concerns — this only
/// summarizes whatever window of values it's given.
public enum TrendEngine {
    /// Direction compares the average of the older half of the series to the
    /// average of the newer half, rather than just first-vs-last, so one
    /// noisy endpoint doesn't flip the arrow.
    public static func snapshot(of values: [Double]) -> TrendSnapshot? {
        guard !values.isEmpty else { return nil }

        let average = values.reduce(0, +) / Double(values.count)
        let minimum = values.min()!
        let maximum = values.max()!

        let direction: TrendDirection
        if values.count < 2 {
            direction = .flat
        } else {
            let midpoint = values.count / 2
            let olderHalf = values[..<midpoint]
            let newerHalf = values[midpoint...]
            let olderAverage = olderHalf.reduce(0, +) / Double(olderHalf.count)
            let newerAverage = newerHalf.reduce(0, +) / Double(newerHalf.count)
            if newerAverage > olderAverage {
                direction = .up
            } else if newerAverage < olderAverage {
                direction = .down
            } else {
                direction = .flat
            }
        }

        return TrendSnapshot(average: average, minimum: minimum, maximum: maximum, direction: direction)
    }
}
