import Foundation
import Testing
@testable import AlmanacCore

/// Pantry suggestions: offered from the log, approved or dismissed by the
/// person, never added on their own (owner, 2026-10-06).
@Suite("Pantry suggestions")
struct PantrySuggestionTests {
    let db = try! TestDatabase()
    let zone = TimeZone(identifier: "Asia/Riyadh")!
    var time: TimeModel { TimeModel(timeZone: zone, boundary: .almanac) }
    let today = LogicalDay("2026-10-06")
    var suggestions: PantrySuggestions { PantrySuggestions(db: db) }

    func food(_ id: String, _ name: String) throws -> SourceIdentifier {
        try NutritionDishEditor(db: db).create(localID: id, nameText: name)
    }

    /// Logs `ref` at noon on the logical day `daysBack` before today.
    func log(_ ref: SourceIdentifier, daysBack: Int, name: String = "x") throws {
        var day = today
        for _ in 0..<daysBack { day = time.day(before: day)! }
        let noon = time.start(of: day)!.addingTimeInterval(8 * 3600)
        try NutritionLogStore(db: db).record(NutritionLogDraft(
            foodRef: ref, grams: 50,
            eatenAt: PartialDateTime(instant: noon, zone: ZoneContext(zone)),
            foodNameText: name, quantityText: nil, mealType: nil))
    }

    func current() throws -> [PantrySuggestion] {
        try suggestions.suggestions(today: today, timeModel: time)
    }

    @Test("Three distinct days in the last fourteen is offered; three entries on one day is not")
    func daysNotEntries() throws {
        let eggs = try food("eggs", "Eggs")
        let oats = try food("oats", "Oats")
        for back in [0, 5, 13] { try log(eggs, daysBack: back) }
        for _ in 0..<3 { try log(oats, daysBack: 1) }

        let offered = try current()
        #expect(offered.map(\.ref) == [eggs])
        #expect(offered.first?.daysLogged == 3)
        #expect(offered.first?.name == "Eggs")
    }

    @Test("A day outside the window does not count")
    func windowIsFourteenDays() throws {
        let eggs = try food("eggs", "Eggs")
        for back in [0, 5, 14] { try log(eggs, daysBack: back) }
        #expect(try current().isEmpty, "14 days back is the fifteenth day, outside the window")
    }

    @Test("Nothing is added on its own; accepting adds it and it is not offered again")
    func acceptIsTheOnlyWayIn() throws {
        let eggs = try food("eggs", "Eggs")
        for back in [0, 1, 2] { try log(eggs, daysBack: back) }

        let offered = try #require(try current().first)
        #expect(try KitchenPantry(db: db).items().isEmpty, "a suggestion added itself to the pantry")
        try suggestions.accept(offered)
        #expect(try KitchenPantry(db: db).refs() == [eggs])
        #expect(try current().isEmpty, "a food already in the pantry is still offered")
    }

    @Test("A dismissal is stored, so the same food is not offered again")
    func dismissalIsStored() throws {
        let eggs = try food("eggs", "Eggs")
        for back in [0, 1, 2] { try log(eggs, daysBack: back) }
        try suggestions.dismiss(eggs)

        // A fresh instance reads the stored dismissal, not anything in memory.
        #expect(try PantrySuggestions(db: db).suggestions(today: today, timeModel: time).isEmpty)
        #expect(try suggestions.dismissed() == [eggs])
        try suggestions.dismiss(eggs) // twice is still once
        #expect(try KitchenPantry(db: db).items().isEmpty, "dismissing added something")
    }

    @Test("A recipe logged often is not offered — it is made from a pantry, not kept in one")
    func recipesAreNotOffered() throws {
        let rice = try food("rice", "Rice")
        let bowl = try food("bowl", "Rice bowl")
        try NutritionDishEditor(db: db).setRecipe([DishComponent(rice, grams: 200)], for: bowl)
        for back in [0, 1, 2] { try log(bowl, daysBack: back) }
        #expect(try current().isEmpty)
    }

    @Test("Most-logged first")
    func ordering() throws {
        let eggs = try food("eggs", "Eggs")
        let milk = try food("milk", "Milk")
        for back in [0, 1, 2] { try log(eggs, daysBack: back) }
        for back in [0, 1, 2, 3] { try log(milk, daysBack: back) }
        #expect(try current().map(\.ref) == [milk, eggs])
    }
}
