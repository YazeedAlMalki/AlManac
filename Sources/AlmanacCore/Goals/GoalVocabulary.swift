import Foundation

/// The kind of goal a target period was set under.
///
/// §5.2's `goal` column, as a closed set. The alternative is a free string, and
/// then `+300` versus `-500` becomes a lookup keyed on spelling — so a typo is
/// a silent recalculation, and nothing in the schema objects.
public enum GoalKind: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case bulk
    case cut
    case maintain
    case performance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bulk: return "Bulk"
        case .cut: return "Cut"
        case .maintain: return "Maintain"
        case .performance: return "Performance"
        }
    }

    /// The one-line explanation shown beside the picker.
    ///
    /// Every one of these says which way the numbers move, because a person
    /// choosing between "Bulk" and "Performance" is deciding something about
    /// direction and the labels alone do not say it.
    public var explanation: String {
        switch self {
        case .bulk: return "Eat more than you burn, to add mass."
        case .cut: return "Eat less than you burn, to lose mass."
        case .maintain: return "Balance what you eat against what you burn."
        case .performance: return "Hold steady, and train for output."
        }
    }

    /// The daily calorie adjustment §5.2's comment gives for this goal: a kcal
    /// delta added to maintenance, negative for a cut.
    ///
    /// Transcribed from §5.2's own inline comment — "e.g., +300 bulk, -500 cut"
    /// — not invented. It is a *default*, and every one of these is overridable
    /// per snapshot: a 300 kcal surplus is a reasonable starting point and an
    /// unreasonable answer for a person who weighs 50 kg or 120 kg, which is
    /// precisely why the column is stored on the row instead of computed from
    /// the goal at read time. A goal knows its own default; it does not know
    /// whether this person accepted it.
    public var defaultCalorieAdjustment: Int {
        switch self {
        case .bulk: return 300
        case .cut: return -500
        case .maintain: return 0
        case .performance: return 0
        }
    }
}

/// The resting-energy calculation, as named by BRD §6.10.
///
/// **A named published equation, transcribed, not a formula this app designed.**
/// Mifflin-St Jeor has two variants — a constant of `+5` and one of `−161` —
/// and which one applies is decided by biological sex, which is data the person
/// supplies and may decline to.
///
/// What is *not* the published equation is what to do for a person whose sex is
/// `other` or `not_set`, and that is a decision rather than a transcription, so
/// it is made here explicitly and tested rather than left implicit in a
/// constant: `other` uses the mean of the two variants, and `not_set` declines
/// to produce a number at all. The mean is the standard neutral treatment; the
/// refusal is the honest one — a target derived from a body the person did not
/// describe is a number with no source, and returning `nil` lets the caller say
/// "no target set" instead of inventing one.
public enum MifflinStJeor {
    /// Resting energy burn in kcal/day, or `nil` when the inputs do not support
    /// one.
    ///
    /// `nil` rather than zero for every unusable input, because a zero would be
    /// stored as a target and then shown as a number.
    public static func basalMetabolicRate(weightKg: Double,
                                          heightCm: Double,
                                          ageYears: Double,
                                          sex: BiologicalSex) -> Double? {
        guard weightKg > 0, heightCm > 0, ageYears > 0, ageYears < 130 else { return nil }
        let base = (10 * weightKg) + (6.25 * heightCm) - (5 * ageYears)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base + ((5 + -161) / 2)
        case .notSet: return nil
        }
    }
}

/// Biological sex, as §5.1's `biologicalSex` column defines it.
///
/// The closed set is the spec's — `male | female | other | not_set` — and the
/// member that matters is the fourth. `not_set` is not a placeholder for `nil`
/// (which would mean "unknown" and read as an error) and not an alias for
/// `other` (which would claim something the person did not say). It is its own
/// value because the difference has a consequence: `other` produces a resting
/// burn and `not_set` does not, so collapsing them would either fabricate a
/// number or deny a number somebody deserves.
public enum BiologicalSex: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case male
    case female
    case other
    case notSet = "not_set"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        case .notSet: return "Prefer not to say"
        }
    }

    /// Parses a stored `biologicalSex`, with blank and garbage both meaning
    /// `notSet` — because "the app has no idea" and "the person declined to
    /// say" lead to the same place, and the app should not present one as an
    /// error the other is not.
    ///
    /// **Case- and whitespace-insensitive, because the column is free text until
    /// Task F's setup flow replaces it.** `ProfileView` writes whatever the
    /// person typed, so "Male", "FEMALE" and " male" are all values a real
    /// install holds. A case-sensitive parse reads those as `notSet`, which
    /// silently disables calorie-target generation for a person who *has* said —
    /// the failure mode being a number that never appears rather than an error
    /// the person can act on. The values are lower case on the way in now; this
    /// is what makes the values already in the databases harmless.
    public static func parse(_ raw: String?) -> BiologicalSex {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty,
              let parsed = BiologicalSex(rawValue: trimmed) else { return .notSet }
        return parsed
    }
}
