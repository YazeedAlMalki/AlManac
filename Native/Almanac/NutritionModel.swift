import SwiftUI
import AlmanacCore

/// A preview of what logging a food at a given mass would add to the day.
/// Each figure is independently optional, matching `NutritionTotals`: a food
/// missing fat data still shows the kcal and protein it does have.
struct MacroPreview: Hashable {
    let kilocalories: Double?
    let proteinGrams: Double?
    let fatGrams: Double?
    let carbohydrateGrams: Double?
}

/// Owns nutrition logging state for the app, the same way `HydrationModel`
/// owns hydration state — sharing the one `Database` connection rather than
/// opening a second (see `AlmanacApp.swift`).
@MainActor
final class NutritionModel: ObservableObject {
    @Published private(set) var todaysFoods: [LoggedFood] = []
    @Published private(set) var todaysTotals: NutritionTotals?
    @Published private(set) var isPreparingReference = false
    @Published private(set) var isReferenceAvailable = false
    @Published private(set) var referencePreparationError: String?
    /// Set when a read of today's log failed, cleared when one succeeds.
    /// Separate from `referencePreparationError`, which is about the bundled
    /// catalogue and offers a retry; this one is about the user's own entries
    /// and there is nothing to retry but the next read.
    @Published private(set) var readProblem: String?

    private var catalog: NutritionCatalog?
    private var summary: NutritionSummary?
    private var dishEditor: NutritionDishEditor?
    /// Readable outside this file so Kitchen (`NutritionModel+Kitchen.swift`)
    /// shares this connection instead of being configured with its own.
    private(set) var db: Database?
    private let timeModel = TimeModel(timeZone: .current)

    func configure(db: Database?) {
        guard let db, self.db == nil else { return } // already configured
        self.db = db
        let catalog = NutritionCatalog(db: db)
        self.catalog = catalog
        isReferenceAvailable = (try? catalog.hasReferenceFoods()) ?? false
        summary = NutritionSummary(db: db)
        dishEditor = NutritionDishEditor(db: db)
        refresh()
        prepareReference()
    }

    func retryReferencePreparation() {
        prepareReference()
    }

    private func prepareReference() {
        guard let db, !isPreparingReference else { return }
        isPreparingReference = !isReferenceAvailable
        referencePreparationError = nil
        let path = db.path
        // A second connection lets the rest of the app read through WAL while
        // this one owns the long first-install write transaction.
        Task { [weak self] in
            do {
                _ = try await Task.detached(priority: .utility) { () throws -> NutritionImportReport? in
                    let referenceDatabase = try Database(path: path)
                    let report = try NutritionReferenceBundle.installIfNeeded(into: referenceDatabase)
                    // Kitchen's ingredient table is derived from the catalog's
                    // names, so it is rebuilt whenever the catalog changes, and
                    // built once on a database that predates it (Migration 054).
                    let ingredients = IngredientTable(db: referenceDatabase)
                    var needsBuild = report != nil
                    if !needsBuild { needsBuild = try ingredients.isEmpty() }
                    if needsBuild { try ingredients.rebuild() }
                    return report
                }.value
                self?.isReferenceAvailable = true
                self?.refresh()
            } catch {
                self?.referencePreparationError = String(describing: error)
            }
            self?.isPreparingReference = false
        }
    }

    func refresh() {
        guard let summary else { return }
        let today = timeModel.logicalDay(Date())
        do {
            todaysFoods = try summary.loggedFoods(on: today, in: timeModel) ?? []
            todaysTotals = try summary.totals(on: today, in: timeModel)
            readProblem = nil
        } catch {
            // The same defect the hydration, training and readiness models had:
            // this comment promised the screen would "simply show stale figures
            // until the next refresh() succeeds", and the next `refresh()` fails
            // the same way — so there was no recovery here, only a screen that
            // looked the same whether it had no data or could not load it.
            readProblem = "Could not read today's food log."
        }
    }

    // MARK: Search and lookup

