import Foundation
import Testing
@testable import AlmanacCore

/// Kitchen's ingredient table: the merge rule, matching through it, and the
/// allergen check reading through it without getting weaker (2026-10-06).
@Suite("Ingredient table")
struct IngredientTableTests {
    let db = try! TestDatabase()
    var editor: NutritionDishEditor { NutritionDishEditor(db: db) }

    func food(_ id: String, _ name: String) throws -> SourceIdentifier {
        try editor.create(localID: id, nameText: name)
    }

    func recipe(_ id: String, _ name: String, _ parts: [SourceIdentifier]) throws -> SourceIdentifier {
        let ref = try editor.create(localID: id, nameText: name)
        try editor.setRecipe(parts.map { DishComponent($0, grams: 100) }, for: ref)
        return ref
    }

    // MARK: The rule

    @Test("Raw and roasted chicken breast are one ingredient")
    func preparationIsSetAside() {
        let raw = IngredientNormaliser.key(for: "Chicken breast, raw")
        #expect(raw == "chicken breast")
        #expect(IngredientNormaliser.key(for: "Chicken breast, roasted") == raw)
        #expect(IngredientNormaliser.key(for: "Chicken, breast, without skin, grilled/pan-fried") == raw)
        #expect(IngredientNormaliser.key(for: "Chicken, broilers or fryers, breast, meat only, cooked, roasted") == raw)
    }

    @Test("A breaded or coated variant never merges")
    func compositionIsGuarded() {
        #expect(IngredientNormaliser.key(for: "Chicken breast, breaded, fried") == nil)
        #expect(IngredientNormaliser.key(for: "Chicken breast/steak, coated, baked") == nil)
        #expect(IngredientNormaliser.key(for: "Chicken breast in sauce") == nil)
    }

    @Test("Form words are kept: dried apricots are not fresh ones")
    func formIsKept() {
        #expect(IngredientNormaliser.key(for: "Apricots, dried") == "apricot dried")
        #expect(IngredientNormaliser.key(for: "Apricot, dried") == "apricot dried")
        #expect(IngredientNormaliser.key(for: "Apricots, raw") == "apricot")
        #expect(IngredientNormaliser.key(for: "Tomatoes, raw") == "tomato")
        #expect(IngredientNormaliser.key(for: "Strawberries, raw") == "strawberry")
    }

    // MARK: Matching through it

    @Test("A recipe naming roasted chicken breast is made from a pantry holding raw")
    func pantryMatchesThroughTheTable() throws {
        let raw = try food("chicken-raw", "Chicken breast, raw")
        let roasted = try food("chicken-roasted", "Chicken breast, roasted")
        let breaded = try food("chicken-breaded", "Chicken breast, breaded, fried")
        let salad = try recipe("salad", "Chicken salad", [roasted])
        let goujons = try recipe("goujons", "Goujons", [breaded])
        try KitchenPantry(db: db).add(raw, nameText: "Chicken breast, raw")

        // Before the table is built, exact refs only: nothing matches.
        #expect(try RecipeFinder(db: db).fromPantry(excluding: []).recipes.isEmpty)

        try IngredientTable(db: db).rebuild()
        let found = try RecipeFinder(db: db).fromPantry(excluding: [])
        #expect(found.recipes.map(\.recipe) == [salad])
        #expect(found.recipes.first?.missing.isEmpty == true)
        #expect(found.recipes.first?.ingredients.first?.ingredientName == "Chicken breast")
        #expect(!found.recipes.map(\.recipe).contains(goujons), "the breaded variant merged silently")
    }

    @Test("The log matches through it too, and an unmapped food still matches itself")
    func logAndIdentity() throws {
        let raw = try food("chicken-raw", "Chicken breast, raw")
        let roasted = try food("chicken-roasted", "Chicken breast, roasted")
        let breaded = try food("chicken-breaded", "Chicken breast, breaded, fried")
        let salad = try recipe("salad", "Chicken salad", [roasted])
        let goujons = try recipe("goujons", "Goujons", [breaded])
        try IngredientTable(db: db).rebuild()

        #expect(try RecipeFinder(db: db).recipes(using: [raw], excluding: []).recipes.map(\.recipe) == [salad])
        // The breaded food has no ingredient, so it matches by its own ref, as before.
        #expect(try RecipeFinder(db: db).recipes(using: [breaded], excluding: []).recipes.map(\.recipe) == [goujons])
    }

