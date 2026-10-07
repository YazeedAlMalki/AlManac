import Foundation
import SwiftUI
import AlmanacCore

@MainActor
final class HydrationViewModel: NSObject, ObservableObject {
    @Published var selectedTab: HydrationTab = .logging
    @Published var todayMetrics: HydrationMetrics?
    @Published var recommendedVolume: Double = 2500
    @Published var drinkHistory: [HydrationSample] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showUndoButton: Bool = false
    @Published var lastDrinkVolume: Double = 0

    @Published var userProfile: HydrationProfile?
    @Published var userSettings: HydrationSettings?
    @Published var reminders: [HydrationReminder] = []

    let store: HydrationStore
    let calculator: HydrationCalculator
    let loggingService: HydrationLoggingService
    let reminderService: HydrationReminderService

    private var userId: String = "default_user"

    init(
        store: HydrationStore,
        calculator: HydrationCalculator,
        loggingService: HydrationLoggingService,
        reminderService: HydrationReminderService
    ) {
        self.store = store
        self.calculator = calculator
        self.loggingService = loggingService
        self.reminderService = reminderService
        super.init()

        Task {
            await initializeData()
        }
    }

    private func initializeData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await loadTodayMetrics()
            try await loadDrinkHistory()
            try await loadProfile()
            try await loadSettings()
            try await loadReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logDrink(volumeMilliliters: Int, liquidType: LiquidType) async {
        do {
            let sample = HydrationSample(
                id: UUID().uuidString,
                userId: userId,
                timestamp: Date(),
                volumeMilliliters: volumeMilliliters,
                liquidType: liquidType,
                sodiumMilligrams: 0,
                caloriesKilocalories: 0
            )

            try store.save(sample)
            lastDrinkVolume = Double(volumeMilliliters)
            showUndoButton = true

            await loadTodayMetrics()
            await loadDrinkHistory()

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.showUndoButton = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undoLastDrink() async {
        do {
            if let _ = try loggingService.undoLastDrink(userId: userId) {
                showUndoButton = false
                await loadTodayMetrics()
                await loadDrinkHistory()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTodayMetrics() async throws {
        let profile = userProfile ?? HydrationProfile(
            userId: userId,
            baselineIntakeMilliliters: 2500,
            bodyWeightKilogram: 70,
            activityLevel: .moderate
        )

        todayMetrics = try store.calculateTodayMetrics(
            userId: userId,
            calculator: calculator,
            profile: profile,
            settings: userSettings
        )

        if let metrics = todayMetrics {
            recommendedVolume = Double(metrics.recommendedDaily)
        }
    }

    func loadDrinkHistory() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        drinkHistory = try store.fetchSamples(userId: userId, from: today, to: Date())
    }

    func loadProfile() async throws {
        let profiles = try store.fetchProfiles()
        userProfile = profiles.first(where: { $0.userId == userId })

        if userProfile == nil {
            let newProfile = HydrationProfile(
                userId: userId,
                baselineIntakeMilliliters: 2500,
                bodyWeightKilogram: 70,
                activityLevel: .moderate
            )
            try store.save(newProfile)
            userProfile = newProfile
        }
    }

    func loadSettings() async throws {
        let allSettings = try store.fetchSettings()
        userSettings = allSettings.first

        if userSettings == nil {
            let newSettings = HydrationSettings(
                id: UUID().uuidString,
                dailyGoalMilliliters: nil,
                trackCalories: false,
                trackSodium: false,
                trackSugar: false,
                enableDoubleTrackWarnings: false,
                createdAt: Date()
            )
            try store.save(newSettings)
            userSettings = newSettings
        }
    }

    func loadReminders() async throws {
        reminders = try store.fetchReminders()

        if reminders.isEmpty {
            let reminder = try reminderService.createDefaultReminder()
            reminders = [reminder]
        }
    }

    func updateReminder(
        id: String,
        intervalMinutes: Int? = nil,
        startHour: Int? = nil,
        endHour: Int? = nil,
        isEnabled: Bool? = nil
    ) async {
        do {
            try reminderService.updateReminder(
                id: id,
                intervalMinutes: intervalMinutes,
                startHour: startHour,
                endHour: endHour,
                isEnabled: isEnabled
            )
            try await loadReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSettings(
        dailyGoal: Int? = nil,
        trackCalories: Bool? = nil,
        trackSodium: Bool? = nil,
        trackSugar: Bool? = nil,
        enableDoubleTrackWarnings: Bool? = nil
    ) async {
        do {
            guard var settings = userSettings else { return }

            if let dailyGoal = dailyGoal {
                settings.dailyGoalMilliliters = dailyGoal
            }
            if let trackCalories = trackCalories {
                settings.trackCalories = trackCalories
            }
            if let trackSodium = trackSodium {
                settings.trackSodium = trackSodium
            }
            if let trackSugar = trackSugar {
                settings.trackSugar = trackSugar
            }
            if let enableDoubleTrackWarnings = enableDoubleTrackWarnings {
                settings.enableDoubleTrackWarnings = enableDoubleTrackWarnings
            }

            try store.save(settings)
            userSettings = settings
            try await loadTodayMetrics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