    /// Search, filtered by the allergens on the profile.
    ///
    /// The allergen set is read per search rather than cached on the model,
    /// because the thing that changes it is a trip to the profile screen and the
    /// cache would then be stale for as long as nobody thought to invalidate it.
    /// The read is two indexed lookups against a table with fourteen rows, on a
    /// screen that is already running a `LIKE` scan over the food catalogue — the
    /// invalidation bug it would prevent is worth more than the microseconds.
    func search(_ text: String) throws -> NutritionFoodSearchResults {
        // No catalog means no search, and no search means no filter has run — so
        // `allergens` is empty and `isFiltered` is false. That is the honest
        // answer: the screen stays silent about allergies rather than warning
        // about a filter that did not happen.
        guard let catalog, let db else { return NutritionFoodSearchResults() }
        // A failed read of the allergen list must not silently produce an
        // *unfiltered* search, which is the one result that looks safe. No
        // allergies can be reported means the gate is not in force, and
        // `NutritionFoodSearchResults.disclaimer` is where that has to be said —
        // so the empty set is right, and it is the caller's job not to read it as
        // "checked and clean".
        let allergens = (try? ProfileStore(db: db).allergenSet()) ?? []
        return try catalog.search(text, excluding: allergens)
    }

    /// Almanac's calorie number per 100 g, when the catalog can produce one.
    /// Not thrown on failure — a search result missing a calorie figure is
    /// still a valid row to show, just without that one detail.
    func kilocaloriesPer100g(_ ref: SourceIdentifier) -> Double? {
        guard let catalog else { return nil }
        return try? catalog.energy(for: ref, basis: .per100g)?.kilocalories
    }

    /// Saved meals with the allergen check applied — the same check Kitchen
    /// uses (`DishAllergenCheck`), because a saved meal and a recipe are the same
    /// row. Fails closed: a failed allergen read throws (`SavedMeals.list()`),
    /// and the screen shows the error rather than an unchecked list.
    /// One serving's weight of a dish — the amount a chosen saved meal
    /// pre-fills, as a chosen recipe does. Nil when the dish has no weight.
    func oneServingGrams(_ ref: SourceIdentifier) -> Double? {
        try? dishEditor?.oneServingGrams(of: ref)
    }

    func savedMeals() throws -> SavedMealResults {
        guard let db else { return SavedMealResults() }
        return try SavedMeals(db: db).list()
    }

    /// Household measures imported for a food. Most foods have none, so the
    /// picker also accepts a directly typed gram amount.
    func portions(for ref: SourceIdentifier) throws -> [NutritionPortion] {
        try catalog?.portions(of: ref) ?? []
    }

    /// Energy and the three macros, scaled to `grams`. Any figure the catalog
    /// cannot supply for this food comes back nil rather than as a silent
    /// zero — the same discipline `NutritionTotals` applies to a whole day.
    func macroPreview(for ref: SourceIdentifier, grams: Double) -> MacroPreview? {
        guard let catalog, let values = try? catalog.values(for: ref, basis: .per100g),
              !values.isEmpty else { return nil }
        func scaled(_ nutrientID: String) -> Double? {
            values.first(where: { $0.nutrientID == nutrientID })?.scaled(toGrams: grams)
        }
        let energy = EnergyEstimate.preferred(from: values, basis: .per100g)?.scaled(toGrams: grams)
        let carbohydrateGrams = scaled("carbohydrate_by_difference")
            ?? scaled("carbohydrate_available")
            ?? scaled("carbohydrate_available_monosaccharide")
        return MacroPreview(kilocalories: energy?.kilocalories, proteinGrams: scaled("protein"),
                            fatGrams: scaled("fat_total"), carbohydrateGrams: carbohydrateGrams)
    }

    // MARK: Writing

    func log(foodRef: SourceIdentifier, foodName: String, grams: Double?,
             quantityText: String?, mealType: NutritionMealType?) throws {
        guard let db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let draft = NutritionLogDraft(
            foodRef: foodRef, grams: grams,
            eatenAt: PartialDateTime(instant: Date(), zone: ZoneContext(TimeZone.current)),
            foodNameText: foodName, quantityText: quantityText, mealType: mealType)
        // Through the fasting-aware log, not the store: a meal ends an
        // intermittent fast (§11.1) or a religious one (any intake), and one
        // eaten between Maghrib and Fajr belongs to the night window (§7.2).
        // Writing to the store directly applied none of the fasting rules.
        try FastingAwareNutritionLog(db: db).record(draft)
        refresh()
    }

    func delete(id: String) throws {
        guard let db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        // Deleting the meal that ended a fast gives the fast back.
        try FastingAwareNutritionLog(db: db).delete(id: id)
        refresh()
    }
}
