import Foundation

/// The targets in force from one day, as one immutable row.
///
/// ## What a snapshot is for
///
/// Two different questions, and a snapshot is the answer to the second one.
/// "What is my target weight?" is a question about *now* and has one answer. "What
/// was my target weight on the 14th?" is a question about the past, and if the
/// answer is not stored then a chart of the last month is silently rewritten every
/// time a goal changes — the 14th's bar moves because of something typed on the
/// 20th. That is the reason §5.2 says rows are never updated, and it is the reason
/// this type has no `update`.
///
/// ## Why a whole row rather than one row per target
///
/// §5.2's shape, kept. A goal, an activity assumption, a calorie adjustment and
/// the targets computed from them are one thought, and a target that outlives the
/// assumption behind it is a number nobody can re-derive or audit. Splitting them
/// across tables would buy normalised rows and cost the ability to ask "why was
/// this target 2,400?" — which is the question the `formula_version` column
/// exists to answer.
///
/// ## What is generated and what is chosen
///
/// The calorie target is *generated* from the resting burn, the activity multiplier
/// and the goal's adjustment. The body-composition targets are *chosen*: nothing
/// computes a target body-fat percentage. That difference is carried explicitly —
/// `isTargetManual` is `false` only where a formula produced the number — because a
/// computed target and a typed one deserve different trust, and a card that showed
/// them with the same confidence would be overstating one of them.
///
/// ## What is absent, and why that is normal
///
/// On a fresh install there is no snapshot at all, and every target here is
/// `nil`. That is not a broken state to be repaired; it is the state of an app
/// that has not been told anything. A height, a weight, an activity level and a
/// goal are four things a person has to supply, and until they do, every target
/// is `nil` and every card says "No target set".
public struct GoalTargetSnapshot: Sendable, Hashable, Identifiable {
    public let id: Int64
    /// The first day these targets apply, `YYYY-MM-DD`.
    public let effectiveDate: String
    public let goal: GoalKind
    /// Which version of the target formula produced the generated numbers.
    /// Kept on the row because a target outlives the code that made it, and a
    /// re-derivation six months later has to know whether it may.
    public let formulaVersion: String

    // The inputs, kept so a target can be re-derived and questioned.
    public let bodyWeightKg: Double?
    public let bodyFatPercent: Double?
    public let activityMultiplier: Double?
    public let goalCalorieAdjustment: Int?

    // Generated.
    public let calorieTarget: Int?
    public let proteinTargetG: Double?
    public let carbTargetG: Double?
    public let fatTargetG: Double?
    public let hydrationTargetMl: Int?

    // Manual overrides. §5.2: "stored alongside (never erase) calculated" — so a
    // null here means "no override", never "the generated value is gone".
    public let manualCalorieTarget: Int?
    public let manualProteinTargetG: Double?
    public let manualCarbTargetG: Double?
    public let manualFatTargetG: Double?
    public let manualHydrationTargetMl: Int?

    // Chosen body-composition targets, one per `BodyMetric`.
    public let bodyCompositionTargets: [BodyMetric: Double]

    public let createdAt: Date

    public init(id: Int64 = 0,
                effectiveDate: String,
                goal: GoalKind,
                formulaVersion: String = "1.0",
                bodyWeightKg: Double? = nil,
                bodyFatPercent: Double? = nil,
                activityMultiplier: Double? = nil,
                goalCalorieAdjustment: Int? = nil,
                calorieTarget: Int? = nil,
                proteinTargetG: Double? = nil,
                carbTargetG: Double? = nil,
                fatTargetG: Double? = nil,
                hydrationTargetMl: Int? = nil,
                manualCalorieTarget: Int? = nil,
                manualProteinTargetG: Double? = nil,
                manualCarbTargetG: Double? = nil,
                manualFatTargetG: Double? = nil,
                manualHydrationTargetMl: Int? = nil,
                bodyCompositionTargets: [BodyMetric: Double] = [:],
                createdAt: Date) {
        self.id = id
        self.effectiveDate = effectiveDate
        self.goal = goal
        self.formulaVersion = formulaVersion
        self.bodyWeightKg = bodyWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.activityMultiplier = activityMultiplier
        self.goalCalorieAdjustment = goalCalorieAdjustment
        self.calorieTarget = calorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbTargetG = carbTargetG
        self.fatTargetG = fatTargetG
        self.hydrationTargetMl = hydrationTargetMl
        self.manualCalorieTarget = manualCalorieTarget
        self.manualProteinTargetG = manualProteinTargetG
        self.manualCarbTargetG = manualCarbTargetG
        self.manualFatTargetG = manualFatTargetG
        self.manualHydrationTargetMl = manualHydrationTargetMl
        self.bodyCompositionTargets = bodyCompositionTargets
        self.createdAt = createdAt
    }

