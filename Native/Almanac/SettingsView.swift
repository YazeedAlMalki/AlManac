import SwiftUI
import UIKit
import AlmanacCore

@MainActor
struct SettingsView: View {
    @ObservedObject var model: HydrationModel
    @ObservedObject var labModel: LaboratoryModel
    @ObservedObject var healthModel: HealthModel
    @ObservedObject var trackingModel: TrackingCalendarModel
    @ObservedObject var notificationModel: NotificationModel
    @State private var dailyGoal: Double = 2000
    @State private var remindersEnabled = false
    @State private var reminderIntervalMinutes = 60
    @State private var reminderStartHour = 7
    @State private var reminderEndHour = 22
    @State private var digestionRingEnabled = false
    @State private var bodyMeasurementTrackSides = false
    @State private var didLoadSettings = false
    @State private var healthKitStatus: String?
    @State private var error: String?
    @AppStorage("almanac.appearance") private var appearanceRaw = AlmanacAppearance.system.rawValue
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AlmanacAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            // iOS's own per-app Language page (#4): Almanac keeps no language
            // setting of its own, so this row only opens that page.
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    LabeledContent("Language", value: currentLanguageName)
                }
                .accessibilityIdentifier("settings-language")
            } header: {
                Text("Language")
            } footer: {
                Text("Almanac follows the language chosen for it in iOS Settings. Changing it restarts the app.")
            }
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
                NavigationLink("Which source wins") {
                    SyncSourcePreferenceView(db: labModel.db)
                }
                .accessibilityIdentifier("sync-source-preference-link")
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
                NavigationLink {
                    NotificationSettingsView(model: notificationModel)
                } label: {
                    Label("All reminders", systemImage: "bell")
                }
                .accessibilityIdentifier("notification-settings-link")
            }
            Section("About") {
                NavigationLink("Attributions") {
                    AttributionsView(db: labModel.db)
                }
            }
            Section("Health") {
                Toggle("Track left/right arms and thighs", isOn: Binding(
                    get: { bodyMeasurementTrackSides },
                    set: { enabled in
                        do {
                            guard let db = labModel.db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
                            try ProfileStore(db: db).updateBodyMeasurementTrackSides(enabled)
                            bodyMeasurementTrackSides = enabled
                        } catch { self.error = error.localizedDescription }
                    }
                ))
                Text("Applies to new entries. Existing left/right measurements are kept while their treatment is awaiting a decision.")
                    .font(.caption)
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
        .scrollContentBackground(.hidden)
        .background(AlmanacPalette.canvas)
        .navigationTitle("Settings")
        .toolbarBackground(AlmanacPalette.canvas, for: .navigationBar)
        .editorError($error)
        .task {
            guard !didLoadSettings else { return }
            didLoadSettings = true
            dailyGoal = model.hydrationSettings?.dailyGoalMilliliters ?? 2000
            if let db = labModel.db {
                do { bodyMeasurementTrackSides = try ProfileStore(db: db).profile().bodyMeasurementTrackSides }
                catch { self.error = error.localizedDescription }
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

    /// The language the app is actually running in, named in that language.
    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private func setDigestionRingEnabled(_ enabled: Bool) {
        digestionRingEnabled = enabled
        do {
            guard let db = labModel.db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
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
                healthKitStatus = String(localized: "Connected.")
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    /// Persists the reminder fields to `hydration_settings` (the store
    /// `HydrationReminderService` reads), then runs §14.1's scheduling pass.
    ///
    /// **The fire times are no longer computed here.** This used to expand the
    /// interval/window pair into `DateComponents` and hand them to a scheduler
    /// that repeated them forever, which meant the reminders ignored shift
    /// schedule, religious fasts and every other rule in §14 — and could not be
    /// unscheduled individually. `NotificationPlanner` now derives the water
    /// window from the day's own shift occurrence, applies Appendix B, and the
    /// scheduler reconciles the OS against the result. The interval below still
    /// sets the cadence, because that is a user preference rather than a rule.
    private func applyReminderSchedule() async {
        do {
            try model.saveReminderSettings(enabled: remindersEnabled, intervalMinutes: reminderIntervalMinutes,
                                            startHour: reminderStartHour, endHour: reminderEndHour)
        } catch {
            self.error = String(describing: error)
            return
        }

        guard remindersEnabled else {
            // Turning the water toggle off has to reach the notification rule
            // too, or the next pass would schedule water again from the §5.25
            // default. The planner requires *both* switches on for that reason.
            do {
                try notificationModel.setEnabled(false, for: .water)
            } catch {
                self.error = String(describing: error)
            }
            await notificationModel.reconcileNotifications()
            return
        }

        do {
            try notificationModel.setEnabled(true, for: .water)
            guard try await notificationModel.requestAuthorizationAndSchedule() else {
                remindersEnabled = false
                try? model.saveReminderSettings(enabled: false, intervalMinutes: reminderIntervalMinutes,
                                                 startHour: reminderStartHour, endHour: reminderEndHour)
                return
            }
        } catch {
            remindersEnabled = false
            self.error = String(describing: error)
        }
    }
}