    @Test("A rebuild keeps curated mappings and applies the aliases")
    func curatedSurvivesRebuild() throws {
        let egg = try food("egg", "Egg, raw")
        let hen = try food("hen-egg", "Eggs, chicken, whole, raw")
        let odd = try food("odd", "Mystery thing")
        let table = IngredientTable(db: db)
        try table.curate(odd, as: "chicken breast")
        try table.rebuild()
        try table.rebuild()

        #expect(try table.ingredient(of: egg)?.id == IngredientNormaliser.id(forKey: "egg chicken whole"))
        #expect(try table.ingredient(of: hen)?.id == IngredientNormaliser.id(forKey: "egg chicken whole"))
        #expect(try table.ingredient(of: odd)?.id == IngredientNormaliser.id(forKey: "chicken breast"))
    }

    // MARK: The allergen check is no weaker

    @Test("A food's own allergen-naming name still hides the recipe when its ingredient's name is silent")
    func allergenCheckIsNoWeaker() throws {
        let sauce = try food("satay-sauce", "Satay sauce, peanut")
        let rice = try food("rice", "Rice, raw")
        let satay = try recipe("satay", "Weeknight satay", [rice, sauce])
        let table = IngredientTable(db: db)
        // Map the sauce to an ingredient whose own name does not say peanut —
        // the worst case for a check that read only canonical names.
        try table.curate(sauce, as: "satay")
        try table.rebuild()
        #expect(try table.ingredient(of: sauce)?.name == "Satay")

        let kitchen = try RecipeFinder(db: db).browse("", excluding: [.peanuts])
        #expect(kitchen.withheld.map(\.recipe).contains(satay))
        #expect(!kitchen.recipes.map(\.recipe).contains(satay))
        let saved = try SavedMeals(db: db).list(excluding: [.peanuts])
        #expect(saved.hidden.map(\.item.ref).contains(satay))
    }

    @Test("An ingredient's name that declares an allergen is read as well")
    func canonicalNameAddsEvidence() throws {
        let paste = try food("paste", "Brown spread")
        let toast = try recipe("toast", "Toast with paste", [paste])
        #expect(try RecipeFinder(db: db).browse("", excluding: [.peanuts]).withheld.isEmpty,
                "precondition: the food's own name does not say peanut")
        try IngredientTable(db: db).curate(paste, as: "peanut butter")

        #expect(try RecipeFinder(db: db).browse("", excluding: [.peanuts]).withheld.map(\.recipe) == [toast])
    }
}

/// The rule against the lake that actually ships.
@Suite("Ingredient table on the shipped lake")
struct IngredientTableShippedLakeTests {
    @Test("Chicken breast from four sources is one ingredient; the coated one is not")
    func shippedLake() throws {
        let db = try TestDatabase()
        _ = try #require(try NutritionReferenceBundle.installIfNeeded(into: db))
        let table = IngredientTable(db: db)
        let mapped = try table.rebuild()
        #expect(mapped > 7_000, "mapped \(mapped)")

        let breast = IngredientNormaliser.id(forKey: "chicken breast")
        for ref in ["usda:2646170", "cofid:18-307", "ciqual:36017", "afcd:F002594"] {
            #expect(try table.ingredient(of: SourceIdentifier(parsing: ref)!)?.id == breast, "\(ref)")
        }
        // CoFID's "Chicken breast/steak, coated, baked".
        #expect(try table.ingredient(of: SourceIdentifier(parsing: "cofid:18-504")!) == nil)
        // A second rebuild is the same table.
        #expect(try table.rebuild() == mapped)
    }
}
