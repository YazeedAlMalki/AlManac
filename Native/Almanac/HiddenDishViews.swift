import SwiftUI
import AlmanacCore

/// One dish the allergen check hid, as the collapsed list shows it.
struct HiddenDishRow: Identifiable, Hashable {
    let ref: SourceIdentifier
    let name: String
    /// `AllergenVerdict.reason` — "Names Peanuts".
    let reason: String?
    /// `DishAllergenJudgement.warning`, shown on the dish's own page.
    let warning: String
    /// Ingredient names, when the dish has any. Shown on the page so the
    /// person can see what the warning is about.
    let ingredients: [String]

    var id: SourceIdentifier { ref }
}

/// The collapsed "Hidden because of your allergens" entry, shared by Kitchen
/// and Saved meals so both say the same thing in the same place
/// (`DishAllergenCheck` is the shared rule; this is the shared screen half).
///
/// Collapsed by default, because the owner's decision (2026-10-06) is that a
/// conflicting dish is **hidden** by default — but reachable, so he can open one
/// deliberately and read the warning on its own page.
struct HiddenDishesSection: View {
    let rows: [HiddenDishRow]
    /// The disclaimer, repeated on each page.
    let disclaimer: String?
    let onLogAnyway: (HiddenDishRow) -> Void
    @State private var expanded = false

    var body: some View {
        if !rows.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(rows) { row in
                        NavigationLink {
                            HiddenDishPage(row: row, disclaimer: disclaimer) { onLogAnyway(row) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                if let reason = row.reason {
                                    Text(reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("allergen-hidden-row-\(row.ref.localID)")
                    }
                } label: {
                    Label("Hidden because of your allergens (\(rows.count))",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AlmanacPalette.warning)
                }
                .accessibilityIdentifier("allergen-hidden-toggle")
            }
        }
    }
}

/// A hidden dish's own page: the warning first, then what is in it, then a way
/// to log it that asks first.
///
/// The confirmation is a decision taken without an answer (2026-10-06,
/// `CONTEXT.md`): the owner said a hidden recipe can be opened and carries a
/// warning; he did not say whether logging it should ask again. It asks,
/// because the cost of one more tap is small and the cost of logging the wrong
/// thing by reflex is not.
struct HiddenDishPage: View {
    let row: HiddenDishRow
    let disclaimer: String?
    let onLogAnyway: () -> Void
    @State private var confirming = false

    var body: some View {
        List {
            Section {
                AlmanacProblemNote(text: row.warning)
                    .accessibilityIdentifier("allergen-warning")
            }
            if !row.ingredients.isEmpty {
                Section("Ingredients") {
                    ForEach(Array(row.ingredients.enumerated()), id: \.offset) { _, name in
                        Text(name)
                    }
                }
            }
            if let disclaimer {
                Section { Text(disclaimer).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Button("Log anyway…", role: .destructive) { confirming = true }
                    .accessibilityIdentifier("allergen-log-anyway")
            }
        }
        .navigationTitle(row.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Log \(row.name) anyway?", isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("Log anyway", role: .destructive) { onLogAnyway() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(row.warning)
        }
    }
}
