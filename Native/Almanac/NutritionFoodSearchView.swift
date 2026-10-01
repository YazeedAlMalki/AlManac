import SwiftUI
import AlmanacCore

/// Searches the reference catalog and hands back what was picked. Used both
/// from `NutritionQuickEntryView`'s "Select food" step and, indirectly, from
/// `NutritionSavedMealsView` sharing the same result row styling.
///
/// A picker, not a browser: there is no way to page through the whole catalog
/// unfiltered, matching `NutritionCatalog.search`'s own refusal to return
/// anything for an empty query.
///
/// ## What the allergen note has to do here
///
/// The filter removes foods whose *names* declare one of the recorded allergens.
/// Two things follow, and both are the screen's problem rather than the store's:
///
/// 1. **Something withheld has to be visible.** A food that silently disappears
///    is a food the user concludes the app cannot find. A food that is visibly
///    withheld, with the reason, is a food they understand the app refusing.
/// 2. **Something removed has to be caveated.** The catalog carries no ingredient
///    data, so a clean result means only "no name here mentions peanut". Saying
///    nothing in that case is what makes the filter unsafe, not the filter.
///
/// So the note is present whenever the profile records any allergen — including
/// when nothing was removed, which is precisely the case that reads as a clean
/// bill of health. The sentence is `NutritionFoodSearchResults.note`, written and
/// tested in core, so this screen cannot describe the filter differently from the
/// way the filter behaves.
@MainActor
struct NutritionFoodSearchView: View {
    @ObservedObject var model: NutritionModel
    let onSelect: (NutritionFood) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: NutritionFoodSearchResults = NutritionFoodSearchResults()
    @State private var error: String?

    private var foods: [NutritionFood] { results.foods }

    var body: some View {
        NavigationStack {
            List {
                // Above the results, not below them, and not in a toolbar. It has
                // to be read *before* choosing the food it is qualifying, which
                // rules out everywhere that only appears once the list is read.
                if let note = results.note {
                    Section {
                        AlmanacProblemNote(text: note)
                    }
                }

                if !results.blocked.isEmpty {
                    Section {
                        ForEach(results.blocked) { withheld in
                            WithheldFoodRow(withheld: withheld)
                        }
                    } header: {
                        Text("Hidden by your allergens")
                    } footer: {
                        // Why the section exists, in the place a reader who has
                        // just been surprised will look. Without it, "hidden" reads
                        // as the app deciding on their behalf and refusing to say
                        // why — which is the reading that produces distrust of the
                        // filter, and distrust is why people stop relying on it.
                        Text("Almanac hid these because their name names one of your allergens. Nothing here can be added back.")
                    }
                }

                Section {
                    ForEach(foods, id: \.ref) { food in
                        row(for: food)
                    }
                } header: {
                    // `Text("Foods")` is not decoration. When a search for
                    // "coconut" returns six of forty milks, this heading is the
                    // only thing on screen that admits the list is a sample — and
                    // without it, a short list reads as complete.
                    Text(foods.isEmpty ? "Foods" : "Foods (\(foods.count))")
                } footer: {
                    if results.hitTheLimit {
                        // The SQL `LIMIT`, reached before the filter ran. Distinct
                        // from "no more matches", and the screen has to say which:
                        // a short list that is *also* truncated is not a complete
                        // list, and somebody hunting an allergen wants to know.
                        Text("More foods match than are shown. Try a shorter search to see the rest.")
                    }
                }
            }
            .overlay {
                emptyState
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

    /// Three different empty states, not one.
    ///
    /// The obvious implementation is `ContentUnavailableView.search(text:)` for
    /// everything, and it is actively wrong in two of the three cases: "no matches
    /// for your allergies" and "no matches in the catalogue" look identical and
    /// mean opposite things to somebody who is checking whether they can eat
    /// something. The blocked list is the answer to the first, so it is named in
    /// the message.
    @ViewBuilder
    private var emptyState: some View {
        // No `return` early-exit: a bare `return` in a `@ViewBuilder` body
        // disables the result builder for the whole property, so the three cases
        // below would stop being a `Group` and the function would have no
        // return value to infer. `EmptyView` is the same intent — build nothing —
        // and leaves the builder intact.
        if query.isEmpty || !foods.isEmpty {
            EmptyView()
        } else if results.isFiltered && !results.blocked.isEmpty {
            ContentUnavailableView {
                Label("Nothing left to show", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("\(results.blocked.count) of the foods matching “\(query)” name one of your allergens. They are listed above.")
            }
        } else if results.hitTheLimit {
            // Every match was withheld *and* the query was truncated: the person
            // may be typing a term whose remaining matches are all safe. Saying
            // "nothing left" here would be a much stronger claim than we can make.
            ContentUnavailableView {
                Label("Everything matching was withheld", systemImage: "hand.raised")
            } description: {
                Text("Almanac hid every food it had for “\(query)” because of your allergens. Try a shorter search — a broader term may match foods it did not reach.")
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func row(for food: NutritionFood) -> some View {
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

    private func runSearch(_ text: String) {
        do {
            results = try model.search(text)
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// A food the allergen filter withheld, named and greyed.
///
/// ## The name, and nothing that identifies it more precisely
///
/// The name is what makes this row useful — it is the only thing a reader can
/// match against what they were looking for. The `ref` is deliberately not
/// shown: `usda:1105904` is an upstream catalogue key, it identifies nothing the
/// user can act on, and printing it invites a support question ("what is
/// 1105904?") that only an engineer with the import script can answer.
///
/// ## Not tappable, and that is a safety decision
///
/// There is no override here. A row you can tap to reveal a food your allergy
/// filter withheld is a row that eventually gets tapped — and the person tapping
/// it is, by construction, somebody looking for something they are allergic to.
/// If an override is ever wanted it should be a deliberate, separately-named
/// choice by the owner, not a row in a list.
private struct WithheldFoodRow: View {
    let withheld: WithheldFood

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(withheld.name)
                .foregroundStyle(.secondary)
            if let reason = withheld.verdict.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
