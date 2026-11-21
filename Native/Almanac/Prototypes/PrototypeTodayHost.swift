import SwiftUI
import AlmanacCore

// ============================================================================
// PROTOTYPE HOST — NOT PRODUCTION UI
// ============================================================================
//
// Reachable only when a launch argument names a direction:
//
//     xcrun simctl launch <udid> com.almanac.personal -AlmanacTodayPrototype instrument
//     ... day-page | native-console
//
// The argument is read in `AlmanacApp.selectedDestination`, so an ordinary
// launch never constructs any of this and the production Today screen is the
// only one a user can reach. The prototypes read the live models, so a capture
// shows real data — the same score, the same totals, the same empty states the
// shipped screen would show.
//
// Delete this file, the three prototype views, and the argument branch once a
// direction is chosen.

@MainActor
struct PrototypeTodayHost: View {
    enum Direction: String {
        case instrument
        case dayPage = "day-page"
        case nativeConsole = "native-console"
    }

    let direction: Direction
    @ObservedObject var readiness: ReadinessModel
    @ObservedObject var hydration: HydrationModel
    @ObservedObject var nutrition: NutritionModel
    @ObservedObject var training: TrainingModel

    private static let argument = "-AlmanacTodayPrototype"

    /// The direction a launch argument asked for, or nil on an ordinary launch.
    static func requestedDirection(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Direction? {
        guard let flag = arguments.firstIndex(of: argument), flag + 1 < arguments.count else { return nil }
        return Direction(rawValue: arguments[flag + 1])
    }

    var body: some View {
        let data = PrototypeTodayFactory.make(
            readiness: readiness,
            hydration: hydration,
            nutrition: nutrition,
            training: training
        )
        Group {
            switch direction {
            case .instrument: PrototypeInstrumentToday(data: data)
            case .dayPage: PrototypeDayPageToday(data: data)
            case .nativeConsole: PrototypeNativeConsoleToday(data: data)
            }
        }
        .task {
            readiness.refresh()
            hydration.refresh()
            nutrition.refresh()
            training.refresh()
        }
    }
}
