import SwiftUI
import AlmanacCore

// ============================================================================
// PROTOTYPE HOST — NOT PRODUCTION UI
// ============================================================================

/// A preview-only stand-in for the live models, so each prototype can be
/// rendered in Xcode Previews without a database. It carries a plausible day:
/// a provisional score, a partial hydration total, and a missing input.
@MainActor
struct PrototypeTodayPreview: View {
    private let data = PrototypeTodayData(
        dateLine: "Wednesday 21 October",
        greeting: "Good morning, Sam",
        score: 74,
        stateLabel: "Provisional",
        headline: "Ready for a normal session",
        detail: "It describes today; it does not diagnose or prescribe.",
        confidence: .medium,
        isFinal: false,
        calibrationDay: 9,
        missingInputCount: 1,
        recommendation: "Train as written. Hold the top set two reps short of failure.",
        baselineNotice: nil,
        circadianLine: nil,
        readProblem: nil,
        saveProblem: nil,
        isRecoveryDay: false,
        sleepMinutes: 431,
        hydrationMilliliters: 1_350,
        hydrationGoal: 2_000,
        nutritionValue: "1,842 kcal",
        nutritionDetail: "3 meals counted",
        trainingValue: nil,
        trainingDetail: "No session logged yet",
        rhr: 52,
        hrv: 61,
        mood: 7,
        soreness: nil,
        setRecoveryDay: { _ in }
    )

    var body: some View {
        PrototypeInstrumentToday(data: data)
    }
}

#Preview("Day page") {
    PrototypeDayPageToday(data: previewData)
}

#Preview("Native console") {
    PrototypeNativeConsoleToday(data: previewData)
}

private var previewData: PrototypeTodayData {
    PrototypeTodayData(
        dateLine: "Wednesday 21 October",
        greeting: "Good morning, Sam",
        score: 74,
        stateLabel: "Provisional",
        headline: "Ready for a normal session",
        detail: "It describes today; it does not diagnose or prescribe.",
        confidence: .medium,
        isFinal: false,
        calibrationDay: 9,
        missingInputCount: 1,
        recommendation: "Train as written. Hold the top set two reps short of failure.",
        baselineNotice: nil,
        circadianLine: nil,
        readProblem: nil,
        saveProblem: nil,
        isRecoveryDay: false,
        sleepMinutes: 431,
        hydrationMilliliters: 1_350,
        hydrationGoal: 2_000,
        nutritionValue: "1,842 kcal",
        nutritionDetail: "3 meals counted",
        trainingValue: nil,
        trainingDetail: "No session logged yet",
        rhr: 52,
        hrv: 61,
        mood: 7,
        soreness: nil,
        setRecoveryDay: { _ in }
    )
}
