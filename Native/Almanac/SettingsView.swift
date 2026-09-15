import SwiftUI
import AlmanacCore

@MainActor
struct SettingsView: View {
    @ObservedObject var model: HydrationModel
    @AppStorage("hydrationDailyGoalML") private var dailyGoal: Double = 2000
    @AppStorage("hydrationRemindersEnabled") private var remindersEnabled = false
    @State private var reminderTimes: [Date] = SettingsView.defaultReminderTimes
    @State private var healthKitStatus: String?
    @State private var error: String?

    private let scheduler = NotificationScheduler()

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily goal") {
                    Stepper("\(Int(dailyGoal)) mL", value: $dailyGoal, in: 500...5000, step: 250)
                }
                Section("HealthKit") {
                    Button("Connect to Health", action: connectHealthKit)
                    if let healthKitStatus {
                        Text(healthKitStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Reminders") {
                    Toggle("Remind me to drink water", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, enabled in
                            Task { await applyReminderSchedule(enabled: enabled) }
                        }
                    if remindersEnabled {
                        ForEach(reminderTimes.indices, id: \.self) { index in
                            DatePicker("Reminder \(index + 1)", selection: Binding(
                                get: { reminderTimes[index] },
                                set: { reminderTimes[index] = $0; Task { await applyReminderSchedule(enabled: true) } }
                            ), displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .editorError($error)
        }
    }

    private static var defaultReminderTimes: [Date] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return [9, 13, 17].compactMap { hour in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())
        }
    }

    private func connectHealthKit() {
        Task {
            do {
                let provider = HealthKitProvider()
                model.configureHealthKit(provider: provider, writer: provider)
                try await provider.requestAuthorisation(for: [.water])
                await model.syncInbound()
                await model.drainOutbound()
                healthKitStatus = "Connected."
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    private func applyReminderSchedule(enabled: Bool) async {
        if enabled {
            do {
                guard try await scheduler.requestAuthorization() else {
                    remindersEnabled = false
                    error = "Notifications were not authorized."
                    return
                }
                let calendar = Calendar.current
                let components = reminderTimes.map {
                    calendar.dateComponents([.hour, .minute], from: $0)
                }
                await scheduler.scheduleReminders(times: components)
            } catch {
                remindersEnabled = false
                self.error = String(describing: error)
            }
        } else {
            await scheduler.cancelAll()
        }
    }
}
