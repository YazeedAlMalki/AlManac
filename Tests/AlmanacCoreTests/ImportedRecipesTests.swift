import Foundation
import Testing
@testable import AlmanacCore

/// Kitchen's Wikibooks recipes (owner, T04, 2026-10-16): installing the bundle,
/// re-installing a changed one, and how an imported recipe shows up in Kitchen
/// and stays out of Saved meals.
@Suite("Imported recipes")
struct ImportedRecipesTests {
    let db = try! TestDatabase()
    var dishes: NutritionDishEditor { NutritionDishEditor(db: db) }

    init() throws {
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
        for (id, name) in [("flour", "Flour, wheat"), ("egg", "Egg, raw"), ("peanut", "Peanut butter")] {
            try db.run("""
                INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                            food_group_code, food_group_name, source_record)
                VALUES (?, 'usda', ?, 'A', '', '', 'fixture');
                """, [.text("usda:" + id), .text(id)])
            try db.run("""
                INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
                VALUES (?, 'en', ?, 1, ?);
                """, [.text("usda:" + id), .text(name), .text(TextFold.fold(name))])
            try db.run("""
                INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier,
                                             source_value, source_nutrient_id, source_unit, licence_group)
                VALUES (?, 'protein', 'per_100g', 10, 'measured', '10', 'protein', 'g', 'A');
                """, [.text("usda:" + id)])
        }
    }

    func bundle(_ recipes: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["licence": "CC BY-SA 4.0", "recipes": recipes])
    }

    func recipe(_ id: String, _ name: String, servings: Int? = nil,
                _ parts: [(String, Double)]) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "name": name, "title": "Cookbook:" + name, "revision": 100,
            "url": "https://en.wikibooks.org/wiki/Cookbook:" + name.replacingOccurrences(of: " ", with: "_"),
            "components": parts.map { ["ref": $0.0, "grams": $0.1, "line": "\($0.1) g of \($0.0)"] }
        ]
        if let servings { row["servings"] = servings }
        return row
    }

    @Test("Each recipe becomes a dish with its components, its source, and the servings its page states")
    func installWritesDishes() throws {
        let data = try bundle([
            recipe("1", "Pancakes", servings: 4, [("usda:flour", 200), ("usda:egg", 100)]),
            recipe("2", "Egg bread", [("usda:flour", 300), ("usda:egg", 50)])
        ])
        #expect(try WikibooksRecipeBundle.install(data, sha256: "a", into: db) == 2)

        let pancakes = WikibooksRecipeBundle.ref(forPageID: "1")
        #expect(pancakes.description == "almanac:wikibooks-1")
        let components = try dishes.components(of: pancakes)
        #expect(components.map(\.ref.description) == ["usda:flour", "usda:egg"])
        #expect(components.map(\.grams) == [200, 100])
        #expect(components.first?.noteText == "200.0 g of usda:flour")
        #expect(try dishes.dish(pancakes)?.servingCount == 4)
        #expect(try dishes.dish(WikibooksRecipeBundle.ref(forPageID: "2"))?.servingCount == nil)
        // Values are reduced from the components, as for any dish.
        #expect(try NutritionCatalog(db: db).values(for: pancakes, basis: .per100g).isEmpty == false)

        let source = try #require(try WikibooksRecipeBundle.sources(in: db)[pancakes])
        #expect(source.title == "Cookbook:Pancakes")
        #expect(source.url == "https://en.wikibooks.org/wiki/Cookbook:Pancakes")
        #expect(source.licence == "CC BY-SA 4.0")
        #expect(source.statedServings == 4)
    }

    @Test("A changed bundle updates recipes, removes the ones it dropped, and keeps a count the person set")
    func reinstall() throws {
        try WikibooksRecipeBundle.install(try bundle([
            recipe("1", "Pancakes", servings: 4, [("usda:flour", 200), ("usda:egg", 100)]),
            recipe("2", "Egg bread", [("usda:flour", 300), ("usda:egg", 50)])
        ]), sha256: "a", into: db)
        let pancakes = WikibooksRecipeBundle.ref(forPageID: "1")
        let bread = WikibooksRecipeBundle.ref(forPageID: "2")
        try dishes.update(pancakes, .servings(6))

        #expect(try WikibooksRecipeBundle.install(try bundle([
            recipe("1", "Thin pancakes", servings: 8, [("usda:flour", 150), ("usda:egg", 150)]),
            recipe("3", "Omelette", servings: 1, [("usda:egg", 150), ("usda:flour", 10)])
        ]), sha256: "b", into: db) == 2)

        #expect(try dishes.dish(pancakes)?.nameText == "Thin pancakes")
        #expect(try dishes.components(of: pancakes).map(\.grams) == [150, 150])
        #expect(try dishes.dish(pancakes)?.servingCount == 6, "the person's count is theirs")
        #expect(try dishes.dish(bread) == nil)
        #expect(try WikibooksRecipeBundle.sources(in: db)[bread] == nil)
        #expect(try dishes.dish(WikibooksRecipeBundle.ref(forPageID: "3"))?.servingCount == 1)
        #expect(try db.query("SELECT bundle_sha256 FROM kitchen_recipe_import;").first?.string("bundle_sha256") == "b")
    }

    @Test("Kitchen lists an imported recipe with its credit; Saved meals does not list it")
    func kitchenAndSavedMeals() throws {
        try WikibooksRecipeBundle.install(try bundle([
            recipe("1", "Pancakes", servings: 4, [("usda:flour", 200), ("usda:egg", 100)])
        ]), sha256: "a", into: db)
        let own = try dishes.create(localID: "zz-omelette", nameText: "Zesty omelette")
        try dishes.setRecipe([DishComponent(SourceIdentifier(parsing: "usda:egg")!, grams: 120)], for: own)

        let found = try RecipeFinder(db: db).browse("", excluding: [])
        // The person's own dish first, although "Z" sorts after "P".
        #expect(found.recipes.map(\.name) == ["Zesty omelette", "Pancakes"])
        let pancakes = try #require(found.recipes.first { $0.name == "Pancakes" })
        #expect(pancakes.source?.url == "https://en.wikibooks.org/wiki/Cookbook:Pancakes")
        #expect(pancakes.source?.credit.contains("CC BY-SA 4.0") == true)
        #expect(found.recipes.first { $0.name == "Zesty omelette" }?.source == nil)

        let saved = try SavedMeals(db: db).list(excluding: [])
        #expect(saved.meals.map(\.nameText) == ["Zesty omelette"])
    }

    @Test("The Kitchen test seed puts the servings question back, and leaves a stated count alone")
    func seedResetsAnsweredCounts() throws {
        try WikibooksRecipeBundle.install(try bundle([
            recipe("1", "Pancakes", servings: 4, [("usda:flour", 200), ("usda:egg", 100)]),
            recipe("2", "Egg bread", [("usda:flour", 300), ("usda:egg", 50)])
        ]), sha256: "a", into: db)
        let bread = WikibooksRecipeBundle.ref(forPageID: "2")
        try dishes.update(bread, .servings(3))
        try #require(KitchenSeedPlan(spec: "recipes")).apply(into: db)
        #expect(try dishes.dish(bread)?.servingCount == nil)
        #expect(try dishes.dish(WikibooksRecipeBundle.ref(forPageID: "1"))?.servingCount == 4)
    }

    @Test("The allergen check reads an imported recipe's ingredients like any other dish's")
    func allergenCheck() throws {
        try WikibooksRecipeBundle.install(try bundle([
            recipe("1", "Satay", [("usda:peanut", 100), ("usda:flour", 50)])
        ]), sha256: "a", into: db)
        let results = try RecipeFinder(db: db).browse("Satay", excluding: [.peanuts])
        #expect(results.recipes.isEmpty)
        #expect(results.withheld.map(\.name) == ["Satay"])
    }
}

