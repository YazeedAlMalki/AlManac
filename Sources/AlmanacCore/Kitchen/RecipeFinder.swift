import Foundation

// MARK: - Values

/// One ingredient of a recipe, and whether it is on hand.
public struct RecipeIngredient: Sendable, Hashable {
    public let ref: SourceIdentifier
    /// Nil when the reference row has gone. The recipe still lists the
    /// ingredient and still counts it as missing or on hand; it just cannot
    /// name it — the same fact `RecipeReduction.missingComponents` reports from
    /// the nutrition side.
    public let name: String?
    public let grams: Double
    public let isOnHand: Bool
}

/// A recipe, its ingredients, and how much of it is on hand.
public struct RecipeMatch: Sendable, Hashable {
    /// The `almanac:` dish. Logging the recipe is logging this ref — a
    /// `nutrition_log` row whose `food_ref` is the dish, which is how a saved
    /// meal is already logged and why Kitchen has no link table of its own.
    public let recipe: SourceIdentifier
    public let name: String
    public let ingredients: [RecipeIngredient]
    /// The shared dish allergen check's judgement (`DishAllergenCheck`).
    public let allergen: DishAllergenJudgement

    public var verdict: AllergenVerdict { allergen.verdict }

    public var missing: [RecipeIngredient] { ingredients.filter { !$0.isOnHand } }
    public var onHandCount: Int { ingredients.count - missing.count }
}

/// One Kitchen response, and what the allergen filter did to it.
///
/// The recipe counterpart of `NutritionFoodSearchResults`, and held to the same
/// rule: the screen reports what the filter did and what it cannot do, never a
/// reassuring adjective.
public struct RecipeResults: Sendable, Hashable {
    public let recipes: [RecipeMatch]
    /// Recipes withheld because a name in them declares one of `allergens`.
    public let withheld: [RecipeMatch]
    public let effect: AllergenFilterEffect
    /// The allergens this lookup was filtered against.
    public let allergens: Set<FoodAllergen>

    public init(recipes: [RecipeMatch] = [], withheld: [RecipeMatch] = [],
                effect: AllergenFilterEffect = AllergenFilterEffect(),
                allergens: Set<FoodAllergen> = []) {
        self.recipes = recipes
        self.withheld = withheld
        self.effect = effect
        self.allergens = allergens
    }

    public var isFiltered: Bool { !allergens.isEmpty }

    /// Present whether or not anything was withheld, for the reason
    /// `NutritionFoodSearchResults.disclaimer` is. Worded differently because
    /// that sentence — "Almanac has no ingredient lists" — is false here: a
    /// recipe *is* its ingredient list. What is still true is that every check
    /// is a check of a name.
    public var disclaimer: String? {
        DishAllergenCheck.disclaimer(noun: "recipe", allergens: allergens)
    }

