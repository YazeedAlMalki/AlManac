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
    /// An imported recipe with no serving count, waiting on the question.
    @State private var askingServings: RecipeMatch?
    /// The answer, handed on once the question has closed: closing the picker
    /// from inside the question's own dismissal would close both at once.
    @State private var answered: (match: RecipeMatch, servings: Int?)?
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

                // Hidden by default and reachable: collapsed, and each one opens
                // on its own page under its warning (`HiddenDishesSection`, the
                // same entry Saved meals shows). Above the recipes, not below:
                // with the Wikibooks recipes the list runs to some three hundred
                // rows, and an entry under them would never be seen.
                HiddenDishesSection(rows: results.withheld.map(hiddenRow),
                                    disclaimer: results.disclaimer) { row in
                    if let match = results.withheld.first(where: { $0.recipe == row.ref }) {
                        choose(match)
                    }
                }

                Section {
                    if results.recipes.isEmpty {
                        Text(emptyText).foregroundStyle(.secondary)
                    } else {
                        ForEach(results.recipes, id: \.recipe) { match in
                            HStack(spacing: 8) {
                                Button { choose(match) } label: { RecipeRow(match: match) }
                                    .buttonStyle(.plain)
                                // CC BY-SA asks for a link to the work with the
                                // credit: the page itself, one tap away.
                                if let url = match.source?.pageURL {
                                    Link(destination: url) {
                                        Image(systemName: "book")
                                            .foregroundStyle(AlmanacPalette.accent)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Open \(match.name) on Wikibooks")
                                    .accessibilityIdentifier("recipe-source-link-\(match.recipe.localID)")
                                }
                            }
                        }
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
            .sheet(item: $askingServings, onDismiss: {
                if let answered { hand(answered.match, servings: answered.servings) }
                answered = nil
            }) { match in
                RecipeServingsQuestion(match: match) { count in
                    if let count { try model.setServingCount(count, for: match.recipe) }
                    answered = (match, count)
                }
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
            return String(localized: "None of your recipes use what you have logged this week.")
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
                      ingredients: match.ingredients.map { $0.name ?? String(localized: "An unnamed ingredient") })
    }

    private func choose(_ match: RecipeMatch) {
        // An imported recipe whose page gave no serving count is the whole pot
        // until someone says how many it makes, so Kitchen asks the first time
        // (`CONTEXT.md`, Kitchen 2026-10-06). The answer is kept on the dish.
        if match.source != nil, match.servingCount == nil {
            askingServings = match
            return
        }
        hand(match, servings: match.servingCount)
    }

    /// One serving (owner, 2026-10-06), still editable in the form: the
    /// finished weight over the serving count, or the whole dish when no count
    /// is set (`RecipeMatch.oneServingGrams`).
    private func hand(_ match: RecipeMatch, servings: Int?) {
        let whole = match.yieldGrams ?? match.ingredients.reduce(0) { $0 + $1.grams }
        let grams = whole > 0 ? whole / Double(servings ?? 1) : nil
        onSelect(match.recipe, match.name, grams)
        dismiss()
    }
}

/// A recipe's name, what it still needs, and a tally of its ingredients.
///
/// The words say *which* ingredients are missing; the tally answers the
/// question the list is scanned for — which recipe is nearest — without
/// reading every line. "Everything on hand" is the one judgement here, so it
/// alone takes a status colour.
private struct RecipeRow: View {
    let match: RecipeMatch

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(match.name)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text(summary)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(match.missing.isEmpty ? AlmanacPalette.good : AlmanacPalette.textSecondary)
                    .lineLimit(2)
                if let source = match.source {
                    Text(source.credit)
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            IngredientTally(onHand: match.onHandCount, total: match.ingredients.count)
        }
    }

    private var summary: String {
        let missing = match.missing
        guard !missing.isEmpty else { return String(localized: "Everything on hand") }
        // An ingredient whose reference row has gone is still missing; it just
        // cannot be named, and it is not dropped from the count.
        let names = missing.map { $0.name ?? "an unnamed ingredient" }
        return String(localized: "Missing \(names.joined(separator: String(localized: ", ")))")
    }
}

