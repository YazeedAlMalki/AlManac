import Foundation

/// Readiness formula v1.0 — Technical Specification §9.1-§9.2, Appendix A.
///
/// Every function here is pure and takes its baseline explicitly. That is what
/// makes §9.9 possible: a historical score can be recomputed from its stored
/// `inputSnapshot` and compared against what today's formula would say, without
/// either one being able to quietly rewrite the other.
public enum ReadinessFormula {

    public static let version = "1.0"

    /// §9.3 presentation bands. These are domain thresholds, not UI copy:
    /// charts and status surfaces should read them from here so a formula
    /// change cannot silently leave a stale reference line behind.
    public static let compromisedThreshold = 40
    public static let readyThreshold = 70

    // MARK: - Weights (Appendix A)

    public struct Weights: Sendable {
        public let sleepDuration: Double
        public let sleepQuality: Double
        public let rhr: Double
        public let hrv: Double
        public let moodSoreness: Double
    }

    /// I1=33%, I2=22%, I3=22%, I4=23%. Mood/soreness has no weight before the
    /// check-in exists.
    public static let provisionalWeights = Weights(
        sleepDuration: 0.33, sleepQuality: 0.22, rhr: 0.22, hrv: 0.23, moodSoreness: 0
    )

    /// I1=30%, I2=20%, I3=20%, I4=20%, I5=10%.
    public static let finalWeights = Weights(
        sleepDuration: 0.30, sleepQuality: 0.20, rhr: 0.20, hrv: 0.20, moodSoreness: 0.10
    )

    /// A provisional score is scaled to a ceiling of 90, so that a user who has
    /// not checked in never sees 100 and reads it as a complete picture.
    public static let provisionalCeiling: Double = 0.90

    // MARK: - §9.2 Input scoring

    /// Sleep duration bands, plus the Ramadan fragmentation modifier.
    ///
    /// The modifier is applied on total sleep across *all* episodes, not on the
    /// primary episode, because the thing it exists to stop penalising is
    /// fragmentation: two four-hour sleeps in Ramadan are not a four-hour night.
    public static func sleepDurationScore(
        minutes: Int,
        religiousFastDay: Bool = false,
        totalAcrossEpisodesMinutes: Int? = nil
    ) -> Double {
        let base: Double
        switch minutes {
        case ..<240:     base = 10
        case 240..<300:  base = 30
        case 300..<360:  base = 55
        case 360..<420:  base = 75
        case 420..<540:  base = 100
        case 540..<600:  base = 90
        default:         base = 75
        }
        guard religiousFastDay, (totalAcrossEpisodesMinutes ?? minutes) >= 300 else { return base }
        return Swift.min(100, base + 10)
    }

    /// Weighted stage quality. Nil stage data scores a neutral 50 and is
    /// flagged missing by the engine — it is not excluded, because excluding it
    /// would silently inflate the weight of the remaining inputs.
    public static func sleepQualityScore(_ stages: SleepStageBreakdown?) -> Double {
        guard let s = stages else { return 50 }
        let raw = (s.deep * 1.4 + s.rem * 1.1 + s.core * 0.7) * 100
        return Swift.min(100, Swift.max(0, raw))
    }

    /// Resting heart rate against personal baseline. Lower than baseline is better.
    public static func rhrScore(current: Double, baseline: Double) -> Double {
        let delta = current - baseline
        if delta <= -2 { return 100 }
        if delta <=  0 { return 95 }
        if delta <=  2 { return 85 }
        if delta <=  4 { return 65 }
        if delta <=  6 { return 40 }
        return 15
    }

    /// HRV against personal baseline, as a percentage difference.
    public static func hrvScore(current: Double, baseline: Double) -> Double {
        guard baseline != 0 else { return 50 }
        let pct = (current - baseline) / baseline * 100
        if pct >=  15 { return 100 }
        if pct >=   5 { return 90 }
        if pct >=  -5 { return 75 }
        if pct >= -15 { return 50 }
        if pct >= -25 { return 30 }
        return 10
    }

    /// Mood and soreness, averaged. Soreness is inverted: 10 means very sore,
    /// which is a low contribution.
    public static func moodSorenessScore(mood: Int, soreness: Int) -> Double {
        let moodNormalised = Double(mood) / 10.0 * 100
        let sorenessNormalised = Double(10 - soreness) / 10.0 * 100
        return (moodNormalised + sorenessNormalised) / 2
    }

    // MARK: - §9.1 Weighting and redistribution

    /// Weighted sum over present inputs only, with missing weight redistributed
    /// proportionally among those that remain.
    ///
    /// Redistribution rather than zero-substitution is the whole point: a
    /// missing HRV reading must not be scored as the worst possible HRV.
    /// Returns nil when nothing is present to weigh.
    public static func weightedSum(_ contributions: [(weight: Double, score: Double)]) -> Double? {
        let totalWeight = contributions.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let sum = contributions.reduce(0) { $0 + $1.weight * $1.score }
        return sum / totalWeight
    }

    // MARK: - §9.3 / §9.4 presentation

    public static func color(for score: Int?) -> ReadinessColor {
        guard let score else { return .none }
        if score >= readyThreshold { return .green }
        if score >= compromisedThreshold { return .yellow }
        return .red
    }

    public static func bandText(for score: Int) -> String {
        switch score {
        case 85...:   return "Recovery is excellent — ready for maximum effort"
        case 70..<85: return "Recovery is good — ready for a strong session"
        case 55..<70: return "Moderate recovery — train at reduced intensity"
        case 40..<55: return "Recovery is below baseline — consider a light session"
        case 25..<40: return "Recovery is poor — prioritise rest today"
        default:      return "Recovery is very low — rest is the best training decision"
        }
    }

    // MARK: - §9.5

    public static func confidence(missingCount: Int) -> ReadinessConfidence {
        switch missingCount {
        case 0:  return .high
        case 1:  return .medium
        case 2:  return .low
        default: return .veryLow
        }
    }

    // MARK: - §9.7

    /// Valid days required before scores stop being preliminary.
    public static let calibrationValidDays = 21
    /// Rolling window for general and shift-specific baselines.
    public static let baselineWindowDays = 28
    /// Valid days on one shift type before its own baseline replaces the general one.
    public static let shiftBaselineActivationDays = 14

    /// §9.7 — a day counts toward calibration if it carried sleep data, or both
    /// a resting heart rate and an HRV reading. A day with neither does not
    /// count, which is why calibration is measured in valid days rather than
    /// calendar days.
    public static func isValidCalibrationDay(hasSleepData: Bool,
                                             hasRHR: Bool,
                                             hasHRV: Bool) -> Bool {
        hasSleepData || (hasRHR && hasHRV)
    }
}
