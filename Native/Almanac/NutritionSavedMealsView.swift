import SwiftUI
import AlmanacCore

/// Lists the `almanac:` dishes the person has authored with
/// `NutritionDishEditor`, so a recipe assembled once can be logged again
/// without re-searching for it every time.
///
/// Picking a row hands its food back to `NutritionQuickEntryView` exactly as
/// `NutritionFoodSearchView` does — a saved meal is just a food with a name
/// the person already trusts, not a second logging path to maintain.
@MainActor
struct NutritionSavedMealsView: View {
    @ObservedObject var model: NutritionModel
    let onSelect: (SourceIdentifier, String, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var meals: [NativeDish] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("No saved meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("Dishes created for the food log will appear here.")
                    }
                } else {
                    List(meals, id: \.ref) { dish in
                        Button {
                            onSelect(dish.ref, dish.nameText, dish.yieldGrams)
                            dismiss()
                        } label: {
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

    private func load() {
        do {
            meals = try model.savedMeals()
        } catch {
            self.error = String(describing: error)
        }
    }
}
