import Foundation
import Testing
@testable import AlmanacCore

/// The one allergen check for Almanac's own dishes, as Saved meals and Kitchen
/// both use it (owner, 2026-10-06: "same rule everywhere").
@Suite("Dish allergen check")
struct DishAllergenCheckTests {
    let db = try! TestDatabase()
    var editor: NutritionDishEditor { NutritionDishEditor(db: db) }

    /// A plain food (no components) — a saved meal typed from a label.
    @discardableResult
    func food(_ id: String, _ name: String) throws -> SourceIdentifier {
        try editor.create(localID: id, nameText: name)
    }

    @discardableResult
    func recipe(_ id: String, _ name: String, _ parts: [SourceIdentifier]) throws -> SourceIdentifier {
        let ref = try editor.create(localID: id, nameText: name)
        try editor.setRecipe(parts.map { DishComponent($0, grams: 100) }, for: ref)
        return ref
    }

    @Test("A saved meal naming a recorded allergen is hidden by default — the gap that was open")
    func savedMealNamingAnAllergenIsHidden() throws {
        try food("toast", "Peanut butter toast")
        try food("apple", "Apple")

        let results = try SavedMeals(db: db).list(excluding: [.peanuts])
        #expect(results.meals.map(\.nameText) == ["Apple"])
        #expect(results.hidden.map(\.item.nameText) == ["Peanut butter toast"])
    }

    @Test("A saved meal is hidden when only an ingredient declares, through nested dishes")
    func ingredientDeclares() throws {
        let sauce = try food("sauce", "Satay sauce with peanut")
        let rice = try food("rice", "Rice")
        let bowl = try recipe("bowl", "Rice bowl", [rice])
        let inner = try recipe("inner", "Chicken with sauce", [sauce])
        try recipe("outer", "Weeknight dinner", [bowl, inner])

        let results = try SavedMeals(db: db).list(excluding: [.peanuts])
        let hidden = Set(results.hidden.map(\.item.nameText))
        #expect(hidden == ["Satay sauce with peanut", "Chicken with sauce", "Weeknight dinner"])
        #expect(Set(results.meals.map(\.nameText)) == ["Rice", "Rice bowl"])
    }

    @Test("A hidden meal is reachable, and its warning names the allergen and where it was found")
    func reachableWithWarning() throws {
        let sauce = try food("sauce", "Peanut sauce")
        try recipe("satay", "Satay", [sauce])

        let results = try SavedMeals(db: db).list(excluding: [.peanuts, .milk])
        let satay = try #require(results.hidden.first { $0.item.nameText == "Satay" })
        #expect(satay.judgement.verdict.declared == [.peanuts])
        #expect(satay.judgement.foundIn == ["Peanut sauce"])
        let warning = try #require(satay.judgement.warning)
        #expect(warning.contains(FoodAllergen.peanuts.title), "got \(warning)")
        #expect(warning.contains("Found in: Peanut sauce"))
        #expect(!warning.contains(FoodAllergen.milk.title), "warns about an allergen it did not find")
        #expect(results.disclaimer?.hasPrefix("Checked meal and ingredient names only") == true)
    }

    @Test("Nothing is hidden, and nothing is said, when no allergens are recorded")
    func nothingRecorded() throws {
        try food("toast", "Peanut butter toast")
        let results = try SavedMeals(db: db).list()
        #expect(results.hidden.isEmpty)
        #expect(results.meals.map(\.nameText) == ["Peanut butter toast"])
        #expect(results.disclaimer == nil)
        #expect(try DishAllergenCheck(db: db).judge([SourceIdentifier(namespace: .almanac, localID: "toast")],
                                                    allergens: [])
                .values.allSatisfy { $0.verdict.status == .notApplicable && $0.warning == nil })
    }

    @Test("A failed read of the allergen list is an error, not an unchecked list")
    func failedReadIsAnError() throws {
        try food("toast", "Peanut butter toast")
        try ProfileStore(db: db).addAllergen(.peanuts)
        #expect(try SavedMeals(db: db).list().hidden.count == 1)

        // Make the read fail. `PRAGMA foreign_keys` off first, so the drop is
        // allowed; the point is only that the list read now throws.
        try db.execute("PRAGMA foreign_keys = OFF; DROP TABLE profile_allergen;")
        #expect(throws: (any Error).self) { try SavedMeals(db: db).list() }
    }

    @Test("Kitchen and Saved meals judge the same dish the same way")
    func oneRuleForBoth() throws {
        let sauce = try food("sauce", "Peanut sauce")
        let rice = try food("rice", "Rice")
        let satay = try recipe("satay", "Satay", [rice, sauce])

        let kitchen = try RecipeFinder(db: db).browse("", excluding: [.peanuts])
        let saved = try SavedMeals(db: db).list(excluding: [.peanuts])

        let fromKitchen = try #require(kitchen.withheld.first { $0.recipe == satay })
        let fromSaved = try #require(saved.hidden.first { $0.item.ref == satay })
        #expect(fromKitchen.allergen == fromSaved.judgement)
        #expect(kitchen.disclaimer?.hasPrefix("Checked recipe and ingredient names only") == true)
    }
}
