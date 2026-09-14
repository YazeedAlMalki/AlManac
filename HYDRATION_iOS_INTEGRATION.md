# Hydration Tracking — iOS UI Integration Guide

This document provides step-by-step instructions for integrating the AlmanacCore hydration module into the iOS app.

## Architecture Overview

The iOS app uses SwiftUI with the following layers:
1. **AlmanacCore package** — Database, business logic, and calculations (this is what we've built)
2. **iOS App Views** — SwiftUI screens that present data and collect user input
3. **EnvironmentObjects** — State management for navigation and user preferences

## Getting Started

### 1. Import AlmanacCore

Add to your iOS app target's build settings or package dependencies:
```swift
import AlmanacCore
```

### 2. Initialize at App Launch

In your main App struct:
```swift
@main
struct AlmanacApp: App {
    @StateObject var appState: AppState
    
    init() {
        // Initialize shared database
        let db = AppState.sharedDatabase
        _appState = StateObject(wrappedValue: AppState(database: db))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
```

### 3. AppState Helper Class

Create a shared state management class:

```swift
@MainActor
final class AppState: ObservableObject {
    static let sharedDatabase: Database = {
        let dbPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        )[0] + "/almanac.db"
        return try! Database(path: dbPath)
    }()
    
    let hydrationStore: HydrationStore
    let calorieIntegration: CalorieIntegration
    let settingsStore: HydrationSettingsStore
    let loggingService: HydrationLoggingService
    let reminderService: HydrationReminderService
    let calculator: HydrationCalculator
    let healthBridge: HydrationHealthBridge
    
    @Published var userProfile: HydrationProfile?
    @Published var todayMetrics: HydrationMetrics?
    @Published var currentRecommendation: HydrationRecommendation?
    
    init(database: Database) {
        self.hydrationStore = HydrationStore(database: database)
        self.calorieIntegration = CalorieIntegration(database: database)
        self.settingsStore = HydrationSettingsStore(database: database)
        self.loggingService = HydrationLoggingService(
            hydrationStore: hydrationStore,
            calorieIntegration: calorieIntegration,
            settingsStore: settingsStore
        )
        self.reminderService = HydrationReminderService(store: hydrationStore)
        self.calculator = HydrationCalculator()
        self.healthBridge = HydrationHealthBridge(db: database)
        
        Task {
            await loadUserProfile()
            await refreshTodayMetrics()
        }
    }
    
    func loadUserProfile() async {
        let userId = getCurrentUserId() // Your app's user ID
        do {
            let profile = try hydrationStore.fetchProfile(userId: userId)
                ?? HydrationProfile(userId: userId)
            self.userProfile = profile
        } catch {
            print("Error loading profile: \(error)")
        }
    }
    
    func refreshTodayMetrics() async {
        guard let profile = userProfile else { return }
        do {
            let metrics = try hydrationStore.calculateTodayMetrics(
                calculator: calculator,
                profile: profile
            )
            self.todayMetrics = metrics
            
            // Update recommendation
            let recommendation = calculator.currentRecommendation(
                timeSinceLastDrinkMinutes: 0,
                exerciseActive: false,
                metrics: metrics,
                profile: profile
            )
            self.currentRecommendation = recommendation
        } catch {
            print("Error refreshing metrics: \(error)")
        }
    }
    
    private func getCurrentUserId() -> String {
        // Return the current authenticated user's ID
        // This should be obtained from your authentication system
        return "default_user"
    }
}
```

## UI Components

### 1. HydrationDashboardView

Main screen showing today's hydration progress:

```swift
struct HydrationDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDrinkPicker = false
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Progress Ring
                if let metrics = appState.todayMetrics {
                    ProgressRingView(
                        current: Int(metrics.totalVolumeMilliliters),
                        goal: Int(metrics.recommendedIntakeMilliliters)
                    )
                    .frame(height: 200)
                    .padding()
                }
                
                // Stats Grid
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        StatCard(
                            title: "Volume",
                            value: "\(Int(appState.todayMetrics?.totalVolumeMilliliters ?? 0))ml",
                            icon: "💧"
                        )
                        
                        StatCard(
                            title: "Goal",
                            value: "\(Int(appState.todayMetrics?.recommendedIntakeMilliliters ?? 0))ml",
                            icon: "🎯"
                        )
                    }
                    
                    if let settings = try? AppState.sharedDatabase.query("SELECT * FROM hydration_settings LIMIT 1"),
                       settings.first?.int("calorie_tracking_enabled") != 0 {
                        StatCard(
                            title: "Calories",
                            value: "140 kcal",
                            icon: "🔥"
                        )
                    }
                }
                .padding(.horizontal)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: { showDrinkPicker = true }) {
                        Label("Log Drink", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    HStack(spacing: 10) {
                        QuickLogButton(volume: 250, appState: appState)
                        QuickLogButton(volume: 500, appState: appState)
                        QuickLogButton(volume: 350, appState: appState)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Hydration")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showDrinkPicker) {
                DrinkPickerView(appState: appState)
            }
            .sheet(isPresented: $showSettings) {
                HydrationSettingsView(appState: appState)
            }
            .task {
                await appState.refreshTodayMetrics()
            }
        }
    }
}

struct QuickLogButton: View {
    let volume: Double
    let appState: AppState
    @State private var isLogging = false
    
    var body: some View {
        Button(action: logQuickDrink) {
            Text("\(Int(volume))ml")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isLogging)
    }
    
    private func logQuickDrink() {
        Task {
            isLogging = true
            do {
                let water = Drink(
                    id: "catalog_water",
                    name: "Water",
                    liquidType: .water,
                    volumeMilliliters: volume,
                    caloriesKcal: 0,
                    sodiumMilligrams: 0,
                    sugarGrams: 0,
                    isCustom: false,
                    userId: "default_user"
                )
                let _ = try await appState.loggingService.logDrink(
                    drink: water,
                    userId: "default_user"
                )
                await appState.refreshTodayMetrics()
            } catch {
                print("Error logging drink: \(error)")
            }
            isLogging = false
        }
    }
}
```

### 2. DrinkPickerView

Search and select from drink catalog:

```swift
struct DrinkPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedDrink: Drink?
    @State private var customVolume: Double?
    @State private var showCustomDrink = false
    @State private var isLogging = false
    
    var filteredDrinks: [Drink] {
        if searchText.isEmpty {
            return CatalogDrinks.all
        }
        return CatalogDrinks.all.filter { drink in
            drink.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                SearchBar(text: $searchText, placeholder: "Search drinks...")
                
                List(filteredDrinks, id: \.id) { drink in
                    DrinkRow(
                        drink: drink,
                        isSelected: selectedDrink?.id == drink.id,
                        onSelect: { selectedDrink = drink }
                    )
                }
                
                if selectedDrink != nil {
                    VolumeInputView(
                        drink: selectedDrink!,
                        customVolume: $customVolume,
                        onConfirm: logSelectedDrink
                    )
                }
                
                Button(action: { showCustomDrink = true }) {
                    Label("Add Custom Drink", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding()
            }
            .navigationTitle("Select Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCustomDrink) {
                CustomDrinkSheetView(appState: appState)
            }
        }
    }
    
    private func logSelectedDrink() {
        guard let drink = selectedDrink else { return }
        Task {
            isLogging = true
            do {
                let result = try await appState.loggingService.logDrink(
                    drink: drink,
                    customVolume: customVolume,
                    userId: "default_user"
                )
                
                // Handle warnings if needed
                if !result.warnings.isEmpty {
                    // Show warning dialog
                    showWarningDialog(result.warnings)
                }
                
                await appState.refreshTodayMetrics()
                dismiss()
            } catch {
                print("Error logging drink: \(error)")
            }
            isLogging = false
        }
    }
    
    private func showWarningDialog(_ warnings: [DrinkLoggingWarning]) {
        // Implement warning dialog based on warning types
        for warning in warnings {
            switch warning.type {
            case .possibleDoubleTrack:
                print("Double-track warning: \(warning.message)")
            case .highSugar:
                print("High sugar warning: \(warning.message)")
            case .highSodium:
                print("High sodium info: \(warning.message)")
            }
        }
    }
}

struct DrinkRow: View {
    let drink: Drink
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(drink.name)
                    .font(.headline)
                Text("\(Int(drink.caloriesKcal)) cal • \(Int(drink.sodiumMilligrams))mg sodium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct VolumeInputView: View {
    let drink: Drink
    @Binding var customVolume: Double?
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Volume")
                .font(.headline)
            
            HStack {
                Slider(
                    value: Binding(
                        get: { customVolume ?? drink.volumeMilliliters },
                        set: { customVolume = $0 }
                    ),
                    in: 50...1000,
                    step: 50
                )
                
                Text("\(Int(customVolume ?? drink.volumeMilliliters))ml")
                    .font(.body)
                    .frame(width: 50)
            }
            
            Button(action: onConfirm) {
                Text("Log")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
        .padding()
    }
}
```

### 3. CustomDrinkSheetView

Create custom drinks:

```swift
struct CustomDrinkSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var liquidType: LiquidType = .water
    @State private var volume: Double = 250
    @State private var calories: Double = 0
    @State private var sodium: Double = 0
    @State private var sugar: Double? = nil
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Drink Details") {
                    TextField("Name", text: $name)
                    
                    Picker("Type", selection: $liquidType) {
                        ForEach(LiquidType.allCases, id: \.self) { type in
                            Text(formatLiquidType(type)).tag(type)
                        }
                    }
                }
                
                Section("Nutrition (per serving)") {
                    Stepper("Volume: \(Int(volume))ml", value: $volume, in: 50...1000, step: 50)
                    
                    Stepper("Calories: \(Int(calories)) kcal", value: $calories, in: 0...500, step: 10)
                    
                    Stepper("Sodium: \(Int(sodium))mg", value: $sodium, in: 0...1000, step: 50)
                    
                    Stepper(
                        "Sugar: \(sugar.map { Int($0) } ?? 0)g",
                        value: Binding(
                            get: { sugar ?? 0 },
                            set: { sugar = $0 > 0 ? $0 : nil }
                        ),
                        in: 0...100,
                        step: 1
                    )
                }
                
                Section {
                    Button(action: saveCustomDrink) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Custom Drink")
                        }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .navigationTitle("New Custom Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func saveCustomDrink() {
        Task {
            isSaving = true
            do {
                let _ = try await appState.loggingService.logCustomDrink(
                    name: name,
                    liquidType: liquidType,
                    volume: volume,
                    calories: calories,
                    sodium: sodium,
                    sugar: sugar,
                    userId: "default_user"
                )
                dismiss()
            } catch {
                print("Error saving custom drink: \(error)")
            }
            isSaving = false
        }
    }
    
    private func formatLiquidType(_ type: LiquidType) -> String {
        switch type {
        case .water: return "💧 Water"
        case .sportsDrink: return "⚡ Sports Drink"
        case .electrolyteSolution: return "🧂 Electrolyte Solution"
        case .coconutWater: return "🥥 Coconut Water"
        case .juice: return "🧃 Juice"
        case .tea: return "🍵 Tea"
        case .coffee: return "☕ Coffee"
        case .milk: return "🥛 Milk"
        case .other: return "🥤 Other"
        }
    }
}
```

### 4. HydrationSettingsView

Configure hydration tracking:

```swift
struct HydrationSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var settings: HydrationSettings?
    @State private var selectedPreset: HydrationSettingsPreset = .standard
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    Text("User: default_user")
                    
                    Picker("Activity Level", selection: Binding(
                        get: { appState.userProfile?.activityLevel ?? .moderate },
                        set: { newLevel in
                            updateActivityLevel(newLevel)
                        }
                    )) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text(formatActivityLevel(level)).tag(level)
                        }
                    }
                    
                    HStack {
                        Text("Body Weight")
                        Spacer()
                        TextField("kg", value: Binding(
                            get: { appState.userProfile?.bodyWeightKg ?? 70 },
                            set: { newWeight in
                                updateBodyWeight(newWeight)
                            }
                        ), format: .number)
                    }
                }
                
                Section("Tracking") {
                    Toggle("Calorie Tracking", isOn: Binding(
                        get: { settings?.isCalorieTrackingEnabled ?? false },
                        set: { value in
                            updateSetting(\.isCalorieTrackingEnabled, to: value)
                        }
                    ))
                    
                    Toggle("Double-Track Warnings", isOn: Binding(
                        get: { settings?.isDoubleTrackWarningEnabled ?? true },
                        set: { value in
                            updateSetting(\.isDoubleTrackWarningEnabled, to: value)
                        }
                    ))
                    
                    Toggle("Track Sodium", isOn: Binding(
                        get: { settings?.trackSodium ?? true },
                        set: { value in
                            updateSetting(\.trackSodium, to: value)
                        }
                    ))
                    
                    Toggle("Track Sugar", isOn: Binding(
                        get: { settings?.trackSugar ?? true },
                        set: { value in
                            updateSetting(\.trackSugar, to: value)
                        }
                    ))
                }
                
                Section("Reminders") {
                    Stepper(
                        "Interval: \(settings?.reminderIntervalMinutes ?? 60) min",
                        value: Binding(
                            get: { Double(settings?.reminderIntervalMinutes ?? 60) },
                            set: { value in
                                updateSetting(\.reminderIntervalMinutes, to: Int(value))
                            }
                        ),
                        in: 30...120,
                        step: 15
                    )
                }
                
                Section("Presets") {
                    Picker("Profile", selection: $selectedPreset) {
                        ForEach(HydrationSettingsPreset.allCases, id: \.self) { preset in
                            Text(formatPreset(preset)).tag(preset)
                        }
                    }
                    .onChange(of: selectedPreset) { newPreset in
                        applyPreset(newPreset)
                    }
                }
            }
            .navigationTitle("Hydration Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadSettings()
            }
        }
    }
    
    private func loadSettings() async {
        do {
            let settings = try appState.settingsStore.getOrCreate(for: "default_user")
            self.settings = settings
            isLoading = false
        } catch {
            print("Error loading settings: \(error)")
        }
    }
    
    private func updateSetting<T>(_ keyPath: WritableKeyPath<HydrationSettings, T>, to value: T) {
        guard var settings = settings else { return }
        settings[keyPath: keyPath] = value
        Task {
            try appState.settingsStore.save(settings)
        }
    }
    
    private func updateActivityLevel(_ level: ActivityLevel) {
        guard var profile = appState.userProfile else { return }
        profile = HydrationProfile(
            userId: profile.userId,
            baselineIntakeMilliliters: profile.baselineIntakeMilliliters,
            bodyWeightKg: profile.bodyWeightKg,
            activityLevel: level,
            updatedAt: Date()
        )
        Task {
            try appState.hydrationStore.save(profile)
            appState.userProfile = profile
        }
    }
    
    private func updateBodyWeight(_ weight: Double) {
        guard var profile = appState.userProfile else { return }
        profile = HydrationProfile(
            userId: profile.userId,
            baselineIntakeMilliliters: profile.baselineIntakeMilliliters,
            bodyWeightKg: weight,
            activityLevel: profile.activityLevel,
            updatedAt: Date()
        )
        Task {
            try appState.hydrationStore.save(profile)
            appState.userProfile = profile
        }
    }
    
    private func applyPreset(_ preset: HydrationSettingsPreset) {
        let newSettings = preset.toSettings(userId: "default_user")
        Task {
            try appState.settingsStore.save(newSettings)
            self.settings = newSettings
        }
    }
    
    private func formatActivityLevel(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return "Sedentary"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very High"
        }
    }
    
    private func formatPreset(_ preset: HydrationSettingsPreset) -> String {
        switch preset {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .comprehensive: return "Comprehensive"
        case .athlete: return "Athlete"
        case .calorieCounter: return "Calorie Counter"
        }
    }
}
```

## Health Framework Integration

### 1. Update HealthProvider

Extend the HealthProvider protocol to expose workouts:

```swift
protocol HealthProvider: Sendable {
    // Existing methods...
    
    /// Stream of workout events
    var workouts: AsyncStream<HealthWorkout> { get }
}

struct HealthWorkout: Sendable {
    let id: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let calories: Double?
}
```

### 2. Wire Health Sync

In your HealthSyncService, sync workouts to health_sample:

```swift
func syncWorkouts() async throws {
    let workouts = await healthProvider.workouts
    for await workout in workouts {
        let sample = HealthSample(
            id: workout.id,
            domain: .workouts,
            startAt: workout.startDate,
            endAt: workout.endDate,
            value: workout.duration / 60,  // minutes
            deletedAt: nil
        )
        try healthSampleStore.save(sample)
    }
}
```

### 3. Setup Reminder Notifications

In AppState, schedule notifications:

```swift
func scheduleHydrationReminders() async {
    let reminder = try reminderService.createDefaultReminder()
    
    // Schedule daily notifications at intervals
    let center = UNUserNotificationCenter.current()
    try await center.requestAuthorization(options: [.alert, .sound])
    
    Timer.scheduledTimer(withTimeInterval: Double(reminder.intervalMinutes * 60), repeats: true) { _ in
        Task {
            let profile = appState.userProfile,
            let metrics = try hydrationStore.calculateTodayMetrics(
                calculator: calculator,
                profile: profile
            ),
            let rec = try reminderService.checkReminder(profile: profile, currentMetrics: metrics)
            else { return }
            
            let message = reminderService.getReminderMessage(recommendation: rec, profile: profile)
            
            let content = UNMutableNotificationContent()
            content.title = "💧 Hydration Reminder"
            content.body = message
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            try await center.add(request)
        }
    }
}
```

## Key Integration Points

- **Database Path:** `NSSearchPathForDirectoriesInDomains(.documentDirectory)[0] + "/almanac.db"`
- **User ID:** Must be provided by your authentication system
- **Health Data:** Read-only from health_sample table via HydrationHealthBridge
- **Settings:** Per-user, stored in hydration_settings table
- **Calorie Tracking:** OFF by default, enabled via settings

## Testing Checklist

- [ ] App launches and initializes AlmanacCore
- [ ] HydrationDashboardView displays today's metrics
- [ ] DrinkPickerView searches and selects drinks
- [ ] Quick-log buttons (250ml, 500ml, 350ml) work
- [ ] Custom drink creation saves to database
- [ ] Settings panel controls calorie tracking toggle
- [ ] Double-track warnings appear when expected
- [ ] Reminders notify at configured intervals
- [ ] Exercise detection escalates recommendations
- [ ] Calorie totals display when tracking enabled
- [ ] Custom drinks persist and reappear in picker

