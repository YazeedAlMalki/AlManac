import Foundation

/// Spec §9 / §5.23. Readiness formula v1.0 vocabulary.
///
/// Everything here is a stored field on `readiness_record`, so these types are
/// the schema's enum columns rather than convenience wrappers: the raw values
/// are exactly the strings the spec writes.

/// §9.1 — provisional is computed from automatic inputs alone; final includes
/// the mood/soreness check-in.
public enum ReadinessState: String, Sendable, Hashable, Codable {
    case provisional
    case final
}

/// §9.5 — derived from how many inputs were missing, never chosen by hand.
public enum ReadinessConfidence: String, Sendable, Hashable, Codable {
    case high
    case medium
    case low
    case veryLow = "very_low"
    case insufficient
}

/// §9.3
public enum ReadinessColor: String, Sendable, Hashable, Codable {
    case green, yellow, red, none
}

/// The five inputs, named as they appear in `missingInputs`.
public enum ReadinessInputKind: String, Sendable, Hashable, Codable, CaseIterable {
    case sleep          // I1 — duration
    case sleepQuality   // I2 — stage breakdown
    case rhr            // I3
    case hrv            // I4
    case mood           // I5a
    case soreness       // I5b
}

/// §9.8 — which baseline the score was measured against.
public enum ReadinessBaselineContext: String, Sendable, Hashable, Codable {
    case general
    case shiftSpecific = "shift_specific"
    case ramadan
    case calibration
}

/// §9.6 — the precedence rules that fired, recorded so a recommendation can be
/// explained after the fact.
public enum ReadinessPrecedence: String, Sendable, Hashable, Codable {
    case injuryRestriction = "injury_restriction"
    case manualRecovery = "manual_recovery"
    case restDay = "rest_day"
    case deload = "deload"
    case religiousFastContext = "religious_fast_context"
}

/// Sleep stage split, as fractions of the episode (0...1).
public struct SleepStageBreakdown: Sendable, Hashable, Codable {
    public let deep: Double
    public let rem: Double
    public let core: Double

    public init(deep: Double, rem: Double, core: Double) {
        self.deep = deep
        self.rem = rem
        self.core = core
    }
}

/// §9.8 — the rolling averages a score is measured against. Nil fields mean the
/// baseline has nothing to say about that metric yet, which is different from a
/// missing reading and is handled separately.
public struct ReadinessBaseline: Sendable, Hashable, Codable {
    public let context: ReadinessBaselineContext
    public let restingHeartRate: Double?
    public let hrv: Double?
    public let validDayCount: Int

    public init(context: ReadinessBaselineContext = .general,
                restingHeartRate: Double? = nil,
                hrv: Double? = nil,
                validDayCount: Int = 0) {
        self.context = context
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.validDayCount = validDayCount
    }
}

/// The raw readings for one readiness cycle.
public struct ReadinessInputs: Sendable, Hashable, Codable {
    /// Primary sleep episode duration. Nil when no primary sleep was found.
    public var sleepDurationMinutes: Int?
    /// Stage split from HealthKit. Nil is expected and supported — §9.2 scores
    /// it 50 and flags it, rather than excluding it.
    public var stages: SleepStageBreakdown?
    public var restingHeartRate: Double?
    public var hrv: Double?
    /// 1–10, from the check-in. Nil for a provisional score by definition.
    public var mood: Int?
    /// 1–10, where 10 is worst. Inverted by the scorer.
    public var soreness: Int?
    /// Total sleep across every episode of the cycle, used only by the Ramadan
    /// modifier, which is about fragmentation rather than one episode.
    public var totalSleepAcrossEpisodesMinutes: Int?

    public init(sleepDurationMinutes: Int? = nil,
                stages: SleepStageBreakdown? = nil,
                restingHeartRate: Double? = nil,
                hrv: Double? = nil,
                mood: Int? = nil,
                soreness: Int? = nil,
                totalSleepAcrossEpisodesMinutes: Int? = nil) {
        self.sleepDurationMinutes = sleepDurationMinutes
        self.stages = stages
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.mood = mood
        self.soreness = soreness
        self.totalSleepAcrossEpisodesMinutes = totalSleepAcrossEpisodesMinutes
    }
}

/// Everything outside the readings that changes what the user is told:
/// §9.4 suffixes and §9.6 precedence.
public struct ReadinessContext: Sendable, Hashable, Codable {
    public var activeInjuryBodyArea: String?
    public var injuryAffectsTraining: Bool
    public var manualRecoveryDay: Bool
    public var plannedRestDay: Bool
    public var plannedDeloadDay: Bool
    public var religiousFastDay: Bool
    /// A session is planned before iftar on a religious fast day.
    public var fastedSessionPlanned: Bool
    public var shiftTransition: Bool
    /// Valid days so far, while below 21. Nil once calibration is complete.
    public var calibrationDay: Int?

    public init(activeInjuryBodyArea: String? = nil,
                injuryAffectsTraining: Bool = false,
                manualRecoveryDay: Bool = false,
                plannedRestDay: Bool = false,
                plannedDeloadDay: Bool = false,
                religiousFastDay: Bool = false,
                fastedSessionPlanned: Bool = false,
                shiftTransition: Bool = false,
                calibrationDay: Int? = nil) {
        self.activeInjuryBodyArea = activeInjuryBodyArea
        self.injuryAffectsTraining = injuryAffectsTraining
        self.manualRecoveryDay = manualRecoveryDay
        self.plannedRestDay = plannedRestDay
        self.plannedDeloadDay = plannedDeloadDay
        self.religiousFastDay = religiousFastDay
        self.fastedSessionPlanned = fastedSessionPlanned
        self.shiftTransition = shiftTransition
        self.calibrationDay = calibrationDay
    }
}

/// One computed score, shaped to be written straight into `readiness_record`.
public struct ReadinessOutcome: Sendable, Hashable {
    public let state: ReadinessState
    /// Nil when §9.1's "insufficient data" branch fired. Never zero as a
    /// stand-in for absent — that substitution is the thing R-RDY forbids.
    public let score: Int?
    public let color: ReadinessColor
    public let textDescription: String?
    public let confidence: ReadinessConfidence
    public let missingInputs: [ReadinessInputKind]
    public let formulaVersion: String
    /// JSON, deterministic key order, holding every raw value the score used.
    public let inputSnapshot: String
    public let recommendation: String?
    public let precedenceApplied: [ReadinessPrecedence]
    public let baselineContext: ReadinessBaselineContext
}
