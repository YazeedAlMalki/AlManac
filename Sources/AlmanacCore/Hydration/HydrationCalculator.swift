import Foundation

/// Calculates personalized hydration recommendations
public struct HydrationCalculator: Sendable {
    public init() {}

    /// Calculate recommended daily hydration based on profile and activity
    /// - Parameters:
    ///   - profile: User's hydration profile
    ///   - exerciseMinutes: Minutes of exercise on the day
    ///   - isPost: Whether calculating post-exercise (affects timing)
    /// - Returns: Recommended milliliters for the day
    public func recommendedDailyIntake(
        profile: HydrationProfile,
        exerciseMinutes: Double = 0
    ) -> Double {
        var intake = profile.baselineIntakeMilliliters

        // Adjust based on activity level
        let activityMultiplier = multiplier(for: profile.activityLevel)
        intake *= activityMultiplier

        // Add extra for exercise: ~500ml per 30 minutes of exercise
        if exerciseMinutes > 0 {
            let exerciseIntake = (exerciseMinutes / 30) * 500
            intake += exerciseIntake
        }

        // Adjust based on body weight if available
        if let weight = profile.bodyWeightKg {
            // Rule of thumb: ~30ml per kg body weight
            let weightBasedIntake = weight * 30
            // Use the higher of the calculated value or weight-based recommendation
            intake = max(intake, weightBasedIntake)
        }

        return intake
    }

    /// Get recommendation for immediate hydration needs
    /// - Parameters:
    ///   - timeSinceLastDrinkMinutes: Minutes since last hydration sample
    ///   - exerciseActive: Whether user is currently exercising
    ///   - metrics: Today's hydration metrics so far
    ///   - profile: User's hydration profile
    /// - Returns: Recommendation with urgency and suggested drinks
    public func currentRecommendation(
        timeSinceLastDrinkMinutes: Int,
        exerciseActive: Bool,
        metrics: HydrationMetrics,
        profile: HydrationProfile
    ) -> HydrationRecommendation {
        let targetIntake = recommendedDailyIntake(
            profile: profile,
            exerciseMinutes: metrics.exerciseMinutes ?? 0
        )
        let hydrationGap = targetIntake - metrics.totalVolumeMilliliters

        // Determine urgency based on multiple factors
        let urgency = calculateUrgency(
            hydrationGap: hydrationGap,
            timeSinceLastDrink: timeSinceLastDrinkMinutes,
            exerciseActive: exerciseActive,
            dayProgress: metrics.hydrationPercentage
        )

        // Suggest liquid type based on context
        let suggestedTypes = suggestedLiquidTypes(
            exerciseActive: exerciseActive,
            urgency: urgency,
            currentSodium: metrics.totalSodiumMilligrams
        )

        // Calculate recommended volume
        let recommendedVolume: Double
        if exerciseActive {
            // During exercise: ~150-200ml per 15 minutes
            recommendedVolume = 200
        } else if urgency == .critical {
            recommendedVolume = 500
        } else if urgency == .high {
            recommendedVolume = 350
        } else if urgency == .moderate {
            recommendedVolume = 250
        } else {
            recommendedVolume = 150
        }

        let reason = reasonForRecommendation(
            urgency: urgency,
            exerciseActive: exerciseActive,
            hydrationPercentage: metrics.hydrationPercentage,
            timeSinceLastDrink: timeSinceLastDrinkMinutes
        )

        return HydrationRecommendation(
            recommendedVolumeMilliliters: recommendedVolume,
            urgency: urgency,
            reason: reason,
            suggestedLiquidTypes: suggestedTypes,
            timeSinceLastDrinkMinutes: timeSinceLastDrinkMinutes
        )
    }

