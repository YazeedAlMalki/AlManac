import Foundation

/// The vocabulary the program layer introduces above a single session.
///
/// Slice 4's `TrainingVocabulary.swift` holds the two vocabularies
/// `prescription-model-v0.1.md` had: twelve **prescription types** (what kind
/// of work a bout is) and ten **container types** (how a session's bouts hang
/// together). This file is the third set, and it is a different shape of
/// problem from those two. Those were transcriptions — the raw values are the
/// model's, and `TrainingVocabularyTests` asserts the enums equal the arrays on
/// `Migration016_TrainingSchema` so a transcription cannot drift.
///
/// Nothing here is transcribed, because the source is not readable. The
/// 2026-10-01 handoff names the four values it wants and the rest of the model
/// has to be reconstructed from what survives; every reconstruction below says
/// so in its own doc comment and is overruleable from one place.

/// The equipment a movement is performed with, for one exercise.
///
/// **Decision 1 (2026-10-01 handoff):** variants are tracked *separately* by
/// default — a dumbbell fly and a cable fly are distinct entries in the log,
/// and only the graphs choose to draw them together. The consequence, which is
/// the whole reason this is a closed set rather than free text: a free-text
/// variant would produce `"DB"`, `"Dumbbells"` and `"dumbbell"` in the same
/// column and silently render three lines where the graph should show one.
///
/// Five values, not four-plus-a-null. `nil` is a real state on the *log* side
/// (`workoutBout.equipmentVariant` is nullable, because a bodyweight movement
/// genuinely has no variant and pre-slice history has none recorded), so null is
/// modelled by the column being null rather than by a fifth case here.
public enum EquipmentVariant: String, Sendable, Hashable, CaseIterable, Codable {
    case barbell
    case dumbbell
    case cable
    case machine

    public var displayName: String {
        switch self {
        case .barbell:   return localized("Barbell")
        case .dumbbell:  return localized("Dumbbell")
        case .cable:     return localized("Cable")
        case .machine:   return localized("Machine")
        }
    }

    /// The small-print note Decision 1 requires under a graph in combined mode.
    ///
    /// A property rather than a string literal at the call site, because the
    /// note has to appear on *both* graphs (weight and volume) and two hand-typed
    /// copies of a caveat are how one of them ends up wrong.
    public static var combinedModeFootnote: String {
        localized("Equipment variants may not be directly comparable.")
    }
}

/// Whether a progress graph draws one line per equipment variant or one line for
/// all of them.
///
/// **Decision 1:** "Separate" | "Combined", a radio button on the graph itself,
/// and it applies to both graphs of the exercise. One mode covers both because
/// a graph that disagreed with the graph above it would be asking the question
/// twice with different answers.
public enum EquipmentVariantDisplay: String, Sendable, Hashable, CaseIterable, Codable {
    case separate
    case combined

    public var displayName: String {
        switch self {
        case .separate: return localized("Separate")
        case .combined: return localized("Combined")
        }
    }

    /// True when the mode needs the "may not be directly comparable" note.
    public var showsComparabilityFootnote: Bool { self == .combined }
}

/// When a per-exercise progression rule proposes its next load.
///
/// **Decision 4 (2026-10-01 handoff):** the rule is set by the user *per
/// exercise*, never as a global rule — not a fixed "+2.5 kg" applied
/// everywhere. The increment is therefore stored beside the condition on the
/// pool item (`progressionIncrementKg`, `progressionCondition`), and this enum
/// is the closed set the second one may hold.
///
/// **One case, and that is deliberate.** The handoff names `all_reps_completed`
/// and nothing else; it also makes the rule user-defined, which means the set of
/// conditions is product surface nobody has designed yet. The schema holds a
/// closed set (so an invented string cannot be written and then silently fail
/// to match any condition) with exactly the one condition that was actually
/// named. Adding a condition is a migration, and the decision belongs to the
/// owner.
///
/// *Overrule by:* adding cases here and to the CHECK constraint in
/// `Migration049_TrainingProgram`.
public enum ProgressionCondition: String, Sendable, Hashable, CaseIterable, Codable {
    /// Every prescribed set was completed at the prescribed rep count. The only
    /// condition the handoff names, as its own worked example.
    case allRepsCompleted = "all_reps_completed"

    public var displayName: String {
        switch self {
        case .allRepsCompleted: return localized("Every set hit the prescribed reps")
        }
    }
}

/// How one exercise was made unavailable, and what that does to the rotation.
///
/// **Decision 3 (2026-10-01 handoff)** separates two mechanisms that share one
/// prompt, and the separation is the load-bearing part:
///
/// | Case | Mechanism | Effect on the rotation |
/// |---|---|---|
/// | `permanent` | `is_active = false` | Never offered again until re-added by hand. |
/// | perSession | nothing is written to the pool | **Holds its position.** Re-offered next time this day type comes up. |
///
/// The handoff is explicit that the reason is informational and the mechanism
/// is what a caller chooses: dislike and lack-of-equipment both resolve to
/// `permanent`, and neither is ever a per-session skip. This enum exists so that
/// is a type-level fact rather than a convention three call sites have to agree
/// on — `perSession` has no database effect at all, and a caller that reaches
/// for it expecting a row to write will find there is nothing to write.
public enum ExerciseAvailability {
    /// Remove from the rotation: writes `is_active = false`, and the item is
    /// never offered again until the user re-adds it.
    case permanent
    /// Skip this one occurrence: writes no pool state whatsoever, and the item
    /// keeps its `rotationPosition` so it is offered again next time.
    case perSession

    /// Only `permanent` touches the pool. Stated rather than left implicit,
    /// because the asymmetry is the whole content of Decision 3 and it is the
    /// sort of thing a future call site gets wrong by assuming both are writes.
    public var mutatesPool: Bool { self == .permanent }
}
