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

public enum ActivityLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case sedentary = "sedentary"
    case light = "light"
    case moderate = "moderate"
    case high = "high"
    case veryHigh = "very_high"
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
