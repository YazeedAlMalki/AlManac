import Foundation

/// Calculates personalized hydration recommendations.
///
/// Ported from `claude/app-hydration-tracking-mpwsyv` at Yazeed's explicit
/// instruction, as-is — urgency levels and message text unchanged. The only
/// edit versus the branch is dropping `userId` from the two call sites that
/// copied it forward (`HydrationProfile` no longer carries one; see
/// `Migration013`'s doc comment for why this codebase is single-user).
public struct HydrationCalculator: Sendable {
    public init() {}

    /// Calculate recommended daily hydration based on profile and activity.
    public func recommendedDailyIntake(
        profile: HydrationProfile,
        exerciseMinutes: Double = 0
    ) -> Double {
        var intake = profile.baselineIntakeMilliliters

        let activityMultiplier = multiplier(for: profile.activityLevel)
        intake *= activityMultiplier

        if exerciseMinutes > 0 {
            let exerciseIntake = (exerciseMinutes / 30) * 500
            intake += exerciseIntake
        }

        if let weight = profile.bodyWeightKg {
            let weightBasedIntake = weight * 30
            intake = max(intake, weightBasedIntake)
        }

        return intake
    }

    /// Get recommendation for immediate hydration needs.
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

        let urgency = calculateUrgency(
            hydrationGap: hydrationGap,
            timeSinceLastDrink: timeSinceLastDrinkMinutes,
            exerciseActive: exerciseActive,
            dayProgress: metrics.hydrationPercentage
        )

        let suggestedTypes = suggestedLiquidTypes(
            exerciseActive: exerciseActive,
            urgency: urgency,
            currentSodium: metrics.totalSodiumMilligrams
        )

        let recommendedVolume: Double
        if exerciseActive {
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

    /// Analyze hydration patterns to predict future needs.
    public func adaptProfile(
        baseProfile: HydrationProfile,
        recentMetrics: [HydrationMetrics],
        averageExerciseMinutes: Double
    ) -> HydrationProfile {
        guard !recentMetrics.isEmpty else { return baseProfile }

        let averageAdherence = recentMetrics
            .map { $0.hydrationPercentage }
            .reduce(0, +) / Double(recentMetrics.count)

        var newBaseline = baseProfile.baselineIntakeMilliliters
        if averageAdherence < 75 {
            newBaseline *= 1.1
        } else if averageAdherence > 110 {
            newBaseline *= 0.95
        }

        let newActivityLevel = detectActivityLevel(averageExerciseMinutes)

        return HydrationProfile(
            baselineIntakeMilliliters: newBaseline,
            bodyWeightKg: baseProfile.bodyWeightKg,
            activityLevel: newActivityLevel,
            updatedAt: Date()
        )
    }

    // MARK: - Private Helpers

    private func multiplier(for level: ActivityLevel) -> Double {
        switch level {
        case .sedentary: return 0.9
        case .light: return 1.0
        case .moderate: return 1.1
        case .high: return 1.2
        case .veryHigh: return 1.4
        }
    }

    private func calculateUrgency(
        hydrationGap: Double,
        timeSinceLastDrink: Int,
        exerciseActive: Bool,
        dayProgress: Double
    ) -> Urgency {
        if (hydrationGap > 1500 || dayProgress < 20) && timeSinceLastDrink > 120 && exerciseActive {
            return .critical
        }
        if hydrationGap > 800 || timeSinceLastDrink > 90 {
            return .high
        }
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
            if currentSodium < 500 {
                suggestions.append(.sportsDrink)
                suggestions.append(.electrolyteSolution)
            } else {
                suggestions.append(.sportsDrink)
            }
        }

        suggestions.append(.water)

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
        case 0: return .sedentary
        case 0..<15: return .light
        case 15..<45: return .moderate
        case 45..<90: return .high
        default: return .veryHigh
        }
    }
}