    // MARK: - Effective targets
    //
    // "Effective" is the whole of §5.2's override rule: the manual value wins if
    // there is one, and the generated value is still there underneath. Reading
    // them through one pair of accessors is what keeps a caller from picking the
    // generated column when an override exists — the mistake that would show
    // someone a target they had already replaced.

    public var effectiveCalorieTarget: Int? { manualCalorieTarget ?? calorieTarget }
    public var effectiveProteinTargetG: Double? { manualProteinTargetG ?? proteinTargetG }
    public var effectiveCarbTargetG: Double? { manualCarbTargetG ?? carbTargetG }
    public var effectiveFatTargetG: Double? { manualFatTargetG ?? fatTargetG }
    public var effectiveHydrationTargetMl: Int? { manualHydrationTargetMl ?? hydrationTargetMl }

    // MARK: - Body composition

    /// The target for one body-composition metric, in the metric's stored unit
    /// (kg, pct, rating) — never converted, because that is what is in the row and
    /// converting at read time would make the stored value disagree with the shown
    /// one.
    public func targetValue(for metric: BodyMetric) -> Double? {
        bodyCompositionTargets[metric]
    }

    /// Whether the target for `metric` was chosen rather than computed.
    ///
    /// Always `true` for a target that exists today, because nothing generates
    /// one. It is a method rather than a stored column because the answer is a
    /// property of *which* target is being asked about, and a column would have
    /// to be nullable and then duplicated across two sets of columns.
    public func isManualTarget(for metric: BodyMetric) -> Bool {
        bodyCompositionTargets[metric] != nil
    }

    /// This snapshot keyed by each metric it carries a target for, in the shape
    /// `BodyCompositionProgress.all` wants.
    ///
    /// The one method that crosses between the two types, so the mapping is in one
    /// place rather than rebuilt at each call site. Takes one snapshot, not a list:
    /// a list would imply a per-metric merge, and the merge is exactly the rule
    /// that made a cleared target impossible to remove.
    public func targetMap() -> [BodyMetric: GoalTargetSnapshot] {
        var out: [BodyMetric: GoalTargetSnapshot] = [:]
        for metric in BodyMetric.allCases where bodyCompositionTargets[metric] != nil {
            out[metric] = self
        }
        return out
    }
}

/// Builds a snapshot from a person's stated inputs.
///
/// ## Why this is a value, not a static function
///
/// The inputs are four separate numbers a person supplied, and the outputs are
/// five. A builder makes the *invalid* combinations impossible to construct rather
/// than to notice: there is no path from here to a snapshot carrying a calorie
/// target that was never computed from anything, because the calorie target is
/// only ever set by the computation below. A plain `init` with twenty defaulted
/// parameters would accept `calorieTarget: 9999` with a `nil` multiplier, and
/// that row would then be stored forever and shown as a target.
///
/// ## What it refuses to generate
///
/// A resting burn needs a weight, a height, an age and a sex. Any one missing
/// means no generated calorie target — not a default, not a guess from the last
/// known weight. Same for the macro targets: **no protein, carb or fat target is
/// generated at all**, because the split is a product decision nobody has made
/// and the columns are nullable to say so. The hydration target is generated from
/// body weight by the standard 35 mL/kg rule, which is a published figure rather
/// than a judgement call, and still stays optional: it is a suggestion, and a
/// suggestion is not a target until it is accepted.
public struct GoalTargetBuilder {
    public let effectiveDate: String
    public let goal: GoalKind
    public let weightKg: Double?
    public let bodyFatPercent: Double?
    public let heightCm: Double?
    /// `YYYY-MM-DD`. Needed because age depends on the day, and a resting burn
    /// computed at 30 and read back at 31 is a target that quietly changed.
    public let dateOfBirth: String?
    public let referenceDate: String
    public let sex: BiologicalSex
    public let activity: ActivityLevel?
    public let formulaVersion: String