/// One mark per ingredient, filled when it is on hand, over the count.
///
/// Hidden from VoiceOver: the row's words already say what is missing, and a
/// row of dots read aloud says nothing. It also keeps the row's button label
/// starting with the recipe's name, which the UI tests look it up by.
private struct IngredientTally: View {
    let onHand: Int
    let total: Int
    /// Past this many marks the count alone reads faster than the dots.
    private static let maximumMarks = 8

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if total <= Self.maximumMarks {
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { index in
                        Circle()
                            .fill(index < onHand ? AlmanacPalette.textPrimary : AlmanacPalette.surfaceMuted)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            Text("\(onHand)/\(total)")
                .font(AlmanacTypography.font(.caption).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .accessibilityHidden(true)
    }
}

/// The declared pantry: what Kitchen matches recipes against.
///
/// Above it, foods logged often are *offered* (`PantrySuggestions`), and the
/// person adds or dismisses each — the owner's "declared, with suggestions"
/// (2026-10-06). Nothing reaches the pantry without a tap here.
@MainActor
private struct KitchenPantryView: View {
    @ObservedObject var model: NutritionModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PantryItem] = []
    @State private var suggestions: [PantrySuggestion] = []
    @State private var showingSearch = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty && suggestions.isEmpty {
                    ContentUnavailableView {
                        Label("Your pantry is empty", systemImage: "basket")
                    } description: {
                        Text("Add the foods you have, and Kitchen will find recipes that use them.")
                    }
                } else {
                    List {
                        if !suggestions.isEmpty {
                            Section {
                                ForEach(suggestions, id: \.ref) { suggestion in
                                    suggestionRow(suggestion)
                                }
                            } header: {
                                Text("Logged often — add to your pantry?")
                            } footer: {
                                Text("Foods you logged on \(PantrySuggestions.minimumDays) or more of the last \(PantrySuggestions.windowDays) days. Nothing is added unless you add it, and a dismissed food is not offered again.")
                            }
                        }
                        Section("In your pantry") {
                            if items.isEmpty {
                                Text("Your pantry is empty").foregroundStyle(.secondary)
                            } else {
                                ForEach(items, id: \.ref) { item in
                                    Text(item.nameText ?? item.ref.description)
                                }
                                .onDelete(perform: remove)
                            }
                        }
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

    private func suggestionRow(_ suggestion: PantrySuggestion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name ?? suggestion.ref.description)
                Text("Logged on \(suggestion.daysLogged) of the last \(PantrySuggestions.windowDays) days")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Borderless, so the two buttons in one row are two targets rather
            // than one row-wide tap that fires both.
            Button("Dismiss") { decide(suggestion, accept: false) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pantry-suggestion-dismiss-\(suggestion.ref.localID)")
            Button("Add") { decide(suggestion, accept: true) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("pantry-suggestion-add-\(suggestion.ref.localID)")
        }
    }

    private func load() {
        do {
            items = try model.pantryItems()
            suggestions = try model.pantrySuggestions()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func decide(_ suggestion: PantrySuggestion, accept: Bool) {
        do {
            if accept {
                try model.acceptPantrySuggestion(suggestion)
            } else {
                try model.dismissPantrySuggestion(suggestion)
            }
            load()
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

extension RecipeMatch: @retroactive Identifiable {
    public var id: SourceIdentifier { recipe }
}

/// "How many servings does this make?" — asked once, the first time an
/// imported recipe with no stated count is chosen. "Not now" logs the whole
/// recipe as one serving and asks again next time; a count is kept on the dish
/// and is what Saved meals' "Servings" would show for it.
private struct RecipeServingsQuestion: View {
    let match: RecipeMatch
    let onAnswer: (Int?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var count = DishServingCountSheet.firstCount
    @State private var error: String?

    private var wholeGrams: Double {
        match.yieldGrams ?? match.ingredients.reduce(0) { $0 + $1.grams }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $count, in: 1...50) {
                        Text("Servings: \(count)")
                    }
                    .accessibilityIdentifier("recipe-servings-stepper")
                    if wholeGrams > 0 {
                        Text("Serving: \(Int((wholeGrams / Double(count)).rounded())) g")
                            .accessibilityIdentifier("recipe-servings-preview")
                    }
                } header: {
                    Text("How many servings does this make?")
                } footer: {
                    Text("The recipe's page does not say. Your answer is kept for next time.")
                }
            }
            .navigationTitle(match.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { answer(nil) }
                        .accessibilityIdentifier("recipe-servings-not-now")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { answer(count) }
                        .accessibilityIdentifier("recipe-servings-continue")
                }
            }
            .editorError($error)
        }
        .presentationDetents([.medium])
    }

    private func answer(_ count: Int?) {
        do {
            try onAnswer(count)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
