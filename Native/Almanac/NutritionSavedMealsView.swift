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
@MainActor
struct NutritionSavedMealsView: View {
    @ObservedObject var model: NutritionModel
    let onSelect: (SourceIdentifier, String, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var results = SavedMealResults()
    @State private var error: String?

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
            .editorError($error)
        }
    }

    private func row(_ dish: NativeDish) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(dish.nameText).foregroundStyle(.primary)
                if let yield = dish.yieldGrams {
                    Text("Serving: \(Int(yield)) g")
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
        onSelect(dish.ref, dish.nameText, dish.yieldGrams)
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
