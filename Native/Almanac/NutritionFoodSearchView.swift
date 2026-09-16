import SwiftUI
import AlmanacCore

/// Searches the reference catalog and hands back what was picked. Used both
/// from `NutritionQuickEntryView`'s "Select food" step and, indirectly, from
/// `NutritionSavedMealsView` sharing the same result row styling.
///
/// A picker, not a browser: there is no way to page through the whole catalog
/// unfiltered, matching `NutritionCatalog.search`'s own refusal to return
/// anything for an empty query.
@MainActor
struct NutritionFoodSearchView: View {
    @ObservedObject var model: NutritionModel
    let onSelect: (NutritionFood) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [NutritionFood] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(results, id: \.ref) { food in
                Button {
                    onSelect(food)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(food.primaryName)
                                .foregroundStyle(.primary)
                            Text(food.foodGroupName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let kcal = model.kilocaloriesPer100g(food.ref) {
                            Text("\(Int(kcal.rounded())) kcal/100g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if !query.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Food search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .searchable(text: $query, prompt: "Search foods")
            .onChange(of: query) { _, value in runSearch(value) }
            .editorError($error)
        }
    }

    private func runSearch(_ text: String) {
        do {
            results = try model.search(text)
        } catch {
            self.error = String(describing: error)
        }
    }
}
