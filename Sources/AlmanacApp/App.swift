import SwiftUI
import AlmanacCore

@main
struct AlmanacApp: App {
    @StateObject private var viewModel: HydrationViewModel
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var notificationManager = NotificationManager()

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
                HydrationLoggingView(viewModel: viewModel, healthKitManager: healthKitManager)
                    .tabItem {
                        Label("Log", systemImage: "drop.fill")
                    }
                    .tag(HydrationTab.logging)

                HydrationDashboardView(viewModel: viewModel, healthKitManager: healthKitManager)
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    .tag(HydrationTab.dashboard)

                HydrationSettingsView(viewModel: viewModel, healthKitManager: healthKitManager, notificationManager: notificationManager)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(HydrationTab.settings)
            }
            .environmentObject(viewModel)
            .environmentObject(healthKitManager)
            .environmentObject(notificationManager)
            .onAppear {
                viewModel.setNotificationManager(notificationManager)
                Task {
                    _ = await healthKitManager.requestAuthorization()
                    _ = await notificationManager.requestAuthorization()
                    await notificationManager.getPendingNotifications()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("HydrationReminderTapped")),
                perform: handleReminderNotificationTap
            )
        }
    }

    private func handleReminderNotificationTap(_ notification: Notification) {
        if let recommendedVolume = notification.userInfo?["recommendedVolume"] as? Double {
            viewModel.selectedTab = .logging
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
