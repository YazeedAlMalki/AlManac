import Foundation

/// Represents a single hydration event (drinking water or other liquids)
public struct HydrationSample: Sendable, Hashable {
    public let id: String
    public let timestamp: Date
    public let volumeMilliliters: Double
    public let liquidType: LiquidType
    public let sodiumMilligrams: Double?
    public let caloriesKcal: Double?
    public let sourceName: String?

    public init(
        id: String,
        timestamp: Date,
        volumeMilliliters: Double,
        liquidType: LiquidType,
        sodiumMilligrams: Double? = nil,
        caloriesKcal: Double? = nil,
        sourceName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.volumeMilliliters = volumeMilliliters
        self.liquidType = liquidType
        self.sodiumMilligrams = sodiumMilligrams
        self.caloriesKcal = caloriesKcal
        self.sourceName = sourceName
    }
}

/// Types of liquids tracked for hydration
public enum LiquidType: String, Codable, Sendable, CaseIterable, Hashable {
    case water = "water"
    case sportsDrink = "sports_drink"  // Gatorade, Powerade, etc.
    case electrolyteSolution = "electrolyte_solution"  // Pedialyte, etc.
    case coconutWater = "coconut_water"
    case juice = "juice"
    case tea = "tea"
    case coffee = "coffee"
    case milk = "milk"
    case other = "other"
}

/// Hydration metrics for a given day
public struct HydrationMetrics: Sendable, Hashable {
    public let date: Date
    public let totalVolumeMilliliters: Double
    public let totalSodiumMilligrams: Double
    public let exerciseMinutes: Double?
    public let recommendedIntakeMilliliters: Double
    public let hydrationPercentage: Double  // (actual / recommended) * 100
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

/// Hydration reminder configuration
public struct HydrationReminder: Sendable, Hashable {
    public let id: String
    public let intervalMinutes: Int
    public let startHour: Int  // 0-23
    public let endHour: Int    // 0-23
    public let isEnabled: Bool
    public let createdAt: Date

    public init(
        id: String,
        intervalMinutes: Int = 60,
        startHour: Int = 7,
        endHour: Int = 22,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.intervalMinutes = intervalMinutes
        self.startHour = startHour
        self.endHour = endHour
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

/// User's hydration profile for personalized recommendations
public struct HydrationProfile: Sendable, Hashable {
    public let userId: String
    public let baselineIntakeMilliliters: Double  // Recommended daily intake without exercise
    public let bodyWeightKg: Double?
    public let activityLevel: ActivityLevel
    public let updatedAt: Date

    public init(
        userId: String,
        baselineIntakeMilliliters: Double = 2000,  // Default 2L
        bodyWeightKg: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.baselineIntakeMilliliters = baselineIntakeMilliliters
        self.bodyWeightKg = bodyWeightKg
        self.activityLevel = activityLevel
        self.updatedAt = updatedAt
    }
}

/// User's activity level for hydration calculations
public enum ActivityLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case sedentary = "sedentary"
    case light = "light"
    case moderate = "moderate"
    case high = "high"
    case veryHigh = "very_high"
}

/// Hydration recommendation based on activity and metrics
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

/// Urgency levels for hydration recommendations
public enum Urgency: String, Codable, Sendable, CaseIterable, Hashable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    case critical = "critical"
}
