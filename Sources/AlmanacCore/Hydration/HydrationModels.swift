import Foundation

/// Types of liquids tracked for hydration.
public enum LiquidType: String, Codable, Sendable, CaseIterable, Hashable {
    case water = "water"
    case sportsDrink = "sports_drink"
    case electrolyteSolution = "electrolyte_solution"
    case coconutWater = "coconut_water"
    case juice = "juice"
    case tea = "tea"
    case coffee = "coffee"
    case milk = "milk"
    case other = "other"
}

/// Hydration metrics for a given day. Not persisted — computed on demand
/// from `HydrationStore` reads plus `HydrationHealthBridge`'s exercise
/// figure, same "derived, rebuildable, never a second copy" rule as the rest
/// of this codebase.
public struct HydrationMetrics: Sendable, Hashable {
    public let date: Date
    public let totalVolumeMilliliters: Double
    public let totalSodiumMilligrams: Double
    public let exerciseMinutes: Double?
    public let recommendedIntakeMilliliters: Double
    public let hydrationPercentage: Double
    public let sampleCount: Int

    public init(
        date: Date,
        totalVolumeMilliliters: Double,
        totalSodiumMilligrams: Double,
        exerciseMinutes: Double?,
        recommendedIntakeMilliliters: Double,
        sampleCount: Int
    ) {
        self.date = date
        self.totalVolumeMilliliters = totalVolumeMilliliters
        self.totalSodiumMilligrams = totalSodiumMilligrams
        self.exerciseMinutes = exerciseMinutes
        self.recommendedIntakeMilliliters = recommendedIntakeMilliliters
        self.hydrationPercentage = (totalVolumeMilliliters / max(recommendedIntakeMilliliters, 1)) * 100
        self.sampleCount = sampleCount
    }
}

/// The app's one reminder schedule. Not its own persisted entity — see
/// `Migration013`'s doc comment. Constructed on demand from
/// `HydrationSettings` by `HydrationReminderService`.
public struct HydrationReminder: Sendable, Hashable {
    public let intervalMinutes: Int
    public let startHour: Int
    public let endHour: Int
    public let isEnabled: Bool

    public init(intervalMinutes: Int = 60, startHour: Int = 7, endHour: Int = 22, isEnabled: Bool = true) {
        self.intervalMinutes = intervalMinutes
        self.startHour = startHour
        self.endHour = endHour
        self.isEnabled = isEnabled
    }
}

/// Personalisation inputs for hydration recommendations. Single-user, stored
/// as one row in `hydration_profile` (`HydrationProfileStore`) — no owner
/// column, matching `Native/README.md`'s explicit single-user decision.
public struct HydrationProfile: Sendable, Hashable {
    public let baselineIntakeMilliliters: Double
    public let bodyWeightKg: Double?
    public let activityLevel: ActivityLevel
    public let updatedAt: Date

    public init(
        baselineIntakeMilliliters: Double = 2000,
        bodyWeightKg: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        updatedAt: Date = Date()
    ) {
        self.baselineIntakeMilliliters = baselineIntakeMilliliters
        self.bodyWeightKg = bodyWeightKg
        self.activityLevel = activityLevel
        self.updatedAt = updatedAt
    }
}

/// How much a person moves, in five steps.
///
/// **One vocabulary for the app, not one per feature.** This started life as
/// hydration's own answer to "how active is this person", and it is now also what
/// drives the generated calorie target, so a person's activity level is stated
/// once. The alternative — a second five-case enum beside this one — is how the
/// app ends up with a hydration suggestion computed from one activity level and a
/// calorie target computed from another, both of which the person believes they
/// set.
///
/// **Two multipliers, because the two questions are different.** How much water
/// somebody needs and how much energy they burn are not the same function of
/// "active", and the numbers do not even move the same way: a sedentary person
/// needs slightly *less* fluid than the baseline (0.9) while burning slightly
/// *less* energy than it (1.2). Calling both of them "the multiplier" is how a
/// hydration factor of 0.9 ends up multiplying a calorie target.
///
/// `rawValue` is what `hydration_profile.activity_level` already holds, so the
/// names are frozen by stored data. Renaming the case is free; changing
/// `rawValue` is a data migration.
public enum ActivityLevel: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case sedentary = "sedentary"
    case light = "light"
    case moderate = "moderate"
    case high = "high"
    case veryHigh = "very_high"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .high: return "Very active"
        case .veryHigh: return "Extra active"
        }
    }

    public var explanation: String {
        switch self {
        case .sedentary: return "Desk work, little exercise."
        case .light: return "Light exercise one or two days a week."
        case .moderate: return "Exercise three to five days a week."
        case .high: return "Hard exercise six or seven days a week."
        case .veryHigh: return "Physical work, or twice-a-day training."
        }
    }

    /// How much fluid this activity level implies, relative to the baseline.
    ///
    /// These are the factors `HydrationCalculator` has always used, moved here so
    /// the number sits next to the level it belongs to instead of in a `switch`
    /// inside a calculator. Unchanged in value — a multiplier table that moves is
    /// a hydration goal that changes for everyone, silently.
    public var hydrationNeedMultiplier: Double {
        switch self {
        case .sedentary: return 0.9
        case .light: return 1.0
        case .moderate: return 1.1
        case .high: return 1.2
        case .veryHigh: return 1.4
        }
    }

    /// The energy-expenditure factor that goes with Mifflin-St Jeor.
    ///
    /// **The standard published scale**, transcribed: the same five points, on the
    /// same scale, in the order the equation is always used with. Every generated
    /// calorie target in the app is a resting burn times this number, so a wrong
    /// value here is a wrong answer in every card — which is why it is not a
    /// number this app picked, and why it is *not* `hydrationNeedMultiplier` with a
    /// different name.
    ///
    /// Overridable per snapshot: a person training for a marathon is not `high`,
    /// and the way to say so is to type a different multiplier, not to wait for
    /// this enum to grow a case.
    public var energyExpenditureMultiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .high: return 1.725
        case .veryHigh: return 1.9
        }
    }
}

/// A hydration recommendation. Computed by `HydrationCalculator`, ported
/// from `claude/app-hydration-tracking-mpwsyv` at Yazeed's explicit
/// instruction to keep its urgency levels and messages as written, even
/// though nothing else in this codebase asserts a health judgement this
/// confidently without a stated clinical basis — see the conversation this
/// was ported in. If that framing is ever revisited, `Urgency` and the
/// message strings in `HydrationCalculator`/`HydrationReminderService` are
/// the two places to change.
public struct HydrationRecommendation: Sendable, Hashable {
    public let recommendedVolumeMilliliters: Double
    public let urgency: Urgency
    public let reason: String
    public let suggestedLiquidTypes: [LiquidType]
    public let timeSinceLastDrinkMinutes: Int?

    public init(
        recommendedVolumeMilliliters: Double,
        urgency: Urgency,
        reason: String,
        suggestedLiquidTypes: [LiquidType] = [.water],
        timeSinceLastDrinkMinutes: Int? = nil
    ) {
        self.recommendedVolumeMilliliters = recommendedVolumeMilliliters
        self.urgency = urgency
        self.reason = reason
        self.suggestedLiquidTypes = suggestedLiquidTypes
        self.timeSinceLastDrinkMinutes = timeSinceLastDrinkMinutes
    }
}

public enum Urgency: String, Codable, Sendable, CaseIterable, Hashable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    case critical = "critical"
}