    public var note: String? {
        let parts = [effect.explanation, disclaimer].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Finder

/// Recipe lookup over Almanac's own dishes: what can be made from the pantry,
/// from what has been eaten lately, or by name.
///
/// ## A recipe is an `almanac:` dish with components
///
/// `NutritionDishEditor` already stores a recipe — components by `food_ref`, a
/// yield, and per-100 g values reduced from them. Kitchen reads those rows and
/// adds nothing to them, so a recipe found here and a saved meal on the log
/// screen are the same row, with the same numbers. A dish with values typed in
/// from a label and no components is a food, not a recipe, and never appears.
///
/// ## Matching is by `food_ref`, exactly
///
/// The pantry, the food log and a dish's components all hold `food_ref`s picked
/// from the same catalog search, so a match is a set intersection in SQL and no
/// ingredient text is parsed at read time. The cost is that "Chicken breast,
/// raw" (USDA) and "Chicken breast, roasted" (CoFID) are different ingredients.
/// Folding those together is a canonical-ingredient table's job, and it belongs
/// with whatever imports third-party recipes (docs/features/kitchen.md), not
/// with a query that has to be right for the person's own dishes today.
///
/// ## Allergens
///
/// Judged by `DishAllergenCheck`, the one check Saved meals uses as well. Same
/// contract as `NutritionCatalog.search(_:limit:excluding:)`: the person's
/// allergens are a parameter, not a dependency. A recipe is withheld when its
/// own name, or any ingredient's name — through nested dishes — declares one of
/// them. Everything else is `.noDeclaration`, which is not a safety claim.
public struct RecipeFinder: Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// Recipes that use at least one of `onHand`, fewest missing ingredients
    /// first, then most on hand, then by name.
    public func recipes(using onHand: Set<SourceIdentifier>,
                        excluding allergens: Set<FoodAllergen>,
                        limit: Int = 50) throws -> RecipeResults {
        guard !onHand.isEmpty, limit > 0 else { return RecipeResults(allergens: allergens) }
        let matches = try load(where: """
            c.dish_ref IN (SELECT dish_ref FROM nutrition_dish_component
                           WHERE component_ref IN (SELECT value FROM json_each(?)))
            """, [.text(try RecipeFinder.json(onHand))], onHand: onHand)
        return try finish(matches.sorted(by: RecipeFinder.fewestMissingFirst),
                          excluding: allergens, limit: limit)
    }

    /// Recipes that use what the pantry holds.
    public func fromPantry(excluding allergens: Set<FoodAllergen>,
                           limit: Int = 50) throws -> RecipeResults {
        try recipes(using: try KitchenPantry(db: db).refs(), excluding: allergens, limit: limit)
    }

    /// Recipes that use what was eaten in `[from, to)` — ISO-8601 prefixes, as
    /// `NutritionLogStore.logged(from:to:)` takes them, so a meal belongs to the
    /// window exactly when the timeline would place it there.
    ///
    /// A logged dish counts its own ingredients as eaten too. Somebody who logs
    /// "Omelette" bought eggs, and without this a person who mostly logs saved
    /// meals would get no suggestions at all.
    public func fromRecentLog(from: String, to: String,
                              excluding allergens: Set<FoodAllergen>,
                              limit: Int = 50) throws -> RecipeResults {
        let eaten = Set(try NutritionLogStore(db: db).logged(from: from, to: to).map(\.entry.foodRef))
        return try recipes(using: try throughRecipes(eaten), excluding: allergens, limit: limit)
    }

    /// Recipes whose name, in any language, contains `text` compared folded;
    /// every recipe when `text` is empty. Name order. What is on hand is read
    /// from the pantry, so the list can still say what each recipe is missing.
    public func browse(_ text: String,
                       excluding allergens: Set<FoodAllergen>,
                       limit: Int = 50) throws -> RecipeResults {
        guard limit > 0 else { return RecipeResults(allergens: allergens) }
        let pantry = try KitchenPantry(db: db).refs()
        let folded = TextFold.fold(text)
        let matches: [RecipeMatch]
        if folded.isEmpty {
            matches = try load(where: "1", [], onHand: pantry)
        } else {
            let pattern = "%" + folded.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            matches = try load(where: """
                c.dish_ref IN (SELECT food_ref FROM nutrition_food_name
                               WHERE name_fold LIKE ? ESCAPE '\\')
                """, [.text(pattern)], onHand: pantry)
        }
        return try finish(matches.sorted(by: RecipeFinder.byName), excluding: allergens, limit: limit)
    }

    // MARK: Reading

    /// Every recipe satisfying `condition` (over `nutrition_dish_component c`),
    /// with all of its ingredients — not only the ones that matched — in recipe
    /// order. One query; grouping is done here.
    private func load(where condition: String, _ parameters: [SQLValue],
                      onHand: Set<SourceIdentifier>) throws -> [RecipeMatch] {
        var order: [SourceIdentifier] = []
        var names: [SourceIdentifier: String] = [:]
        var ingredients: [SourceIdentifier: [RecipeIngredient]] = [:]
        for row in try db.query("""
            SELECT c.dish_ref, d.name AS dish_name, c.component_ref, c.grams,
                   n.name AS component_name
            FROM nutrition_dish_component c
            LEFT JOIN nutrition_food_name d ON d.food_ref = c.dish_ref AND d.is_primary = 1
            LEFT JOIN nutrition_food_name n ON n.food_ref = c.component_ref AND n.is_primary = 1
            WHERE \(condition)
            ORDER BY c.dish_ref, c.sequence;
            """, parameters) {
            guard let dish = row.string("dish_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let ref = row.string("component_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let grams = row.double("grams") else { continue }
            if ingredients[dish] == nil {
                order.append(dish)
                names[dish] = row.string("dish_name") ?? dish.description
            }
            ingredients[dish, default: []].append(
                RecipeIngredient(ref: ref, name: row.string("component_name"), grams: grams,
                                 isOnHand: onHand.contains(ref)))
        }
        return order.map {
            RecipeMatch(recipe: $0, name: names[$0] ?? $0.description,
                        ingredients: ingredients[$0] ?? [],
                        allergen: DishAllergenJudgement(ref: $0, verdict: AllergenVerdict(status: .notApplicable)))
        }
    }

    /// Applies the allergen check to an already-ranked list, then the limit.
    ///
    /// The check is `DishAllergenCheck`, the one Saved meals uses too: a recipe
    /// and a saved meal are the same row, so they cannot be judged by two rules.
    ///
    /// The limit comes after the filter, unlike the food search, because the
    /// ranking needs every candidate anyway — there is no `LIMIT` in SQL to put
    /// it before — and a withheld recipe should not cost a kept one its place.
    private func finish(_ ranked: [RecipeMatch], excluding allergens: Set<FoodAllergen>,
                        limit: Int) throws -> RecipeResults {
        let judged = try DishAllergenCheck(db: db).judge(ranked.map(\.recipe), allergens: allergens)
        var kept: [RecipeMatch] = []
        var withheld: [RecipeMatch] = []
        var triggered: Set<FoodAllergen> = []
        for match in ranked {
            let judgement = judged[match.recipe]
                ?? DishAllergenJudgement(ref: match.recipe, verdict: AllergenVerdict(status: .notApplicable))
            let judged = RecipeMatch(recipe: match.recipe, name: match.name,
                                     ingredients: match.ingredients, allergen: judgement)
            if judgement.isHidden {
                withheld.append(judged)
                triggered.formUnion(judgement.verdict.declared)
            } else if kept.count < limit {
                kept.append(judged)
            }
        }
        return RecipeResults(recipes: kept, withheld: withheld,
                             effect: AllergenFilterEffect(removed: withheld.count, kept: kept.count,
                                                          triggeredBy: triggered),
                             allergens: allergens)
    }

    /// `refs`, plus every ingredient under any of them that is a dish.
    private func throughRecipes(_ refs: Set<SourceIdentifier>) throws -> Set<SourceIdentifier> {
        guard !refs.isEmpty else { return [] }
        return Set(try db.query("""
            WITH RECURSIVE part(ref) AS (
                SELECT value FROM json_each(?)
                UNION
                SELECT c.component_ref FROM part
                JOIN nutrition_dish_component c ON c.dish_ref = part.ref
            )
            SELECT ref FROM part;
            """, [.text(try RecipeFinder.json(refs))])
            .compactMap { $0.string("ref").flatMap(SourceIdentifier.init(parsing:)) })
    }

    // MARK: Helpers

    /// A set of refs as a JSON array, for `json_each(?)` — one bound parameter
    /// however many refs, rather than a `?` per ref spliced into the SQL.
    private static func json(_ refs: Set<SourceIdentifier>) throws -> String {
        String(decoding: try JSONEncoder().encode(refs.map(\.description).sorted()), as: UTF8.self)
    }

    private static func fewestMissingFirst(_ a: RecipeMatch, _ b: RecipeMatch) -> Bool {
        if a.missing.count != b.missing.count { return a.missing.count < b.missing.count }
        if a.onHandCount != b.onHandCount { return a.onHandCount > b.onHandCount }
        return byName(a, b)
    }

    private static func byName(_ a: RecipeMatch, _ b: RecipeMatch) -> Bool {
        switch a.name.compare(b.name, options: .caseInsensitive) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.recipe.description < b.recipe.description
        }
    }
}
