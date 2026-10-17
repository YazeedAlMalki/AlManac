import SwiftUI
import AlmanacCore

@MainActor
struct HydrationDashboardView: View {
    @ObservedObject var model: HydrationModel
    private let embedded: Bool
    @State private var logging = false
    @State private var error: String?

    init(model: HydrationModel, embedded: Bool = false) {
        self.model = model
        self.embedded = embedded
    }

    /// The settings-row daily goal; the app default is 2000 mL when the row
    /// has never stored one (the goal now lives in `hydration_settings`, not
    /// `@AppStorage`).
    private var dailyGoal: Double { model.hydrationSettings?.dailyGoalMilliliters ?? 2000 }

    var body: some View {
        dashboard.almanacNavigationHost(embedded)
    }

    private var dashboard: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(model.todayTotal.value)) mL").font(.largeTitle.bold())
                        .accessibilityIdentifier("hydration-today-total")
                    Text("of \(Int(dailyGoal)) mL goal")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: min(model.todayTotal.value / max(dailyGoal, 1), 1))
                        .tint(AlmanacPalette.accent)
                }.padding(.vertical, 4)
            }
            colourFeedbackSection
            Section("Today") {
                // `else if`, not two notes: if the log cannot be read at all,
                // the state of the Health sync is not the thing worth the user's
                // attention. And the sync message already says the figures may
                // be out of date, so it carries no separate action line — the
                // advice is only appended where it is not already spoken.
                if let problem = model.readProblem {
                    AlmanacProblemNote(text: problem, action: String(localized: "Figures below may be out of date."))
                } else if let problem = model.syncProblem {
                    AlmanacProblemNote(text: problem)
                }
                if model.todaysEntries.isEmpty {
                    Text("Nothing logged yet today.").foregroundStyle(.secondary)
                }
                ForEach(model.todaysEntries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text("\(Int(entry.amount.value)) mL")
                                if let drink = entry.drink {
                                    Text(drink.displayName)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            // The drink's own provenance, on the row it applies
                            // to. A catalog figure is a typical value for a
                            // named product, not a measured one, and a number
                            // shown without that reads as measured.
                            if let drink = entry.drink {
                                Text(drink.qualifier == .userEntered
                                     ? "Your figures for this drink"
                                     : "Typical value, not measured")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let note = entry.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                            // §5.5: a clear status while an app-created entry is
                            // not yet in HealthKit. Only once Almanac may write
                            // water there, or every entry of someone who never
                            // connected Health would carry it. The write is
                            // retried on every sync (`HydrationWriteback`).
                            if model.writesWaterToHealth, entry.sourceSystem == "manual", !entry.healthKitSynced {
                                Label("Not yet in Apple Health", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("hydration.pending-health")
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let calories = entry.drink?.caloriesKcal, calories > 0 {
                                Text("\(AlmanacNumber.compact(calories)) kcal")
                                    .font(AlmanacTypography.font(.data).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(timeLabel(entry.loggedAt)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            // No drink-calorie total here any more. It is part of the day's
            // single energy figure on Today, so a second number in this screen
            // would be the same figure twice. The per-drink figure in each row
            // above still shows, and `Migration013` still records per row
            // whether a drink's value was a catalog estimate or user-entered.
        }
        .navigationTitle("Hydration")
        .almanacModuleSurface()
        .toolbar { Button("Log a drink", systemImage: "plus") { logging = true } }
        .sheet(isPresented: $logging) { HydrationLoggingView(model: model) }
        .task { model.refresh() }
        .editorError($error)
    }

    /// BRD §6.3's feedback from urine colour, offered rather than applied:
    /// the target is the person's, so a raise is a button, not a silent edit.
    /// Draft wording, and it says so.
    @ViewBuilder
    private var colourFeedbackSection: some View {
        if let verdict = model.colourFeedback, let message = verdict.message {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hydration.colour-feedback")
                    if case let .raise(_, to, _) = verdict {
                        Button("Raise target to \(Int(to)) mL") {
                            do {
                                try model.saveDailyGoal(milliliters: to)
                                model.refresh()
                            } catch {
                                self.error = String(describing: error)
                            }
                        }
                        .accessibilityIdentifier("hydration.colour-feedback.raise")
                    }
                }
            } header: {
                Text("Urine colour")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            do { try model.delete(id: model.todaysEntries[index].id) }
            catch { self.error = String(describing: error) }
        }
    }

    private func timeLabel(_ date: PartialDateTime) -> String {
        guard date.isKnown else { return "" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let instant = parser.date(from: date.text) else { return date.text }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: instant)
    }
}
