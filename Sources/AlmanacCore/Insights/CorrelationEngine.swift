import Foundation

/// BRD §6.16's correlation guardrails demand a displayed
/// "Limited/insufficient state" when a pair doesn't have enough paired data
/// — never a number computed from too few points and passed off as real.
/// `.insufficientData` is that state; `CorrelationEngine` cannot produce an
/// `r` without first clearing the sample-size gate.
public enum CorrelationResult: Sendable, Equatable {
    case insufficientData(sampleSize: Int, minimumRequired: Int)
    case computed(r: Double, sampleSize: Int)
}

/// Pearson correlation with a minimum-sample-size gate, per the Slice 10
/// handoff's "Option A: Pearson/Spearman + thresholds" recommendation.
///
/// This computes association only — the BRD's "never causation" guardrail is
/// a wording rule for whatever UI displays `r`, not something a number can
/// enforce by itself.
public enum CorrelationEngine {
    /// BRD's own worked example: "Need 14+ days of paired data."
    public static let minimumSampleSize = 14

    public static func pearson(
        _ pairs: [(Double, Double)],
        minimumSampleSize: Int = minimumSampleSize
    ) -> CorrelationResult {
        guard pairs.count >= minimumSampleSize else {
            return .insufficientData(sampleSize: pairs.count, minimumRequired: minimumSampleSize)
        }

        let n = Double(pairs.count)
        let meanX = pairs.map(\.0).reduce(0, +) / n
        let meanY = pairs.map(\.1).reduce(0, +) / n

        var numerator = 0.0
        var sumSquaresX = 0.0
        var sumSquaresY = 0.0
        for (x, y) in pairs {
            let dx = x - meanX
            let dy = y - meanY
            numerator += dx * dy
            sumSquaresX += dx * dx
            sumSquaresY += dy * dy
        }

        let denominator = (sumSquaresX * sumSquaresY).squareRoot()
        // Zero variance on either axis (every point the same value) makes
        // "correlation" undefined, not infinite — report no association
        // rather than propagate a NaN into a confidence display.
        let r = denominator == 0 ? 0.0 : numerator / denominator
        return .computed(r: r, sampleSize: pairs.count)
    }
}
