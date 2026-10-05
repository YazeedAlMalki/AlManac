import Foundation
import Testing
@testable import AlmanacCore

/// Kitchen: the declared pantry, and recipe lookup over `almanac:` dishes by
/// pantry, by recent food log, and by name — with the allergen filter.
@Suite("Kitchen")
struct KitchenTests {
    let db = try! TestDatabase()
    var pantry: KitchenPantry { KitchenPantry(db: db) }
    var finder: RecipeFinder { RecipeFinder(db: db) }
    var dishes: NutritionDishEditor { NutritionDishEditor(db: db) }
    var log: NutritionLogStore { NutritionLogStore(db: db) }

    init() throws {
        // `nutrition_food.namespace` references `nutrition_source`, and a
        // reduced recipe writes `protein` rows that reference `nutrition_nutrient`.
        for (namespace, group) in [("usda", "A"), ("almanac", "N")] {
            try db.run("""
                INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence,
                                              licence_group, attribution, url)
                VALUES (?, ?, ?, '2026', 'x', ?, '', '');
                """, [.text(namespace), .text(namespace), .text(namespace), .text(group)])
        }
        try db.run("""
            INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
            VALUES ('protein', 'PROCNT', 'protein', 'g', '');
            """)
    }

    // MARK: Fixtures

