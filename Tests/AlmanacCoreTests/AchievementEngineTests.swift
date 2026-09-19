import Testing
@testable import AlmanacCore

@Suite("AchievementEngine Tests")
struct AchievementEngineTests {

    @Test("All thresholds met earns all five badges")
    func allBadgesMet() {
        let inputs = DailyAchievementInputs(
            steps: 12000, stepsTarget: 10000,
            trainingLoad: 500, highLoadThreshold: 400,
            isFastedDay: true,
            calorieTargetMet: true, macroTargetMet: true, hydrationTargetMet: true,
            isPerfectLog: true
        )
        #expect(AchievementEngine.badges(for: inputs) == Set(AchievementBadge.allCases))
    }

    @Test("Nothing met earns no badges")
    func noBadgesMet() {
        let inputs = DailyAchievementInputs(
            steps: 2000, stepsTarget: 10000,
            trainingLoad: 50, highLoadThreshold: 400,
            isFastedDay: false,
            calorieTargetMet: false, macroTargetMet: false, hydrationTargetMet: false,
            isPerfectLog: false
        )
        #expect(AchievementEngine.badges(for: inputs).isEmpty)
    }

    @Test("Nutrition badge requires calorie, macro, and hydration targets all met")
    func nutritionBadgeRequiresAllThree() {
        let inputs = DailyAchievementInputs(
            steps: 2000, stepsTarget: 10000,
            trainingLoad: 50, highLoadThreshold: 400,
            isFastedDay: false,
            calorieTargetMet: true, macroTargetMet: true, hydrationTargetMet: false,
            isPerfectLog: false
        )
        #expect(!AchievementEngine.badges(for: inputs).contains(.nutritionTargetsMet))
    }

    @Test("Steps and high-load badges are independent of each other")
    func partialBadges() {
        let inputs = DailyAchievementInputs(
            steps: 12000, stepsTarget: 10000,
            trainingLoad: 50, highLoadThreshold: 400,
            isFastedDay: false,
            calorieTargetMet: false, macroTargetMet: false, hydrationTargetMet: false,
            isPerfectLog: false
        )
        let badges = AchievementEngine.badges(for: inputs)
        #expect(badges == [.stepsTargetMet])
    }
}
