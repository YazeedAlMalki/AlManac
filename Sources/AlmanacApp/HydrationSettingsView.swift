import SwiftUI
import AlmanacCore

struct HydrationSettingsView: View {
    @ObservedObject var viewModel: HydrationViewModel
    @ObservedObject var healthKitManager: HealthKitManager
    @State private var showDailyGoalEditor: Bool = false
    @State private var isLoading: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    SettingsHeaderView()
                        .padding()

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxHeight: .infinity, alignment: .center)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 24) {
                                HealthKitSectionView(healthKitManager: healthKitManager)

                                DailyGoalSectionView(
                                    currentGoal: viewModel.userSettings?.dailyGoalMilliliters ?? 2500,
                                    onEdit: { showDailyGoalEditor = true }
                                )

                                TrackingOptionsSectionView(viewModel: viewModel)

                                RemindersSectionView(viewModel: viewModel)

                                if let errorMessage = viewModel.errorMessage {
                                    ErrorMessageView(message: errorMessage)
                                }
                            }
                            .padding()
                        }
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                isLoading = true
                                try await viewModel.loadSettings()
                                try await viewModel.loadReminders()
                                isLoading = false
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                                .padding()
                        }
                        .disabled(isLoading)
                    }
                    Spacer()
                }
                .padding()
            }
            .onAppear {
                Task {
                    try await viewModel.loadSettings()
                    try await viewModel.loadReminders()
                }
            }
        }
    }
}

struct SettingsHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
            Text("Customize your hydration tracking")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DailyGoalSectionView: View {
    let currentGoal: Int
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Goal")
                .font(.headline)

            HStack {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Intake")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(currentGoal)ml")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)

            Button(action: onEdit) {
                Text("Edit Goal")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

struct TrackingOptionsSectionView: View {
    @ObservedObject var viewModel: HydrationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracking Options")
                .font(.headline)

            VStack(spacing: 8) {
                TrackingToggleView(
                    title: "Track Calories",
                    icon: "flame.fill",
                    color: .orange,
                    isEnabled: viewModel.userSettings?.trackCalories ?? false,
                    onChange: { newValue in
                        Task {
                            await viewModel.updateSettings(trackCalories: newValue)
                        }
                    }
                )

                TrackingToggleView(
                    title: "Track Sodium",
                    icon: "salt.fill",
                    color: .red,
                    isEnabled: viewModel.userSettings?.trackSodium ?? false,
                    onChange: { newValue in
                        Task {
                            await viewModel.updateSettings(trackSodium: newValue)
                        }
                    }
                )

                TrackingToggleView(
                    title: "Track Sugar",
                    icon: "cube.fill",
                    color: .pink,
                    isEnabled: viewModel.userSettings?.trackSugar ?? false,
                    onChange: { newValue in
                        Task {
                            await viewModel.updateSettings(trackSugar: newValue)
                        }
                    }
                )

                TrackingToggleView(
                    title: "Double-Track Warnings",
                    icon: "exclamationmark.triangle.fill",
                    color: .yellow,
                    isEnabled: viewModel.userSettings?.enableDoubleTrackWarnings ?? false,
                    onChange: { newValue in
                        Task {
                            await viewModel.updateSettings(enableDoubleTrackWarnings: newValue)
                        }
                    }
                )
            }
        }
    }
}

struct TrackingToggleView: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: .init(get: { isEnabled }, set: onChange)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(title)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct RemindersSectionView: View {
    @ObservedObject var viewModel: HydrationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminders")
                .font(.headline)

            if viewModel.reminders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("No reminders configured")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.reminders, id: \.id) { reminder in
                        ReminderConfigurationView(
                            reminder: reminder,
                            viewModel: viewModel
                        )
                    }
                }
            }
        }
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .border(Color.red.opacity(0.3), width: 1)
        .cornerRadius(8)
    }
}

struct HealthKitSectionView: View {
    @ObservedObject var healthKitManager: HealthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Integration")
                .font(.headline)

            if healthKitManager.authorizationStatus == .sharingAuthorized {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HealthKit Connected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Tracking workouts & heart rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .border(Color.green.opacity(0.3), width: 1)
                .cornerRadius(8)

                Button(action: {
                    healthKitManager.refreshExerciseData()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Data")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
            } else if healthKitManager.permissionDenied {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        Text("HealthKit Not Available")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    Text("HealthKit is not available on this device. You can still track hydration manually.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        Task {
                            _ = await healthKitManager.requestAuthorization()
                        }
                    }) {
                        Text("Try Again")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .border(Color.orange.opacity(0.3), width: 1)
                .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        Text("Enable HealthKit")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    Text("Allow access to your workouts and heart rate to receive personalized hydration recommendations based on your activity.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        Task {
                            _ = await healthKitManager.requestAuthorization()
                        }
                    }) {
                        Text("Enable HealthKit")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .border(Color.blue.opacity(0.3), width: 1)
                .cornerRadius(8)
            }
        }
    }
}

struct ReminderConfigurationView: View {
    let reminder: HydrationReminder
    let viewModel: HydrationViewModel
    @State private var isExpanded: Bool = false
    @State private var localStartHour: Int
    @State private var localEndHour: Int
    @State private var localInterval: Int

    init(reminder: HydrationReminder, viewModel: HydrationViewModel) {
        self.reminder = reminder
        self.viewModel = viewModel
        _localStartHour = State(initialValue: reminder.startHour)
        _localEndHour = State(initialValue: reminder.endHour)
        _localInterval = State(initialValue: reminder.intervalMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reminder \(reminder.id.prefix(8))")
                        .font(.headline)
                    Text("\(localInterval)min • \(localStartHour):00 - \(localEndHour):00")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { reminder.isEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateReminder(id: reminder.id, isEnabled: newValue)
                        }
                    }
                ))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interval (minutes)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Stepper(
                            value: $localInterval,
                            in: 15...120,
                            step: 15
                        ) {
                            Text("\(localInterval) minutes")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Hour")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Stepper(
                            value: $localStartHour,
                            in: 0...23
                        ) {
                            Text("\(localStartHour):00")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("End Hour")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Stepper(
                            value: $localEndHour,
                            in: 1...24
                        ) {
                            Text("\(localEndHour):00")
                        }
                    }

                    Button(action: {
                        Task {
                            await viewModel.updateReminder(
                                id: reminder.id,
                                intervalMinutes: localInterval,
                                startHour: localStartHour,
                                endHour: localEndHour
                            )
                        }
                    }) {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    let store = HydrationStore(databasePath: ":memory:")
    let calculator = HydrationCalculator()
    let loggingService = HydrationLoggingService(store: store, calculator: calculator)
    let reminderService = HydrationReminderService(store: store, calculator: calculator)
    let viewModel = HydrationViewModel(
        store: store,
        calculator: calculator,
        loggingService: loggingService,
        reminderService: reminderService
    )
    let healthKitManager = HealthKitManager()

    HydrationSettingsView(viewModel: viewModel, healthKitManager: healthKitManager)
}
