import SwiftUI
import AlmanacCore

/// Owns nutrition logging state for the app, the same way `HydrationModel`
/// owns hydration state — sharing the one `Database` connection rather than
/// opening a second (see `AlmanacApp.swift`).
@MainActor
final class NutritionModel: ObservableObject {
    @Published private(set) var todaysFoods: [LoggedFood] = []
    @Published private(set) var todaysTotals: NutritionTotals?

    private var catalog: NutritionCatalog?
    private var logStore: NutritionLogStore?
    private var summary: NutritionSummary?
    private var dishEditor: NutritionDishEditor?
    private var db: Database?
    private let timeModel = TimeModel(timeZone: .current)

    func configure(db: Database?) {
        guard let db, self.db == nil else { return } // already configured
        self.db = db
        catalog = NutritionCatalog(db: db)
        logStore = NutritionLogStore(db: db)
        summary = NutritionSummary(db: db)
        dishEditor = NutritionDishEditor(db: db)
        refresh()
    }

    func refresh() {
        guard let summary else { return }
        let today = timeModel.logicalDay(Date())
        do {
            todaysFoods = try summary.loggedFoods(on: today, in: timeModel) ?? []
            todaysTotals = try summary.totals(on: today, in: timeModel)
        } catch {
            // A read failure here should not crash the screen; it will
            // simply show stale figures until the next refresh() succeeds.
        }
    }

    // MARK: Search and lookup

    func search(_ text: String) throws -> [NutritionFood] {
        guard let catalog else { return [] }
        return try catalog.search(text)
    }

    /// Almanac's calorie number per 100 g, when the catalog can produce one.
    /// Not thrown on failure — a search result missing a calorie figure is
    /// still a valid row to show, just without that one detail.
    func kilocaloriesPer100g(_ ref: SourceIdentifier) -> Double? {
        guard let catalog else { return nil }
        return try? catalog.energy(for: ref, basis: .per100g)?.kilocalories
    }

    func savedMeals() throws -> [NativeDish] {
        try dishEditor?.dishes() ?? []
    }

    // MARK: Writing

    func log(foodRef: SourceIdentifier, foodName: String, grams: Double?,
             quantityText: String?) throws {
        guard let logStore else { throw EditorFailure(message: "The database is unavailable.") }
        let draft = NutritionLogDraft(
            foodRef: foodRef, grams: grams,
            eatenAt: PartialDateTime(instant: Date(), zone: ZoneContext(TimeZone.current)),
            foodNameText: foodName, quantityText: quantityText)
        try logStore.record(draft)
        refresh()
    }

    func delete(id: String) throws {
        guard let logStore else { throw EditorFailure(message: "The database is unavailable.") }
        try logStore.delete(id: id)
        refresh()
    }
}
