import SwiftUI
import AlmanacCore

/// Kitchen: recipes that use what is in the pantry, what was eaten this week,
/// or that match a name — each one an `almanac:` dish built from ingredients.
///
/// A picker, the same shape as `NutritionSavedMealsView`: choosing a recipe
/// hands its dish back to `NutritionQuickEntryView`, which logs it. A recipe
/// *is* a saved meal with a component list, so there is no second logging path.
@MainActor
struct KitchenRecipesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case pantry = "Pantry"
        case recent = "This week"
        case browse = "All"
        var id: String { rawValue }
    }

    @ObservedObject var model: NutritionModel
    let onSelect: (SourceIdentifier, String, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .pantry
    @State private var query = ""
    @State private var results = RecipeResults()
    @State private var pantryIsEmpty = true
    @State private var showingPantry = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Find recipes", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .browse {
                        TextField("Recipe name", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                // Above the results, for the reason `NutritionFoodSearchView`
                // gives: it qualifies the list, so it is read before choosing.
                if let note = results.note {
                    Section { AlmanacProblemNote(text: note) }
                }

                Section {
                    if results.recipes.isEmpty {
                        Text(emptyText).foregroundStyle(.secondary)
                    } else {
                        ForEach(results.recipes, id: \.recipe) { match in
                            Button { choose(match) } label: { RecipeRow(match: match) }
                        }
                    }
                }

                // Hidden by default and reachable: collapsed, and each one opens
                // on its own page under its warning (`HiddenDishesSection`, the
                // same entry Saved meals shows).
                HiddenDishesSection(rows: results.withheld.map(hiddenRow),
                                    disclaimer: results.disclaimer) { row in
                    if let match = results.withheld.first(where: { $0.recipe == row.ref }) {
                        choose(match)
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Pantry") { showingPantry = true } }
            }
            .sheet(isPresented: $showingPantry, onDismiss: load) {
                KitchenPantryView(model: model)
            }
            .task(id: mode) { load() }
            .onChange(of: query) { load() }
            .editorError($error)
        }
    }

    private var emptyText: String {
        switch mode {
        case .pantry:
            return pantryIsEmpty
                ? "Add what is in your kitchen to see recipes you can make with it."
                : "None of your recipes use what is in your pantry."
        case .recent:
            return "None of your recipes use what you have logged this week."
        case .browse:
            return query.isEmpty
                ? "No recipes yet. A saved meal built from ingredients is a recipe."
                : "No recipe names match."
        }
    }

    private func load() {
        do {
            pantryIsEmpty = try model.pantryItems().isEmpty
            switch mode {
            case .pantry: results = try model.recipesFromPantry()
            case .recent: results = try model.recipesFromRecentLog()
            case .browse: results = try model.browseRecipes(query)
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func hiddenRow(_ match: RecipeMatch) -> HiddenDishRow {
        HiddenDishRow(ref: match.recipe, name: match.name, reason: match.verdict.reason,
                      warning: match.allergen.warning ?? match.verdict.reason ?? "",
                      ingredients: match.ingredients.map { $0.name ?? "An unnamed ingredient" })
    }

    private func choose(_ match: RecipeMatch) {
        // No default amount: a recipe's total weight is usually several
        // servings, and pre-filling it would log the whole pot.
        onSelect(match.recipe, match.name, nil)
        dismiss()
    }
}

/// A recipe's name, and what it still needs.
private struct RecipeRow: View {
    let match: RecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.name).foregroundStyle(.primary)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var summary: String {
        let missing = match.missing
        guard !missing.isEmpty else { return "Everything on hand" }
        // An ingredient whose reference row has gone is still missing; it just
        // cannot be named, and it is not dropped from the count.
        let names = missing.map { $0.name ?? "an unnamed ingredient" }
        return "Missing \(names.joined(separator: ", "))"
    }
}

/// The declared pantry: what Kitchen matches recipes against.
@MainActor
private struct KitchenPantryView: View {
    @ObservedObject var model: NutritionModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PantryItem] = []
    @State private var showingSearch = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Your pantry is empty", systemImage: "basket")
                    } description: {
                        Text("Add the foods you have, and Kitchen will find recipes that use them.")
                    }
                } else {
                    List {
                        ForEach(items, id: \.ref) { item in
                            Text(item.nameText ?? item.ref.description)
                        }
                        .onDelete(perform: remove)
                    }
                }
            }
            .navigationTitle("Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Add") { showingSearch = true } }
            }
            .sheet(isPresented: $showingSearch) {
                NutritionFoodSearchView(model: model) { food in add(food) }
            }
            .task { load() }
            .editorError($error)
        }
    }

    private func load() {
        do {
            items = try model.pantryItems()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func add(_ food: NutritionFood) {
        do {
            try model.addToPantry(food)
            load()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func remove(at offsets: IndexSet) {
        do {
            for index in offsets { try model.removeFromPantry(items[index].ref) }
            load()
        } catch {
            self.error = String(describing: error)
        }
    }
}
