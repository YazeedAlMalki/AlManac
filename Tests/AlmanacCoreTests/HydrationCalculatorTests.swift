import Foundation
import XCTest
@testable import AlmanacCore

final class HydrationCalculatorTests: XCTestCase {
    var calculator: HydrationCalculator!

    override func setUp() {
        super.setUp()
        calculator = HydrationCalculator()
    }

    func testBasicDailyIntakeCalculation() {
        let profile = HydrationProfile(
            userId: "test1",
            baselineIntakeMilliliters: 2000,
            activityLevel: .moderate
        )

        let intake = calculator.recommendedDailyIntake(profile: profile, exerciseMinutes: 0)
        // Moderate activity = 2000 * 1.1 = 2200
        XCTAssertEqual(intake, 2200, accuracy: 1)
    }

    func testExerciseBoostIntake() {
        let profile = HydrationProfile(
            userId: "test2",
            baselineIntakeMilliliters: 2000,
            activityLevel: .light
        )

        // 60 minutes of exercise should add ~1000ml
        let intake = calculator.recommendedDailyIntake(profile: profile, exerciseMinutes: 60)
        XCTAssertGreaterThan(intake, 2500)
    }

    func testActivityLevelMultipliers() {
        let baseline: Double = 2000

        let sedentary = calculator.recommendedDailyIntake(
            profile: HydrationProfile(userId: "test", activityLevel: .sedentary, baselineIntakeMilliliters: baseline),
            exerciseMinutes: 0
        )
        XCTAssertEqual(sedentary, baseline * 0.9, accuracy: 1)

        let light = calculator.recommendedDailyIntake(
            profile: HydrationProfile(userId: "test", activityLevel: .light, baselineIntakeMilliliters: baseline),
            exerciseMinutes: 0
        )
        XCTAssertEqual(light, baseline * 1.0, accuracy: 1)

        let moderate = calculator.recommendedDailyIntake(
            profile: HydrationProfile(userId: "test", activityLevel: .moderate, baselineIntakeMilliliters: baseline),
            exerciseMinutes: 0
        )
        XCTAssertEqual(moderate, baseline * 1.1, accuracy: 1)
    }

    func testUrgencyCalculation() {
        let profile = HydrationProfile(userId: "test", baselineIntakeMilliliters: 2000)
        let metrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 500,
            totalSodiumMilligrams: 100,
            exerciseMinutes: nil,
            recommendedIntakeMilliliters: 2000,
            sampleCount: 1
        )

        // Large gap + long time + exercise = critical
        let criticalRec = calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: 120,
            exerciseActive: true,
            metrics: metrics,
            profile: profile
        )
        XCTAssertEqual(criticalRec.urgency, .critical)

        // Large gap = high urgency
        let highRec = calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: 100,
            exerciseActive: false,
            metrics: metrics,
            profile: profile
        )
        XCTAssertEqual(highRec.urgency, .high)

        // Some gap = moderate
        let moderateMetrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 1500,
            totalSodiumMilligrams: 100,
            exerciseMinutes: nil,
            recommendedIntakeMilliliters: 2000,
            sampleCount: 3
        )
        let modRec = calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: 50,
            exerciseActive: false,
            metrics: moderateMetrics,
            profile: profile
        )
        XCTAssertEqual(modRec.urgency, .moderate)
    }

    func testExerciseRecommendations() {
        let profile = HydrationProfile(userId: "test")
        let metrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 500,
            totalSodiumMilligrams: 0,
            exerciseMinutes: 30,
            recommendedIntakeMilliliters: 2500,
            sampleCount: 2
        )

        let recommendation = calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: 15,
            exerciseActive: true,
            metrics: metrics,
            profile: profile
        )

        // During exercise should suggest sports drinks
        XCTAssert(recommendation.suggestedLiquidTypes.contains(.sportsDrink))
        XCTAssertEqual(recommendation.recommendedVolumeMilliliters, 200)
    }

    func testProfileAdaptation() {
        let baseProfile = HydrationProfile(
            userId: "test",
            baselineIntakeMilliliters: 2000,
            activityLevel: .light
        )

        let metrics = [
            HydrationMetrics(date: Date(), totalVolumeMilliliters: 1200, totalSodiumMilligrams: 0, exerciseMinutes: nil, recommendedIntakeMilliliters: 2000, sampleCount: 3),
            HydrationMetrics(date: Date().addingTimeInterval(-86400), totalVolumeMilliliters: 1300, totalSodiumMilligrams: 0, exerciseMinutes: nil, recommendedIntakeMilliliters: 2000, sampleCount: 3),
            HydrationMetrics(date: Date().addingTimeInterval(-172800), totalVolumeMilliliters: 1100, totalSodiumMilligrams: 0, exerciseMinutes: nil, recommendedIntakeMilliliters: 2000, sampleCount: 2)
        ]

        let adapted = calculator.adaptProfile(
            baseProfile: baseProfile,
            recentMetrics: metrics,
            averageExerciseMinutes: 0
        )

        // User is under-hydrating, so baseline should increase
        XCTAssertGreaterThan(adapted.baselineIntakeMilliliters, baseProfile.baselineIntakeMilliliters)
    }

    func testBodyWeightAdjustment() {
        let lightProfile = HydrationProfile(
            userId: "light",
            baselineIntakeMilliliters: 1500,
            bodyWeightKg: 60,
            activityLevel: .light
        )

        let heavyProfile = HydrationProfile(
            userId: "heavy",
            baselineIntakeMilliliters: 1500,
            bodyWeightKg: 100,
            activityLevel: .light
        )

        let lightIntake = calculator.recommendedDailyIntake(profile: lightProfile, exerciseMinutes: 0)
        let heavyIntake = calculator.recommendedDailyIntake(profile: heavyProfile, exerciseMinutes: 0)

        // Body weight adjustment: 30ml per kg
        XCTAssertGreaterThan(heavyIntake, lightIntake)
    }
}