    public init(effectiveDate: String,
                goal: GoalKind,
                weightKg: Double? = nil,
                bodyFatPercent: Double? = nil,
                heightCm: Double? = nil,
                dateOfBirth: String? = nil,
                referenceDate: String,
                sex: BiologicalSex = .notSet,
                activity: ActivityLevel? = nil,
                formulaVersion: String = "1.0") {
        self.effectiveDate = effectiveDate
        self.goal = goal
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.heightCm = heightCm
        self.dateOfBirth = dateOfBirth
        self.referenceDate = referenceDate
        self.sex = sex
        self.activity = activity
        self.formulaVersion = formulaVersion
    }

    /// Years between `dateOfBirth` and `referenceDate`, as a whole number.
    ///
    /// Counting completed years rather than dividing the day count, because a
    /// resting burn is an annual-scale number and someone three days from their
    /// 31st birthday should still be 30 for it. `nil` for a missing or unparseable
    /// birth date, which is a normal state.
    public func ageYears(from dateOfBirth: String?, to referenceDate: String) -> Double? {
        guard let dateOfBirth,
              let born = Self.dayFormatter.date(from: dateOfBirth),
              let reference = Self.dayFormatter.date(from: referenceDate),
              reference >= born else { return nil }
        let years = Calendar(identifier: .gregorian).dateComponents([.year], from: born, to: reference).year
        guard let years, years > 0, years < 130 else { return nil }
        return Double(years)
    }

    /// The generated calorie target, or `nil` when it cannot be derived.
    public func calorieTarget() -> Int? {
        guard let weightKg, let heightCm,
              let age = ageYears(from: dateOfBirth, to: referenceDate),
              let activity,
              let bmr = MifflinStJeor.basalMetabolicRate(
                  weightKg: weightKg, heightCm: heightCm, ageYears: age, sex: sex)
        else { return nil }
        let maintenance = bmr * activity.energyExpenditureMultiplier
        let target = maintenance + Double(goal.defaultCalorieAdjustment)
        // A negative target is a sign the assumptions are wrong, not a number to
        // store. Someone who is told to eat minus 300 kcal deserves an error, and
        // a card showing "-300" is not it.
        guard target > 0 else { return nil }
        return Int(target.rounded())
    }

    /// The suggested daily fluid, from the standard 35 mL/kg. A *suggestion*: the
    /// builder produces it, and it only becomes a target once a snapshot records
    /// it as one.
    public func suggestedHydrationTargetMl() -> Int? {
        guard let weightKg, weightKg > 0, weightKg < 700 else { return nil }
        return Int((weightKg * 35).rounded())
    }

    /// Builds the snapshot. The target columns are set only where a derivation
    /// exists, so every absent column is absent on purpose.
    public func build(now: Date) -> GoalTargetSnapshot {
        GoalTargetSnapshot(
            effectiveDate: effectiveDate,
            goal: goal,
            formulaVersion: formulaVersion,
            bodyWeightKg: weightKg,
            bodyFatPercent: bodyFatPercent,
            activityMultiplier: activity?.energyExpenditureMultiplier,
            goalCalorieAdjustment: goal.defaultCalorieAdjustment,
            calorieTarget: calorieTarget(),
            // Protein, carb and fat are deliberately nil. No split is specified
            // anywhere in the spec, BRD or handoff, and inventing grams-per-kilo
            // ratios would put five numbers on a card that nobody chose.
            proteinTargetG: nil,
            carbTargetG: nil,
            fatTargetG: nil,
            hydrationTargetMl: suggestedHydrationTargetMl(),
            bodyCompositionTargets: [:],
            createdAt: now
        )
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}