/// The bundle the app ships, installed on the nutrition reference it ships.
@Suite("Imported recipes on the shipped data")
struct ImportedRecipesShippedTests {
    @Test("Every shipped recipe installs, every ingredient is in the reference, and a second run does nothing")
    func shippedBundle() throws {
        let db = try TestDatabase()
        _ = try #require(try NutritionReferenceBundle.installIfNeeded(into: db))
        let shipped = try JSONSerialization.jsonObject(with: Data(contentsOf: WikibooksRecipeBundle.resourceURL)) as? [String: Any]
        let count = (shipped?["recipes"] as? [Any])?.count ?? 0
        #expect(count > 250, "shipped \(count)")

        #expect(try WikibooksRecipeBundle.installIfNeeded(into: db) == count)
        #expect(try WikibooksRecipeBundle.installIfNeeded(into: db) == nil)

        let editor = NutritionDishEditor(db: db)
        let sources = try WikibooksRecipeBundle.sources(in: db)
        #expect(sources.count == count)
        for (ref, source) in sources {
            #expect(source.url.hasPrefix("https://en.wikibooks.org/wiki/Cookbook:"), "\(ref)")
            let reduction = try editor.reduce(try editor.components(of: ref), as: ref)
            #expect(reduction.missingComponents.isEmpty, "\(source.title): \(reduction.missingComponents)")
            #expect(reduction.totalGrams > 0, "\(source.title)")
        }
        try AttributionAudit.assertAttributed(["wikibooks-cookbook"])
    }
}
