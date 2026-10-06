import Foundation
import Testing
@testable import AlmanacCore

/// One serving: the amount a chosen recipe or saved meal pre-fills (owner,
/// 2026-10-06), and the serving count behind it (Migration 052).
@Suite("Dish servings")
struct DishServingTests {
    let db = try! TestDatabase()
    var editor: NutritionDishEditor { NutritionDishEditor(db: db) }

    func recipe(_ id: String, grams: [Double], yield: Double? = nil) throws -> SourceIdentifier {
        let parts = try grams.enumerated().map { index, g in
            DishComponent(try editor.create(localID: "\(id)-part-\(index)", nameText: "Part \(index)"), grams: g)
        }
        let ref = try editor.create(localID: id, nameText: "Recipe \(id)", yieldGrams: yield)
        try editor.setRecipe(parts, for: ref)
        return ref
    }

    @Test("With no count set, the whole dish is one serving")
    func noCountIsTheWholeDish() throws {
        let stew = try recipe("stew", grams: [200, 100])
        #expect(try editor.dish(stew)?.servingCount == nil)
        #expect(try editor.oneServingGrams(of: stew) == 300)
    }

    @Test("A count divides the finished weight — the yield when one is stated")
    func countDividesTheFinishedWeight() throws {
        let stew = try recipe("stew", grams: [200, 100])
        var edit = DishEdit()
        edit.servingCount = .set(3)
        #expect(try editor.update(stew, edit))
        #expect(try editor.dish(stew)?.servingCount == 3)
        #expect(try editor.oneServingGrams(of: stew) == 100)

        // Cooked down to 240 g: four servings of 60 g, not of 75.
        var cooked = DishEdit()
        cooked.yieldGrams = .set(240)
        cooked.servingCount = .set(4)
        #expect(try editor.update(stew, cooked))
        #expect(try editor.oneServingGrams(of: stew) == 60)

        // Clearing the count goes back to the whole dish.
        var cleared = DishEdit()
        cleared.servingCount = .clear
        #expect(try editor.update(stew, cleared))
        #expect(try editor.oneServingGrams(of: stew) == 240)
    }

    @Test("A food with no recipe and no yield has no serving weight, not zero")
    func labelFoodHasNone() throws {
        let label = try editor.create(localID: "bar", nameText: "Protein bar")
        #expect(try editor.oneServingGrams(of: label) == nil)
    }

    @Test("A serving count must be at least one")
    func countMustBePositive() throws {
        let stew = try recipe("stew", grams: [200])
        var edit = DishEdit()
        edit.servingCount = .set(0)
        #expect(throws: NutritionError.self) { try editor.update(stew, edit) }
        // And the column refuses it too, should anything write past the editor.
        #expect(throws: (any Error).self) {
            try db.run("UPDATE nutrition_dish SET serving_count = 0 WHERE food_ref = ?;", [.text(stew.description)])
        }
    }

    @Test("Kitchen's match carries the same one-serving weight the editor computes")
    func kitchenAgrees() throws {
        let stew = try recipe("stew", grams: [200, 100], yield: 280)
        var edit = DishEdit()
        edit.servingCount = .set(2)
        try editor.update(stew, edit)

        let match = try #require(try RecipeFinder(db: db).browse("Recipe stew", excluding: []).recipes.first)
        #expect(match.recipe == stew)
        #expect(match.servingCount == 2)
        #expect(match.oneServingGrams == 140)
        // Hoisted: Swift 6.0.3's `#expect` rejects a `try` on the right of `==`.
        let fromEditor = try editor.oneServingGrams(of: stew)
        #expect(match.oneServingGrams == fromEditor)
    }
}
