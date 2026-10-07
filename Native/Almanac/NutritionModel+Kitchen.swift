import Foundation
import AlmanacCore

/// Kitchen's reads and pantry writes, on the nutrition model's connection.
///
/// An extension rather than a model of its own: Kitchen's only write to the
/// food log is the one every saved meal already makes — the picker hands a dish
/// back to `NutritionQuickEntryView`, which logs it through `log(...)` — so the
/// totals refresh and the §7.2 night-window assignment stay on one path.
///
/// Allergens are read per call, for the reason `search(_:)` gives — but a failed
/// read throws rather than becoming an empty set. An empty set means "no
/// allergies recorded", which drops both the filter and the disclaimer, so a
/// person with a peanut allergy would be shown an unfiltered list with nothing
/// on screen to say so. The picker shows the error instead.
extension NutritionModel {
    /// How far back "recently eaten" reaches. A week covers a normal shop.
    static let recentRecipeWindow: TimeInterval = 7 * 24 * 60 * 60

    func recipesFromPantry() throws -> RecipeResults {
        guard let db else { return RecipeResults() }
        return try RecipeFinder(db: db).fromPantry(excluding: try allergens(db))
    }

    func recipesFromRecentLog(now: Date = Date()) throws -> RecipeResults {
        guard let db else { return RecipeResults() }
        let format = ISO8601DateFormatter()
        return try RecipeFinder(db: db).fromRecentLog(
            from: format.string(from: now.addingTimeInterval(-NutritionModel.recentRecipeWindow)),
            // Half-open, so a meal logged this second is still inside it.
            to: format.string(from: now.addingTimeInterval(60)),
            excluding: try allergens(db))
    }

    func browseRecipes(_ text: String) throws -> RecipeResults {
        guard let db else { return RecipeResults() }
        return try RecipeFinder(db: db).browse(text, excluding: try allergens(db))
    }

    func pantryItems() throws -> [PantryItem] {
        guard let db else { return [] }
        return try KitchenPantry(db: db).items()
    }

    func addToPantry(_ food: NutritionFood) throws {
        guard let db else { throw EditorFailure(message: "The database is unavailable.") }
        try KitchenPantry(db: db).add(food.ref, nameText: food.primaryName)
    }

    func removeFromPantry(_ ref: SourceIdentifier) throws {
        guard let db else { throw EditorFailure(message: "The database is unavailable.") }
        try KitchenPantry(db: db).remove(ref)
    }

    /// Foods logged often enough to offer for the pantry (`PantrySuggestions`).
    /// Offered only; nothing is added until the person approves one.
    func pantrySuggestions(now: Date = Date()) throws -> [PantrySuggestion] {
        guard let db else { return [] }
        let time = TimeModel(timeZone: .current)
        return try PantrySuggestions(db: db).suggestions(today: time.logicalDay(now), timeModel: time)
    }

    func acceptPantrySuggestion(_ suggestion: PantrySuggestion) throws {
        guard let db else { throw EditorFailure(message: "The database is unavailable.") }
        try PantrySuggestions(db: db).accept(suggestion)
    }

    func dismissPantrySuggestion(_ suggestion: PantrySuggestion) throws {
        guard let db else { throw EditorFailure(message: "The database is unavailable.") }
        try PantrySuggestions(db: db).dismiss(suggestion.ref)
    }

    private func allergens(_ db: Database) throws -> Set<FoodAllergen> {
        try ProfileStore(db: db).allergenSet()
    }
}
