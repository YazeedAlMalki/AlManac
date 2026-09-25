import SwiftUI
import AlmanacCore

@MainActor
struct SettingsView: View {
    @ObservedObject var model: HydrationModel
    @ObservedObject var labModel: LaboratoryModel
    @ObservedObject var healthModel: HealthModel
    @ObservedObject var trackingModel: TrackingCalendarModel
    @State private var dailyGoal: Double = 2000
    @State private var remindersEnabled = false
    @State private var reminderIntervalMinutes = 60
    @State private var reminderStartHour = 7
    @State private var reminderEndHour = 22
    @State private var digestionRingEnabled = false
    @State private var didLoadSettings = false
    @State private var healthKitStatus: String?
    @State private var error: String?

    private let scheduler = NotificationScheduler()

    var body: some View {
        Form {
            Section("Daily goal") {
                Stepper("\(Int(dailyGoal)) mL", value: $dailyGoal, in: 500...5000, step: 250)
                    .onChange(of: dailyGoal) { _, newValue in
                        do { try model.saveDailyGoal(milliliters: newValue) }
                        catch { self.error = String(describing: error) }
                    }
            }
            Section("HealthKit") {
                Button("Connect to Health", action: connectHealthKit)
                if let healthKitStatus {
                    Text(healthKitStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Reminders") {
                Toggle("Remind me to drink water", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in Task { await applyReminderSchedule() } }
                if remindersEnabled {
                    Stepper("Every \(reminderIntervalMinutes) min", value: $reminderIntervalMinutes, in: 15...240, step: 15)
                        .onChange(of: reminderIntervalMinutes) { _, _ in Task { await applyReminderSchedule() } }
                    Stepper("From \(reminderStartHour):00", value: $reminderStartHour, in: 0...23)
                        .onChange(of: reminderStartHour) { _, _ in Task { await applyReminderSchedule() } }
                    Stepper("Until \(reminderEndHour):00", value: $reminderEndHour, in: 0...23)
                        .onChange(of: reminderEndHour) { _, _ in Task { await applyReminderSchedule() } }
                }
            }
            Section("About") {
                NavigationLink("Attributions") {
                    AttributionsView(db: labModel.db)
                }
            }
            Section("Health") {
                NavigationLink("Health data") {
                    HealthView(model: healthModel)
                }
                if model.hydrationSettings != nil || labModel.db != nil {
                    Text("Sleep, heart rate, steps and body composition sync from Apple Health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Data") {
                if let db = labModel.db {
                    NavigationLink("Backup & restore") {
                        BackupView(db: db)
                    }
                }
            }
            Section("Activity rings") {
                Toggle("Show digestion ring", isOn: Binding(
                    get: { digestionRingEnabled },
                    set: setDigestionRingEnabled
                ))
                Text("The digestion display is separate. Its daily fill rule remains undefined, so no completion state is inferred.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .editorError($error)
        .task {
            guard !didLoadSettings else { return }
            didLoadSettings = true
            dailyGoal = model.hydrationSettings?.dailyGoalMilliliters ?? 2000
            if let db = labModel.db {
                digestionRingEnabled = (try? ActivityRingSettingsStore(db: db).isDigestionEnabled()) ?? false
            }
            if let settings = model.hydrationSettings {
                remindersEnabled = settings.remindersEnabled
                reminderIntervalMinutes = settings.reminderIntervalMinutes
                reminderStartHour = settings.reminderStartHour
                reminderEndHour = settings.reminderEndHour
            }
        }
    }

    private func setDigestionRingEnabled(_ enabled: Bool) {
        digestionRingEnabled = enabled
        do {
            guard let db = labModel.db else { throw EditorFailure(message: "The database is unavailable.") }
            try ActivityRingSettingsStore(db: db).setDigestionEnabled(enabled)
            trackingModel.refresh()
        } catch {
            digestionRingEnabled = !enabled
            self.error = String(describing: error)
        }
    }

    private func connectHealthKit() {
        Task {
            do {
                // One provider, one authorisation sheet: the same concrete
                // object serves the hydration read/write pair and the read-only
                // domains, so the user answers once.
                let provider = HealthKitProvider()
                model.configureHealthKit(provider: provider, writer: provider)
                healthModel.configure(provider: provider)
                try await provider.requestAuthorisation(for: HealthKitProvider.readableDomains)
                // Water's own sync and write-back stay with HydrationModel.
                await model.syncInbound()
                await model.drainOutbound()
                await healthModel.syncNow()
                healthKitStatus = "Connected."
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    /// Persists the current reminder fields to `hydration_settings` (the
    /// same store `HydrationReminderService` reads), then applies the
    /// schedule to the OS. `HydrationSettingsStore` is the single source of
    /// truth now — nothing here reads or writes `@AppStorage`.
    private func applyReminderSchedule() async {
        do {
            try model.saveReminderSettings(enabled: remindersEnabled, intervalMinutes: reminderIntervalMinutes,
                                            startHour: reminderStartHour, endHour: reminderEndHour)
        } catch {
            self.error = String(describing: error)
            return
        }

        guard remindersEnabled else {
            await scheduler.cancelAll()
            return
        }

        do {
            guard try await scheduler.requestAuthorization() else {
                remindersEnabled = false
                error = "Notifications were not authorized."
                try? model.saveReminderSettings(enabled: false, intervalMinutes: reminderIntervalMinutes,
                                                 startHour: reminderStartHour, endHour: reminderEndHour)
                return
            }
            await scheduler.scheduleReminders(times: reminderFireTimes())
        } catch {
            remindersEnabled = false
            self.error = String(describing: error)
        }
    }

    /// Expands the interval/window pair into one `DateComponents` per fire,
    /// starting at `reminderStartHour` and stepping by `reminderIntervalMinutes`
    /// up to (not including) `reminderEndHour` — the same window
    /// `HydrationReminderService.checkReminder` enforces server-side.
    private func reminderFireTimes() -> [DateComponents] {
        guard reminderIntervalMinutes > 0, reminderStartHour < reminderEndHour else { return [] }
        let windowMinutes = (reminderEndHour - reminderStartHour) * 60
        return stride(from: 0, to: windowMinutes, by: reminderIntervalMinutes).map { offset in
            DateComponents(hour: reminderStartHour + offset / 60, minute: offset % 60)
        }
    }
}
