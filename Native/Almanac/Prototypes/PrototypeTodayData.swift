import SwiftUI
import AlmanacCore

// ============================================================================
// PROTOTYPE SCAFFOLDING — NOT PRODUCTION UI
// ============================================================================
//
// Three candidate designs for the Today screen, built to be looked at rather
// than shipped. Nothing here is wired into the app's navigation: the shell in
// `AlmanacApp.swift` shows these only when a launch argument names one, so the
// production `ReadinessDashboardView` is untouched and no prototype type is
// reachable by a user.
//
// They read the **real** models. Every number, label and empty state below is
// whatever the app actually has today — so a prototype can be judged on how it
// carries real data (a provisional score, a missing input, an error) rather
// than on a mock-up of a good day.
//
// Delete this whole `Prototypes/` directory once a direction is chosen; the
// four pbxproj entries that name it are the only other thing to remove.

/// The data one Today prototype draws. Assembled once, from the live models, so
/// the three designs differ in *how* they present the day and not in what the
/// day contains.
@MainActor
struct PrototypeTodayData {
    let dateLine: String
    let greeting: String
    let score: Int?
    let stateLabel: String
    let headline: String
    let detail: String
    let confidence: ReadinessConfidence?
    let isFinal: Bool
    let calibrationDay: Int?
    let missingInputCount: Int
    let recommendation: String?
    let baselineNotice: String?
    let circadianLine: String?
    let readProblem: String?
    let saveProblem: String?
    let isRecoveryDay: Bool

    let sleepMinutes: Int?
    let hydrationMilliliters: Double
    let hydrationGoal: Double
    let nutritionValue: String?
    let nutritionDetail: String
    let trainingValue: String?
    let trainingDetail: String

    let rhr: Double?
    let hrv: Double?
    let mood: Int?
    let soreness: Int?

    let setRecoveryDay: (Bool) -> Void

    var hydrationTone: AlmanacStatusTone {
        hydrationMilliliters >= hydrationGoal ? .good : .neutral
    }
}

/// A font that keeps a prototype's chosen size but still scales with Dynamic
/// Type.
///
/// The prototypes were first written with fixed `.system(size:)` calls, which
/// are frozen: at the largest accessibility size the Instrument screen grew by
/// 1% and its text did not move at all. Measured, not assumed — see the
/// `-ax5` captures. This wraps the same size in `relativeTo:`, so the design's
/// proportions survive while the words scale, which is what the design system
/// does for the shipped screens (`AlmanacTypography.font`).
///
/// `design` and `weight` are passed through so each prototype keeps its face.
extension Font {
    static func almanacScaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo style: Font.TextStyle
    ) -> Font {
        // `.system(size:weight:design:)` is frozen and cannot be made scalable,
        // so resolve the system face to its name and scale *that*.
        let base = UIFont.systemFont(ofSize: size, weight: weight.uiKitWeight)
        if design == .default {
            return .custom(base.fontName, size: size, relativeTo: style)
        }
        return .system(style, design: design, weight: weight)
    }
}

private extension Font.Weight {
    var uiKitWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

@MainActor
enum PrototypeTodayFactory {
    static func make(
        readiness: ReadinessModel,
        hydration: HydrationModel,
        nutrition: NutritionModel,
        training: TrainingModel
    ) -> PrototypeTodayData {
        let outcome = readiness.outcome
        let goal = hydration.hydrationSettings?.dailyGoalMilliliters ?? 2_000
        let energy = DayEnergy.total(food: nutrition.todaysTotals, drinks: hydration.todaysDrinkEnergy)
        let summary = training.todaysSummary

        return PrototypeTodayData(
            dateLine: Date.now.formatted(.almanacDateTime.weekday(.wide).day().month(.wide)),
            greeting: greeting(name: readiness.displayName),
            score: outcome?.score,
            stateLabel: stateLabel(outcome),
            headline: headline(outcome),
            detail: detail(outcome, readProblem: readiness.readProblem),
            confidence: outcome?.confidence,
            isFinal: outcome?.state == .final,
            calibrationDay: readiness.calibrationDay,
            missingInputCount: outcome?.missingInputs.count ?? 0,
            recommendation: outcome?.recommendation.map(ReadinessText.display),
            baselineNotice: readiness.baselineNotice?.text,
            circadianLine: readiness.circadianLine,
            readProblem: readiness.readProblem,
            saveProblem: readiness.saveProblem,
            isRecoveryDay: readiness.isRecoveryDay,
            sleepMinutes: readiness.sleepDurationMinutes,
            hydrationMilliliters: hydration.todayTotal.value,
            hydrationGoal: goal,
            nutritionValue: energy.map { String(localized: "\(AlmanacNumber.compact($0.kcal)) kcal") },
            nutritionDetail: energy?.summary ?? String(localized: "No nutrition logged yet"),
            trainingValue: trainingValue(summary),
            trainingDetail: summary == nil
                ? String(localized: "No session logged yet")
                : String(localized: "Session recorded today"),
            rhr: readiness.latestRHR,
            hrv: readiness.latestHRV,
            mood: readiness.todayMood?.score,
            soreness: readiness.todaySoreness?.overallScore,
            setRecoveryDay: { declared in
                try? readiness.setRecoveryDay(declared)
            }
        )
    }

    static func greeting(name: String) -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return String(localized: "Good morning, \(name)")
        case 12..<17: return String(localized: "Good afternoon, \(name)")
        default: return String(localized: "Good evening, \(name)")
        }
    }

    static func stateLabel(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome, outcome.score != nil else { return String(localized: "Waiting on signals") }
        return outcome.state == .final ? String(localized: "Final") : String(localized: "Provisional")
    }

    static func headline(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome else { return String(localized: "Readiness is waiting") }
        if outcome.score == nil { return String(localized: "More signals are needed") }
        return outcome.textDescription.map(ReadinessText.display) ?? String(localized: "Today’s readiness assessment")
    }

    static func detail(_ outcome: ReadinessOutcome?, readProblem: String?) -> String {
        if readProblem != nil { return String(localized: "The signals below could not be read just now.") }
        guard let outcome else {
            return String(localized: "Connect Apple Health or log today’s check-in. Almanac will not replace missing readings with zero.")
        }
        if outcome.score == nil {
            return String(localized: "Almanac could not produce a defensible score from the available signals.")
        }
        return String(localized: "It describes today; it does not diagnose or prescribe.")
    }

    static func trainingValue(_ summary: WorkoutLoadSummary?) -> String? {
        guard let summary else { return nil }
        if let duration = summary.totalDurationSeconds { return durationLabel(Int(duration.rounded())) }
        if let rounds = summary.totalRounds { return "\(rounds) rounds" }
        if let tonnage = summary.totalTonnageKg { return String(localized: "\(AlmanacNumber.compact(tonnage)) kg") }
        if let distance = summary.totalDistanceMeters { return "\(AlmanacNumber.compact(distance)) m" }
        return String(localized: "Logged")
    }

    static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? String(localized: "\(hours)h \(mins)m") : String(localized: "\(mins)m")
    }
}
