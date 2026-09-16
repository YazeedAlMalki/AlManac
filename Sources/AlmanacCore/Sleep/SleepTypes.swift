import Foundation

/// A single HealthKit sleep sample, as `HKCategoryValueSleepAnalysis` delivers it.
///
/// Stages are kept distinct rather than collapsed to "asleep" because the
/// readiness quality score (spec §9.2) weights deep, REM and core differently.
/// `awake` samples are part of an episode's span — a three-minute wake at 03:00
/// does not end the night — but they do not count as time asleep.
public enum SleepStage: String, Sendable, Hashable, Codable, CaseIterable {
    case inBed
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake

    /// Whether this stage counts toward time actually asleep.
    ///
    /// `inBed` is excluded: it is a bed-occupancy signal, not a sleep signal,
    /// and on devices that emit both it fully overlaps the asleep stages.
    /// Counting it would double the night.
    public var isAsleep: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM: return true
        case .inBed, .awake: return false
        }
    }
}

public struct SleepStageSample: Sendable, Hashable, Codable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage
    public let sourceApp: String?
    public let sourceDevice: String?
    public let healthKitUUID: String?

    public init(start: Date, end: Date, stage: SleepStage,
                sourceApp: String? = nil, sourceDevice: String? = nil,
                healthKitUUID: String? = nil) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceApp = sourceApp
        self.sourceDevice = sourceDevice
        self.healthKitUUID = healthKitUUID
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Spec §5.6 `episodeType`.
public enum SleepEpisodeType: String, Sendable, Hashable, Codable {
    case primary
    case nap
    case split
    case recovery
    case postShift = "post_shift"
}

/// Spec §5.6 `source`.
public enum SleepEpisodeSource: String, Sendable, Hashable, Codable {
    case healthkit
    case manual
    case appGenerated = "app_generated"
}

/// One merged sleep episode: a span of samples with no gap longer than
/// `SleepClassifier.episodeGapMinutes` between them.
public struct SleepEpisode: Sendable, Hashable, Codable {
    public var start: Date
    public var end: Date
    public var type: SleepEpisodeType
    public var source: SleepEpisodeSource
    /// Time in stages that count as asleep, which is not the same as
    /// `end - start`: an episode spanning a 20-minute awake stage is that
    /// much shorter in asleep minutes.
    public var asleepMinutes: Int
    public var sourceApp: String?
    public var sourceDevice: String?
    public var healthKitUUIDs: [String]
    /// Set only when the user overrides the classifier (spec §8.2 step 1).
    public var userCorrectedType: SleepEpisodeType?

    public init(start: Date, end: Date, type: SleepEpisodeType,
                source: SleepEpisodeSource, asleepMinutes: Int,
                sourceApp: String? = nil, sourceDevice: String? = nil,
                healthKitUUIDs: [String] = [], userCorrectedType: SleepEpisodeType? = nil) {
        self.start = start
        self.end = end
        self.type = type
        self.source = source
        self.asleepMinutes = asleepMinutes
        self.sourceApp = sourceApp
        self.sourceDevice = sourceDevice
        self.healthKitUUIDs = healthKitUUIDs
        self.userCorrectedType = userCorrectedType
    }

    /// Wall-clock span in minutes, stored on the row as `durationMinutes`.
    public var spanMinutes: Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }

    /// The type in force: a user correction always wins (spec §8.2 step 1,
    /// "honour unconditionally").
    public var effectiveType: SleepEpisodeType { userCorrectedType ?? type }
}

/// Spec §5.5 `shift_occurrence.shiftType`.
public enum ShiftType: String, Sendable, Hashable, Codable {
    case day, evening, night, split, rest, custom
    case onCall = "on_call"
}

/// The shift facts the classifier needs for one date. Assembled from
/// `shift_occurrence`; absent entirely when the user has no shift schedule,
/// which is the ordinary case and must stay a supported one (spec §6.11:
/// the user "can disable entirely if irrelevant").
public struct ShiftContext: Sendable, Hashable {
    public let date: LogicalDay
    public let shiftType: ShiftType
    /// Absolute instant the shift ended, when known. Used by the post-shift
    /// rule, which is defined against the shift's end, not its type.
    public let shiftEnd: Date?
    /// Absolute instant the user was expected to wake, when known.
    public let expectedWake: Date?

    public init(date: LogicalDay, shiftType: ShiftType,
                shiftEnd: Date? = nil, expectedWake: Date? = nil) {
        self.date = date
        self.shiftType = shiftType
        self.shiftEnd = shiftEnd
        self.expectedWake = expectedWake
    }
}
