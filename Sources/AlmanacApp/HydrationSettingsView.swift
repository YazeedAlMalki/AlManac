import SwiftUI
import AlmanacCore

struct HydrationSettingsView: View {
    @ObservedObject var viewModel: HydrationViewModel
    @State private var showReminderConfig: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Daily Goal")
                                .font(.headline)

                            HStack {
                                Image(systemName: "target")
                                    .foregroundColor(.blue)
                                Text("Goal: \(viewModel.userSettings?.dailyGoalMilliliters ?? 2500)ml")
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                            Button(action: { showReminderConfig = true }) {
                                Text("Edit Goal")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tracking Options")
                                .font(.headline)

                            Toggle(isOn: Binding(
                                get: { viewModel.userSettings?.trackCalories ?? false },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSettings(trackCalories: newValue)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "flame.fill")
                                        .foregroundColor(.orange)
                                    Text("Track Calories")
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                            Toggle(isOn: Binding(
                                get: { viewModel.userSettings?.trackSodium ?? false },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSettings(trackSodium: newValue)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "salt.fill")
                                        .foregroundColor(.red)
                                    Text("Track Sodium")
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                            Toggle(isOn: Binding(
                                get: { viewModel.userSettings?.trackSugar ?? false },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSettings(trackSugar: newValue)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "cube.fill")
                                        .foregroundColor(.pink)
                                    Text("Track Sugar")
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                            Toggle(isOn: Binding(
                                get: { viewModel.userSettings?.enableDoubleTrackWarnings ?? false },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSettings(enableDoubleTrackWarnings: newValue)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text("Double-Track Warnings")
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reminders")
                                .font(.headline)

                            if !viewModel.reminders.isEmpty {
                                ForEach(viewModel.reminders, id: \.id) { reminder in
                                    ReminderConfigurationView(
                                        reminder: reminder,
                                        viewModel: viewModel
                                    )
                                }
                            } else {
                                Text("No reminders configured")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            }

                            Button(action: {
                                Task {
                                    try await viewModel.loadReminders()
                                }
                            }) {
                                Text("Refresh Reminders")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .foregroundColor(.primary)
                                    .cornerRadius(8)
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
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

    HydrationSettingsView(viewModel: viewModel)
}
