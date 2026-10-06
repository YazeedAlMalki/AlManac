import Foundation

/// The Saved meals list, judged against the person's allergens.
public struct SavedMealResults: Sendable, Hashable {
    /// The meals shown by default.
    public let meals: [NativeDish]
    /// Meals hidden by default because a name under them declares one of
    /// `allergens`. Still reachable: the screen lists them collapsed, and each
    /// opens on its own page under its `judgement.warning`.
    public let hidden: [AllergenPartition<NativeDish>.Hidden]
    /// The allergens this list was checked against.
    public let allergens: Set<FoodAllergen>

    public init(meals: [NativeDish] = [], hidden: [AllergenPartition<NativeDish>.Hidden] = [],
                allergens: Set<FoodAllergen> = []) {
        self.meals = meals
        self.hidden = hidden
        self.allergens = allergens
    }

    /// Present whenever allergens are recorded, hidden or not, for the reason
    /// `RecipeResults.disclaimer` gives.
    public var disclaimer: String? {
        DishAllergenCheck.disclaimer(noun: "meal", allergens: allergens)
    }
}

/// Saved meals — Almanac's own dishes — with the allergen check applied.
///
/// Until 2026-10-06 this list was not checked at all (`CONTEXT.md` recorded it
/// as the one gap with a safety argument behind it). A saved meal and a Kitchen
/// recipe are the same row, so both go through `DishAllergenCheck`.
public struct SavedMeals: Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// Every saved meal, with the allergens on the profile applied.
    ///
    /// **Fails closed.** A failed read of the allergen list throws rather than
    /// becoming an empty set: an empty set drops both the check and the
    /// disclaimer, which would show somebody with a peanut allergy an unchecked
    /// list with nothing on screen to say so. The screen shows the error.
    public func list() throws -> SavedMealResults {
        try list(excluding: try ProfileStore(db: db).allergenSet())
    }

    /// Every saved meal, checked against `allergens`.
    public func list(excluding allergens: Set<FoodAllergen>) throws -> SavedMealResults {
        let dishes = try NutritionDishEditor(db: db).dishes()
        let split = try DishAllergenCheck(db: db).partition(dishes, ref: \.ref, allergens: allergens)
        return SavedMealResults(meals: split.shown, hidden: split.hidden, allergens: allergens)
    }
}
