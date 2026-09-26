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
                    Text("of \(Int(dailyGoal)) mL goal")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: min(model.todayTotal.value / max(dailyGoal, 1), 1))
                        .tint(AlmanacPalette.accent)
                }.padding(.vertical, 4)
            }
            Section("Today") {
                if model.todaysEntries.isEmpty {
                    Text("Nothing logged yet today.").foregroundStyle(.secondary)
                }
                ForEach(model.todaysEntries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text("\(Int(entry.amount.value)) mL")
                                if let drink = entry.drink {
                                    Text(drink.drinkName)
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
            // A separate line from food's `NutritionTotals.kcal`, on purpose.
            // Merging them would put an uncited catalog estimate inside a
            // number that otherwise means cited composition data, which is the
            // distinction `Migration013` exists to keep.
            if let drinkCalories = model.todaysDrinkCalories, drinkCalories > 0 {
                Section {
                    HStack {
                        Text("From drinks")
                        Spacer()
                        Text("\(AlmanacNumber.compact(drinkCalories)) kcal")
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                    }
                } footer: {
                    Text("Kept apart from your food calories on purpose: a catalog drink is a typical value, not a measured or cited figure.")
                }
            }
        }
        .navigationTitle("Hydration")
        .almanacModuleSurface()
        .toolbar { Button("Log a drink", systemImage: "plus") { logging = true } }
        .sheet(isPresented: $logging) { HydrationLoggingView(model: model) }
        .task { model.refresh() }
        .editorError($error)
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
