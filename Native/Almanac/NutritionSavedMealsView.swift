import SwiftUI
import AlmanacCore

/// Lists the `almanac:` dishes the person has authored with
/// `NutritionDishEditor`, so a recipe assembled once can be logged again
/// without re-searching for it every time.
///
/// Picking a row hands its food back to `NutritionQuickEntryView` exactly as
/// `NutritionFoodSearchView` does — a saved meal is just a food with a name
/// the person already trusts, not a second logging path to maintain.
///
/// **Allergens (2026-10-06).** Checked by `DishAllergenCheck`, the same check
/// Kitchen uses: a meal naming a recorded allergen — in its own name or an
/// ingredient's — is hidden by default, listed collapsed under "Hidden because
/// of your allergens", and opens on its own page under a warning. Until then
/// this list was not checked at all. A failed read of the allergen list is an
/// error here, never an unchecked list.
///
/// **Servings (2026-10-16).** A meal's swipe action sets how many servings the
/// dish makes (`DishServingCountSheet`). This is the only screen that lists a
/// person's dishes, and no screen edits one, so the count lives here.
@MainActor
struct NutritionSavedMealsView: View {
    @ObservedObject var model: NutritionModel
    let onSelect: (SourceIdentifier, String, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var results = SavedMealResults()
    @State private var error: String?
    @State private var countingServings: ServingTarget?

    var body: some View {
        NavigationStack {
            Group {
                if results.meals.isEmpty && results.hidden.isEmpty {
                    ContentUnavailableView {
                        Label("No saved meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("Dishes created for the food log will appear here.")
                    }
                } else {
                    List {
                        // Above the list, for the reason `NutritionFoodSearchView`
                        // gives: it qualifies what follows.
                        if let disclaimer = results.disclaimer {
                            Section { AlmanacProblemNote(text: disclaimer) }
                        }
                        Section {
                            ForEach(results.meals, id: \.ref) { dish in
                                Button { choose(dish) } label: { row(dish) }
                                    .swipeActions(edge: .trailing) {
                                        Button("Servings") { countingServings = ServingTarget(dish: dish) }
                                            .tint(AlmanacPalette.accent)
                                    }
                            }
                        }
                        HiddenDishesSection(rows: results.hidden.map(hiddenRow),
                                            disclaimer: results.disclaimer) { row in
                            if let hidden = results.hidden.first(where: { $0.item.ref == row.ref }) {
                                choose(hidden.item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { load() }
            .sheet(item: $countingServings, onDismiss: load) { target in
                DishServingCountSheet(
                    dish: target.dish,
                    wholeGrams: model.oneServingGrams(target.dish.ref)
                        .map { $0 * Double(target.dish.servingCount ?? 1) },
                    onSave: { try model.setServingCount($0, for: target.dish.ref) })
            }
            .editorError($error)
        }
    }

    private func row(_ dish: NativeDish) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(dish.nameText).foregroundStyle(.primary)
                if let serving = model.oneServingGrams(dish.ref) {
                    Text("Serving: \(Int(serving.rounded())) g")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let kcal = model.kilocaloriesPer100g(dish.ref) {
                Text("\(Int(kcal.rounded())) kcal/100g")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func hiddenRow(_ hidden: AllergenPartition<NativeDish>.Hidden) -> HiddenDishRow {
        HiddenDishRow(ref: hidden.item.ref, name: hidden.item.nameText,
                      reason: hidden.judgement.verdict.reason,
                      warning: hidden.judgement.warning ?? hidden.judgement.verdict.reason ?? "",
                      ingredients: [])
    }

    private func choose(_ dish: NativeDish) {
        // One serving, as Kitchen does — the same row, the same default
        // (2026-10-06). Was the whole stated yield, which is the whole pot.
        onSelect(dish.ref, dish.nameText, model.oneServingGrams(dish.ref))
        dismiss()
    }

    private func load() {
        do {
            results = try model.savedMeals()
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct ServingTarget: Identifiable {
    let dish: NativeDish
    var id: String { dish.ref.description }
}

/// How many servings one dish makes. One serving is the finished weight over
/// the count, which is what choosing the meal pre-fills; with no count the
/// whole dish is one serving.
@MainActor
struct DishServingCountSheet: View {
    let dish: NativeDish
    /// The finished weight of the whole dish. Nil for a dish with no weight
    /// (typed in from a label), where a count still divides nothing.
    let wholeGrams: Double?
    let onSave: (Int?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCounted: Bool
    @State private var count: Int
    @State private var error: String?

    /// Turned on for a dish with no count, the count starts at 2: the smallest
    /// count that changes what a serving is.
    static let firstCount = 2

    init(dish: NativeDish, wholeGrams: Double?, onSave: @escaping (Int?) throws -> Void) {
        self.dish = dish
        self.wholeGrams = wholeGrams
        self.onSave = onSave
        _isCounted = State(initialValue: dish.servingCount != nil)
        _count = State(initialValue: dish.servingCount ?? Self.firstCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Set a serving count", isOn: $isCounted)
                        .accessibilityIdentifier("serving-count-toggle")
                    if isCounted {
                        Stepper(value: $count, in: 1...50) {
                            Text("Servings: \(count)")
                        }
                        .accessibilityIdentifier("serving-count-stepper")
                    }
                } footer: {
                    Text("One serving is the finished dish divided by this count. With no count set, the whole dish is one serving.")
                }
                if let wholeGrams {
                    Section {
                        Text("Serving: \(Int((wholeGrams / Double(isCounted ? count : 1)).rounded())) g")
                            .accessibilityIdentifier("serving-count-preview")
                    }
                }
            }
            .navigationTitle(dish.nameText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try onSave(isCounted ? count : nil)
                            dismiss()
                        } catch {
                            self.error = String(describing: error)
                        }
                    }
                }
            }
            .editorError($error)
        }
    }
}
