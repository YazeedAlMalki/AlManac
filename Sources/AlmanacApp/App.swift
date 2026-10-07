import SwiftUI
import AlmanacCore

@main
struct AlmanacApp: App {
    @StateObject private var viewModel: HydrationViewModel

    init() {
        let store = HydrationStore(databasePath: Self.databasePath)
        let calculator = HydrationCalculator()
        let loggingService = HydrationLoggingService(store: store, calculator: calculator)
        let reminderService = HydrationReminderService(store: store, calculator: calculator)

        _viewModel = StateObject(
            wrappedValue: HydrationViewModel(
                store: store,
                calculator: calculator,
                loggingService: loggingService,
                reminderService: reminderService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $viewModel.selectedTab) {
                HydrationLoggingView(viewModel: viewModel)
                    .tabItem {
                        Label("Log", systemImage: "drop.fill")
                    }
                    .tag(HydrationTab.logging)

                HydrationDashboardView(viewModel: viewModel)
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    .tag(HydrationTab.dashboard)

                HydrationSettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(HydrationTab.settings)
            }
            .environmentObject(viewModel)
        }
    }

    private static var databasePath: String {
        let paths = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        let appSupportURL = paths[0]
        let dbURL = appSupportURL.appendingPathComponent("almanac.db")
        return dbURL.path
    }
}

enum HydrationTab {
    case logging
    case dashboard
    case settings
}