    /// Analyze hydration patterns to predict future needs
    /// - Parameters:
    ///   - recentSamples: Hydration samples from last few days
    ///   - exercisePattern: Historical exercise data
    /// - Returns: Adapted profile recommendations
    public func adaptProfile(
        baseProfile: HydrationProfile,
        recentMetrics: [HydrationMetrics],
        averageExerciseMinutes: Double
    ) -> HydrationProfile {
        guard !recentMetrics.isEmpty else { return baseProfile }

        // Calculate average hydration adherence
        let averageAdherence = recentMetrics
            .map { $0.hydrationPercentage }
            .reduce(0, +) / Double(recentMetrics.count)

        // If consistently under-hydrating, increase baseline
        var newBaseline = baseProfile.baselineIntakeMilliliters
        if averageAdherence < 75 {
            newBaseline *= 1.1  // Increase by 10%
        } else if averageAdherence > 110 {
            newBaseline *= 0.95  // Decrease by 5%
        }

        // Detect activity level based on exercise patterns
        let newActivityLevel = detectActivityLevel(averageExerciseMinutes)

        return HydrationProfile(
            userId: baseProfile.userId,
            baselineIntakeMilliliters: newBaseline,
            bodyWeightKg: baseProfile.bodyWeightKg,
            activityLevel: newActivityLevel,
            updatedAt: Date()
        )
    }

    // MARK: - Private Helpers

    private func multiplier(for level: ActivityLevel) -> Double {
        switch level {
        case .sedentary:
            return 0.9
        case .light:
            return 1.0
        case .moderate:
            return 1.1
        case .high:
            return 1.2
        case .veryHigh:
            return 1.4
        }
    }

    private func calculateUrgency(
        hydrationGap: Double,
        timeSinceLastDrink: Int,
        exerciseActive: Bool,
        dayProgress: Double
    ) -> Urgency {
        // Critical: very dehydrated or long time without water + exercise
        if (hydrationGap > 1500 || dayProgress < 20) && timeSinceLastDrink > 120 && exerciseActive {
            return .critical
        }

        // High: significant gap or long time without water
        if hydrationGap > 800 || timeSinceLastDrink > 90 {
            return .high
        }

        // Moderate: some gap or moderate time without water
        if hydrationGap > 300 || timeSinceLastDrink > 45 {
            return .moderate
        }

        return .low
    }

    private func suggestedLiquidTypes(
        exerciseActive: Bool,
        urgency: Urgency,
        currentSodium: Double
    ) -> [LiquidType] {
        var suggestions: [LiquidType] = []

        if exerciseActive || urgency == .critical || urgency == .high {
            // During/after intense exercise, suggest electrolyte drinks
            if currentSodium < 500 {  // Low sodium intake
                suggestions.append(.sportsDrink)
                suggestions.append(.electrolyteSolution)
            } else {
                suggestions.append(.sportsDrink)
            }
        }

        // Always include water as primary option
        suggestions.append(.water)

        // For variety and additional nutrients
        if !exerciseActive && urgency == .low {
            suggestions.append(.coconutWater)
        }

        return suggestions
    }

    private func reasonForRecommendation(
        urgency: Urgency,
        exerciseActive: Bool,
        hydrationPercentage: Double,
        timeSinceLastDrink: Int
    ) -> String {
        if exerciseActive {
            return "You're exercising - stay hydrated! Drink water or electrolyte sports drink."
        }

        switch urgency {
        case .critical:
            return "Critical: You're significantly dehydrated. Drink now!"
        case .high:
            if timeSinceLastDrink > 90 {
                return "It's been over 90 minutes since your last drink. Time to hydrate."
            }
            return "You're behind on hydration for today. Drink water now."
        case .moderate:
            if hydrationPercentage < 50 {
                return "You're only at \(Int(hydrationPercentage))% of daily hydration goal. Keep drinking."
            }
            return "Regular reminder: Drink some water to stay on track."
        case .low:
            return "You're doing well with hydration. Keep it up!"
        }
    }

    private func detectActivityLevel(_ averageExerciseMinutes: Double) -> ActivityLevel {
        switch averageExerciseMinutes {
        case 0:
            return .sedentary
        case 0..<15:
            return .light
        case 15..<45:
            return .moderate
        case 45..<90:
            return .high
        default:
            return .veryHigh
        }
    }
}