    @discardableResult
    func food(_ localID: String, _ name: String, protein: Double = 5) throws -> SourceIdentifier {
        let ref = SourceIdentifier(namespace: .usda, localID: localID)
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                        food_group_code, food_group_name, source_record)
            VALUES (?, 'usda', ?, 'A', '', '', 'fixture');
            """, [.text(ref.description), .text(localID)])
        try db.run("""
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
            VALUES (?, 'en', ?, 1, ?);
            """, [.text(ref.description), .text(name), .text(TextFold.fold(name))])
        try db.run("""
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier,
                                         source_value, source_nutrient_id, source_unit, licence_group)
            VALUES (?, 'protein', 'per_100g', ?, 'measured', ?, 'protein', 'g', 'A');
            """, [.text(ref.description), .real(protein), .text(String(protein))])
        return ref
    }

    @discardableResult
    func recipe(_ localID: String, _ name: String,
                _ parts: [SourceIdentifier]) throws -> SourceIdentifier {
        let ref = try dishes.create(localID: localID, nameText: name)
        try dishes.setRecipe(parts.map { DishComponent($0, grams: 100) }, for: ref)
        return ref
    }

    func eat(_ ref: SourceIdentifier, at iso: String) throws -> String {
        let instant = try #require(ISO8601DateFormatter().date(from: iso))
        return try log.record(NutritionLogDraft(
            foodRef: ref, grams: 100,
            eatenAt: PartialDateTime(instant: instant, zone: ZoneContext(TimeZone(identifier: "UTC")!))
        )).logID
    }

    // MARK: Pantry

    @Test("Recipes using the pantry come back fewest-missing first, with what is missing named")
    func pantryRanking() throws {
        let egg = try food("egg", "Egg")
        let milk = try food("milk", "Milk")
        let flour = try food("flour", "Flour")
        let tomato = try food("tomato", "Tomato")
        try recipe("pancakes", "Pancakes", [egg, milk, flour])
        try recipe("omelette", "Omelette", [egg, milk])
        try recipe("salad", "Salad", [tomato])
        try pantry.add(egg, nameText: "Egg")
        try pantry.add(milk, nameText: "Milk")

        let results = try finder.fromPantry(excluding: [])
        #expect(results.recipes.map(\.name) == ["Omelette", "Pancakes"])
        #expect(results.recipes[0].missing.isEmpty)
        #expect(results.recipes[1].missing.map(\.name) == ["Flour"])
        #expect(results.recipes[1].onHandCount == 2)
        // Nothing for the salad is on hand, so it is not a suggestion at all.
        #expect(!results.recipes.contains { $0.name == "Salad" })
    }

    @Test("An empty pantry suggests nothing, and says nothing about allergens it did not check")
    func emptyPantry() throws {
        try recipe("salad", "Salad", [try food("tomato", "Tomato")])
        let results = try finder.fromPantry(excluding: [])
        #expect(results.recipes.isEmpty)
        #expect(results.note == nil)
    }

    @Test("Adding a food twice keeps one row; removing reports whether anything went")
    func pantryIsPresenceNotQuantity() throws {
        let egg = try food("egg", "Egg")
        try pantry.add(egg, nameText: "Egg")
        try pantry.add(egg, nameText: nil)
        let items = try pantry.items()
        #expect(items.count == 1)
        // A nil name on the second add does not erase the name the first one kept.
        #expect(items.first?.nameText == "Egg")
        #expect(try pantry.remove(egg))
        #expect(try !pantry.remove(egg))
        #expect(try pantry.items().isEmpty)
    }

    // MARK: Recent food log

    @Test("Foods eaten in the window suggest recipes; earlier and deleted entries do not")
    func recentLogWindow() throws {
        let egg = try food("egg", "Egg")
        let milk = try food("milk", "Milk")
        let flour = try food("flour", "Flour")
        let tomato = try food("tomato", "Tomato")
        try recipe("pancakes", "Pancakes", [egg, milk, flour])
        try recipe("omelette", "Omelette", [egg, milk])
        try recipe("salad", "Salad", [tomato])

        _ = try eat(tomato, at: "2026-10-03T12:00:00Z")
        _ = try eat(flour, at: "2026-09-01T12:00:00Z")   // before the window
        let deleted = try eat(egg, at: "2026-10-04T08:00:00Z")
        try log.delete(id: deleted)

        let results = try finder.fromRecentLog(from: "2026-10-01", to: "2026-10-06", excluding: [])
        #expect(results.recipes.map(\.name) == ["Salad"])
    }

    @Test("A logged dish counts its own ingredients as eaten")
    func loggedDishExpands() throws {
        let egg = try food("egg", "Egg")
        let milk = try food("milk", "Milk")
        let flour = try food("flour", "Flour")
        let omelette = try recipe("omelette", "Omelette", [egg, milk])
        try recipe("pancakes", "Pancakes", [egg, milk, flour])

        _ = try eat(omelette, at: "2026-10-03T12:00:00Z")

        let results = try finder.fromRecentLog(from: "2026-10-01", to: "2026-10-06", excluding: [])
        #expect(results.recipes.map(\.name) == ["Omelette", "Pancakes"])
        #expect(results.recipes[1].missing.map(\.name) == ["Flour"])
    }

    // MARK: Browse

    @Test("Browse finds recipes by folded name and marks what the pantry holds")
    func browseByName() throws {
        let egg = try food("egg", "Egg")
        let flour = try food("flour", "Flour")
        try recipe("pancakes", "Pancakes", [egg, flour])
        try recipe("omelette", "Omelette", [egg])
        try pantry.add(egg, nameText: "Egg")

        let results = try finder.browse("PAN", excluding: [])
        #expect(results.recipes.map(\.name) == ["Pancakes"])
        #expect(results.recipes[0].ingredients.map(\.isOnHand) == [true, false])

        // Empty text is every recipe, in name order.
        #expect(try finder.browse("", excluding: []).recipes.map(\.name) == ["Omelette", "Pancakes"])
    }

    @Test("A dish with no components is a food, not a recipe")
    func dishWithoutRecipe() throws {
        try dishes.create(localID: "label-bar", nameText: "Protein bar")
        try recipe("omelette", "Omelette", [try food("egg", "Egg")])
        #expect(try finder.browse("", excluding: []).recipes.map(\.name) == ["Omelette"])
    }

    // MARK: Allergens

    @Test("A recipe whose ingredient names an allergen is withheld, and the screen is told")
    func allergenWithheld() throws {
        let chicken = try food("chicken", "Chicken breast")
        let peanutButter = try food("pb", "Peanut butter")
        let rice = try food("rice", "Rice")
        try recipe("satay", "Chicken satay", [chicken, peanutButter])
        try recipe("plain", "Chicken and rice", [chicken, rice])
        try pantry.add(chicken, nameText: "Chicken breast")

        let results = try finder.fromPantry(excluding: [.peanuts])
        #expect(results.recipes.map(\.name) == ["Chicken and rice"])
        #expect(results.recipes[0].verdict.status == .noDeclaration)
        #expect(results.withheld.map(\.name) == ["Chicken satay"])
        #expect(results.withheld[0].verdict.declared == [.peanuts])
        #expect(results.effect.removed == 1)
        #expect(results.note?.contains("Peanuts") == true)
        #expect(results.disclaimer != nil)
    }

    @Test("An allergen inside a nested dish is caught")
    func nestedAllergen() throws {
        let noodles = try food("noodles", "Rice noodles")
        let sauce = try recipe("sauce", "House sauce", [try food("pb", "Peanut butter")])
        try recipe("padthai", "Pad thai", [noodles, sauce])
        try pantry.add(noodles, nameText: "Rice noodles")

        let results = try finder.fromPantry(excluding: [.peanuts])
        #expect(results.recipes.isEmpty)
        #expect(results.withheld.map(\.name) == ["Pad thai"])
    }

    @Test("With no allergens recorded nothing is withheld and nothing is said")
    func noAllergens() throws {
        let chicken = try food("chicken", "Chicken breast")
        try recipe("satay", "Chicken satay", [chicken, try food("pb", "Peanut butter")])
        try pantry.add(chicken, nameText: "Chicken breast")

        let results = try finder.fromPantry(excluding: [])
        #expect(results.recipes.map(\.name) == ["Chicken satay"])
        #expect(results.recipes[0].verdict.status == .notApplicable)
        #expect(results.note == nil)
    }

    // MARK: Logging

    @Test("Logging a recipe is a food-log entry for the dish, valued by the recipe reduction")
    func loggingARecipe() throws {
        let omelette = try recipe("omelette", "Omelette",
                                  [try food("egg", "Egg", protein: 12), try food("milk", "Milk", protein: 4)])
        let id = try eat(omelette, at: "2026-10-03T12:00:00Z")

        let entry = try #require(try log.entry(id: id))
        #expect(entry.foodRef == omelette)
        // 100 g egg + 100 g milk → 16 g protein over 200 g → 8 g per 100 g.
        let protein = try NutritionCatalog(db: db).values(for: omelette, basis: .per100g)
            .first { $0.nutrientID == "protein" }
        #expect(protein?.amount == 8)
    }
}
