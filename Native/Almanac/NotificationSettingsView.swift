import SwiftUI
import AlmanacCore

/// Per-type reminder switches — BRD §6.14's "All types individually
/// toggleable & time-adjustable" — and a plain statement of what the app has
/// actually queued right now.
///
/// The count at the top is read from the notification centre, not from the
/// plan, because a plan computed an hour ago is a claim about the past. When
/// the two disagree, this screen believes the system.
@MainActor
struct NotificationSettingsView: View {
    @ObservedObject var model: NotificationModel

    @State private var rules: [NotificationRule] = []
    @State private var error: String?
    @State private var confirmTurnOffAll = false

    var body: some View {
        Form {
            Section {
                if model.isAuthorized {
                    LabeledContent("Queued now", value: NumberDisplay.localized(String(model.pendingCount)))
                        .font(AlmanacTypography.font(.body))
                } else {
                    Text("Almanac has not been allowed to send notifications on this device, so nothing is queued. Turn reminders on to be asked.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
                if let modelProblem = model.schedulingProblem {
                    Text(modelProblem)
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.warning)
                }
            }

            Section {
                ForEach(rules) { rule in
                    Toggle(isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in setEnabled(enabled, for: rule.type) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.title(for: rule.type))
                                .font(AlmanacTypography.font(.body))
                            Text(Self.blurb(for: rule.type))
                                .font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("notification-rule-\(rule.type.rawValue)")
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Each reminder is scheduled against your own day — your shift, your fast and your sleep. A reminder that does not apply is not sent, rather than sent and ignored.")
            }

            Section {
                Button("Allow notifications", action: requestAuthorization)
                    .disabled(model.isAuthorized)
                    .accessibilityIdentifier("notification-allow-button")
                Button("Turn all reminders off", role: .destructive) { confirmTurnOffAll = true }
                    .disabled(rules.allSatisfy { !$0.isEnabled })
                    .accessibilityIdentifier("notification-turn-off-all")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AlmanacPalette.canvas)
        .navigationTitle("Reminders")
        .toolbarBackground(AlmanacPalette.canvas, for: .navigationBar)
        .editorError($error)
        // An alert rather than a confirmation dialog: this is the one action on
        // the screen that is not trivially reversible, so it is worth the
        // stronger presentation — and an alert renders its buttons where both
        // a finger and a UI test can reliably find them.
        .alert("Turn off every reminder?", isPresented: $confirmTurnOffAll) {
            Button("Turn them all off", role: .destructive) {
                Task { await model.cancelEverything(); reload() }
            }
            Button("Keep them on", role: .cancel) {}
        } message: {
            Text("No reminder from Almanac will be sent until you turn them back on.")
        }
        .task {
            reload()
            await model.reconcileNotifications()
        }
    }

    // MARK: - Private

    private func setEnabled(_ enabled: Bool, for type: NotificationType) {
        do {
            try model.setEnabled(enabled, for: type)
            reload()
            Task { await model.reconcileNotifications() }
        } catch {
            self.error = error.localizedDescription
            reload()
        }
    }

    private func requestAuthorization() {
        Task {
            do {
                if try await model.requestAuthorizationAndSchedule() { reload() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Re-reads every rule. Called after every write rather than once on
    /// appear: the switches read their value out of `rules`, so a stale copy
    /// would leave a toggle showing the state before the tap that just
    /// succeeded.
    private func reload() {
        do { rules = try model.rules() }
        catch { self.error = error.localizedDescription }
    }

    static func title(for type: NotificationType) -> String {
        switch type {
        case .readiness: return String(localized: "Morning check-in")
        case .water: return String(localized: "Drink water")
        case .meal: return String(localized: "Meal reminders")
        case .bedtime: return String(localized: "Bedtime")
        case .supplement: return String(localized: "Supplements")
        case .suhoor: return String(localized: "Suhoor")
        case .iftar: return String(localized: "Iftar")
        case .contextualSnack: return String(localized: "Pre-workout snack")
        case .contextualHydration: return String(localized: "Pre-meal drink")
        case .prayer: return String(localized: "Prayer times")
        }
    }

    /// One line per type saying when it would actually fire, so a switch is not
    /// a mystery. Kept short deliberately: this is a settings list, not §14.2.
    static func blurb(for type: NotificationType) -> String {
        switch type {
        case .readiness: return String(localized: "After you wake, or at your expected wake time on a shift.")
        case .water: return String(localized: "Through your active window, pausing during a dry fast.")
        case .meal: return String(localized: "At the times you set, never during a confirmed fast.")
        case .bedtime: return String(localized: "Before your expected sleep window, not during a night shift.")
        case .supplement: return String(localized: "At each plan's own time, from the supplement screen.")
        case .suhoor: return String(localized: "Twenty minutes before Fajr, on religious fast days.")
        case .iftar: return String(localized: "At Maghrib, on religious fast days.")
        case .contextualSnack: return String(localized: "When a long gap opens before a planned workout.")
        case .contextualHydration: return String(localized: "About an hour before a meal you usually eat.")
        case .prayer: return String(localized: "At each prayer you choose in Prayer. Maghrib on a fast day is the iftar reminder.")
        }
    }
}
