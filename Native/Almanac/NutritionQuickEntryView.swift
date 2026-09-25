import SwiftUI
import AlmanacCore

/// The Nutrition tab's root: today's log at a glance, and the fast path to
/// add another meal to it. Picking a food — by search or from a saved
/// meal — and logging it are both done here; `NutritionFoodSearchView` and
/// `NutritionSavedMealsView` are reached from this screen and hand their
/// pick straight back into the fields below.
@MainActor
struct NutritionQuickEntryView: View {
    @ObservedObject var model: NutritionModel
    private let embedded: Bool
    private let onSaved: () -> Void
    @State private var selectedRef: SourceIdentifier?
    @State private var selectedName = ""
    @State private var gramsText = ""
    @State private var quantityText = ""
    @State private var mealType: NutritionMealType?
    @State private var showingSearch = false
    @State private var showingSavedMeals = false
    @State private var error: String?

    init(model: NutritionModel, embedded: Bool = false, onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.embedded = embedded
        self.onSaved = onSaved
    }

    /// Breakfast/lunch/dinner/snack, in the order a day runs, then whatever
    /// has no meal type at all — grouped last, not dropped, since "logged
    /// this, didn't say which meal" is a real entry (`NutritionMealType`'s
    /// header).
    private static let mealTypeOrder: [NutritionMealType?] =
        NutritionMealType.allCases.map { $0 } + [nil]

    private struct MealGroup: Identifiable {
        let id: String
        let type: NutritionMealType?
        let foods: [LoggedFood]
    }

    private var mealGroups: [MealGroup] {
        let grouped = Dictionary(grouping: model.todaysFoods, by: { $0.entry.mealType })
        return NutritionQuickEntryView.mealTypeOrder.compactMap { type in
            guard let foods = grouped[type], !foods.isEmpty else { return nil }
            return MealGroup(id: type?.rawValue ?? "unspecified", type: type, foods: foods)
        }
    }

    var body: some View {
        content.almanacNavigationHost(embedded)
    }

    private var content: some View {
        Form {
            totalsSection
            if model.isPreparingReference {
                Section {
                    HStack {
                        ProgressView()
                        Text("Preparing the food catalogue…")
                    }
                }
            } else if let error = model.referencePreparationError {
                Section {
                    Text("Food catalogue unavailable: \(error)")
                        .foregroundStyle(.secondary)
                    Button("Try again") { model.retryReferencePreparation() }
                }
            }
            ForEach(mealGroups) { group in
                Section(group.type?.displayName ?? "Other") {
                    ForEach(group.foods, id: \.entry.id) { logged in
                        foodRow(logged)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    deleteEntry(logged.entry.id)
                                }
                            }
                    }
                }
            }
            logSection
        }
        .navigationTitle("Nutrition")
        .almanacModuleSurface()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Saved meals") { showingSavedMeals = true }
                    .disabled(!model.isReferenceAvailable)
            }
        }
        .sheet(isPresented: $showingSearch) {
            NutritionFoodSearchView(model: model) { food in
                selectedRef = food.ref
                selectedName = food.primaryName
            }
        }
        .sheet(isPresented: $showingSavedMeals) {
            NutritionSavedMealsView(model: model) { ref, name, defaultGrams in
                selectedRef = ref
                selectedName = name
                if let defaultGrams { gramsText = String(Int(defaultGrams)) }
            }
        }
        .editorError($error)
        .onAppear { model.refresh() }
    }

    private var totalsSection: some View {
        Section("Today") {
            if let totals = model.todaysTotals, totals.mealsCounted > 0 {
                LabeledContent("Total", value: "\(Int(totals.kcal.rounded())) kcal")
                if !totals.isComplete {
                    Text("Some logged foods are missing an amount or a reference match, so this total is a floor, not the full picture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing logged yet today.").foregroundStyle(.secondary)
            }
        }
    }

    private func foodRow(_ logged: LoggedFood) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(logged.entry.foodNameText ?? logged.food?.primaryName ?? logged.entry.foodRef.description)
                if let quantity = logged.entry.quantityText {
                    Text(quantity).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let kcal = logged.energy?.kilocalories {
                Text("\(Int(kcal.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var logSection: some View {
        Section("Log a food") {
            Button {
                showingSearch = true
            } label: {
                if selectedRef == nil {
                    Text("Select food")
                } else {
                    LabeledContent("Food", value: selectedName)
                }
            }
            if let ref = selectedRef {
                Picker("Meal", selection: $mealType) {
                    Text("Not specified").tag(NutritionMealType?.none)
                    ForEach(NutritionMealType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(NutritionMealType?.some(type))
                    }
                }
                NutritionPortionPickerView(model: model, foodRef: ref,
                                           gramsText: $gramsText, quantityText: $quantityText)
                Button("Log", action: save)
            }
        }
        .disabled(!model.isReferenceAvailable)
    }

    private func deleteEntry(_ id: String) {
        do { try model.delete(id: id) } catch { self.error = String(describing: error) }
    }

    private func save() {
        do {
            guard let ref = selectedRef else {
                throw EditorFailure(message: "Select a food first.")
            }
            let grams: Double?
            if gramsText.isEmpty {
                grams = nil
            } else if let value = Double(gramsText), value > 0 {
                grams = value
            } else {
                throw EditorFailure(message: "Enter a gram amount greater than zero, or leave it blank.")
            }
            try model.log(foodRef: ref, foodName: selectedName, grams: grams,
                          quantityText: optionalText(quantityText), mealType: mealType)
            onSaved()
            selectedRef = nil; selectedName = ""; gramsText = ""; quantityText = ""; mealType = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}
