import Foundation

/// The ten container types, §3 of prescription-model-v0.1.md.
///
/// An enum because `containerType` is what decides *how* a template's bouts hang
/// together — a ladder and a circuit are different objects that happen to share
/// a table — and a caller who can only spell `"amrap"` correctly by hand will
/// eventually not. The raw values are the model's, not invented here, and
/// `TrainingVocabularyTests` asserts the two lists stay identical so a
/// transcription cannot drift.
public enum TrainingContainer: String, Sendable, Hashable, CaseIterable {
    case straightSets = "straight_sets"
    case superset
    case circuit
    case emom
    case amrap
    case forTime = "for_time"
    case intervalBlock = "interval_block"
    case ladder
    case skillBlock = "skill_block"
    case flow

    public var displayName: String {
        switch self {
        case .straightSets: return "Straight sets"
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        case .emom: return "Every minute on the minute"
        case .amrap: return "As many rounds as possible"
        case .forTime: return "For time"
        case .intervalBlock: return "Interval block"
        case .ladder: return "Ladder"
        case .skillBlock: return "Skill block"
        case .flow: return "Flow"
        }
    }
}

/// The twelve prescription types, §2 of the same model.
///
/// This is the one that decides **which fields a bout fills in** — a bout only
/// ever writes the group its prescription type calls for, everything else stays
/// `nil` rather than zero (see `WorkoutBoutDraft`'s header). Getting this
/// wrong in a UI would mean asking someone for a load when they did a timed
/// hold, so the grouping is stated here rather than left to each call site.
public enum PrescriptionKind: String, Sendable, Hashable, CaseIterable {
    case repsLoad = "reps_load"
    case repsBodyweight = "reps_bodyweight"
    case timeUnderLoad = "time_under_load"
    case distance
    case duration
    case roundsForTime = "rounds_for_time"
    case workInTime = "work_in_time"
    case interval
    case qualityReps = "quality_reps"
    case holdStretch = "hold_stretch"
    case `release`
    case sessionOnly = "session_only"

    public var displayName: String {
        switch self {
        case .repsLoad: return "Reps and load"
        case .repsBodyweight: return "Reps, bodyweight"
        case .timeUnderLoad: return "Time under load"
        case .distance: return "Distance"
        case .duration: return "Duration"
        case .roundsForTime: return "Rounds for time"
        case .workInTime: return "Work in time"
        case .interval: return "Intervals"
        case .qualityReps: return "Quality reps"
        case .holdStretch: return "Hold or stretch"
        case .release: return "Release"
        case .sessionOnly: return "Session only"
        }
    }

    /// True when this type records a load, so a bout editor can skip the field.
    ///
    /// Stated rather than inferred from a name: "reps_bodyweight" and
    /// "quality_reps" both contain `reps` and neither takes a load, so any
    /// substring rule would be wrong on two of twelve.
    public var recordsLoad: Bool {
        switch self {
        case .repsLoad, .timeUnderLoad, .duration, .distance: return true
        default: return false
        }
    }

    /// True when this type records a count of repetitions.
    public var recordsReps: Bool {
        switch self {
        case .repsLoad, .repsBodyweight, .qualityReps: return true
        default: return false
        }
    }

    /// True when this type records a clock duration in seconds.
    public var recordsDuration: Bool {
        switch self {
        case .timeUnderLoad, .duration, .holdStretch: return true
        default: return false
        }
    }

    /// True when this type records a distance.
    public var recordsDistance: Bool { self == .distance }

    /// True when this type records a count of rounds.
    ///
    /// Only `rounds_for_time`. AMRAP also counts rounds, but AMRAP is a
    /// *container* (`TrainingContainer.amrap`) and a container is not a
    /// prescription type. A bout inside one still says `rounds_for_time` or
    /// `reps_bodyweight` about what the work was, while the container says how
    /// the work was arranged.
    public var recordsRounds: Bool { self == .roundsForTime }
}
