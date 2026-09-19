import Foundation

/// BRD §6.16's five achievement-calendar badges.
public enum AchievementBadge: String, Sendable, CaseIterable {
    case stepsTargetMet
    case highLoadDay
    case fastedDay
    case nutritionTargetsMet
    case perfectLog
}

/// One day's inputs to the badge engine.
///
/// `isPerfectLog` is taken as given rather than computed here: the handoff
/// explicitly leaves "all Wellness data filled in, or all recommended
/// entries logged?" as an open product question, and guessing an answer to
/// a question the doc itself flags as undecided would bake in a definition
/// nobody signed off on. Whatever screen assembles these inputs decides
/// that; this engine only turns booleans into badges.
public struct DailyAchievementInputs: Sendable {
    public var steps: Int
    public var stepsTarget: Int
    public var trainingLoad: Double
    public var highLoadThreshold: Double
    public var isFastedDay: Bool
    public var calorieTargetMet: Bool
    public var macroTargetMet: Bool
    public var hydrationTargetMet: Bool
    public var isPerfectLog: Bool

    public init(steps: Int, stepsTarget: Int, trainingLoad: Double, highLoadThreshold: Double,
                isFastedDay: Bool, calorieTargetMet: Bool, macroTargetMet: Bool,
                hydrationTargetMet: Bool, isPerfectLog: Bool) {
        self.steps = steps
        self.stepsTarget = stepsTarget
        self.trainingLoad = trainingLoad
        self.highLoadThreshold = highLoadThreshold
        self.isFastedDay = isFastedDay
        self.calorieTargetMet = calorieTargetMet
        self.macroTargetMet = macroTargetMet
        self.hydrationTargetMet = hydrationTargetMet
        self.isPerfectLog = isPerfectLog
    }
}

public enum AchievementEngine {
    public static func badges(for inputs: DailyAchievementInputs) -> Set<AchievementBadge> {
        var earned: Set<AchievementBadge> = []
        if inputs.steps > inputs.stepsTarget { earned.insert(.stepsTargetMet) }
        if inputs.trainingLoad > inputs.highLoadThreshold { earned.insert(.highLoadDay) }
        if inputs.isFastedDay { earned.insert(.fastedDay) }
        if inputs.calorieTargetMet && inputs.macroTargetMet && inputs.hydrationTargetMet {
            earned.insert(.nutritionTargetsMet)
        }
        if inputs.isPerfectLog { earned.insert(.perfectLog) }
        return earned
    }
}
