import Foundation
import Testing
@testable import AlmanacCore

/// The Kitchen UI-test seed: that an ordinary launch asks for nothing, that the
/// grammar is all or nothing, and that applying it lands the same state twice.
@Suite("Kitchen seed plan")
struct KitchenSeedPlanTests {
    let db = try! TestDatabase()

    @Test("An ordinary launch asks for nothing")
    func ordinaryLaunch() {
        #expect(KitchenSeedPlan.fromLaunchArguments([]) == nil)
        #expect(KitchenSeedPlan.fromLaunchArguments(["Almanac", "-AlmanacSeedVitals", "rhr=50@0"]) == nil)
        // The flag with no value after it is not a request either.
        #expect(KitchenSeedPlan.fromLaunchArguments([KitchenSeedPlan.launchArgument]) == nil)
    }

    @Test("The spec is all or nothing")
    func grammar() {
        #expect(KitchenSeedPlan(spec: "recipes")?.allergens == .unchanged)
        #expect(KitchenSeedPlan(spec: "recipes,peanuts")?.allergens == .peanuts)
        #expect(KitchenSeedPlan(spec: "recipes,noallergens")?.allergens == .noPeanuts)
        for bad in ["", "peanuts", "recipes,milk", "recipes,peanuts,noallergens", "recipe"] {
            #expect(KitchenSeedPlan(spec: bad) == nil, "accepted \(bad)")
        }
        #expect(KitchenSeedPlan.fromLaunchArguments([KitchenSeedPlan.launchArgument, "recipes,peanuts"])
                == KitchenSeedPlan(allergens: .peanuts))
    }

    @Test("Applying plants two recipes, empties their pantry rows, and is repeatable")
    func apply() throws {
        let plan = try #require(KitchenSeedPlan(spec: "recipes,peanuts"))
        try KitchenPantry(db: db).add(KitchenSeedPlan.riceRef, nameText: KitchenSeedPlan.riceName)
        try plan.apply(into: db)
        try plan.apply(into: db)

        let editor = NutritionDishEditor(db: db)
        #expect(try editor.dishes().count == 5)
        #expect(try editor.components(of: KitchenSeedPlan.satayRef).map(\.ref)
                == [KitchenSeedPlan.riceRef, KitchenSeedPlan.sauceRef])
        #expect(try KitchenPantry(db: db).items().isEmpty)
        #expect(try ProfileStore(db: db).allergenSet() == [.peanuts])

        // The withheld half of the UI test, at the core: with peanuts recorded
        // the satay is withheld and the rice bowl is not.
        let results = try RecipeFinder(db: db).browse("Kitchen test", excluding: [.peanuts])
        #expect(results.recipes.map(\.recipe) == [KitchenSeedPlan.bowlRef])
        #expect(results.withheld.map(\.recipe) == [KitchenSeedPlan.satayRef])

        try #require(KitchenSeedPlan(spec: "recipes,noallergens")).apply(into: db)
        #expect(try ProfileStore(db: db).allergenSet().isEmpty)
    }

    @Test("The oats are offered for the pantry, on three past days, however often it is applied")
    func pantrySuggestion() throws {
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        let time = TimeModel(timeZone: zone)
        // 09:00 on 7 October in Riyadh: logical day 2026-10-07.
        let now = ISO8601DateFormatter().date(from: "2026-10-07T06:00:00Z")!
        let today = time.logicalDay(now)
        let plan = try #require(KitchenSeedPlan(spec: "recipes"))
        let suggestions = PantrySuggestions(db: db)

        try plan.apply(into: db, now: now, timeModel: time)
        try plan.apply(into: db, now: now, timeModel: time)
        let offered = try suggestions.suggestions(today: today, timeModel: time)
        #expect(offered.map(\.ref) == [KitchenSeedPlan.oatsRef])
        #expect(offered.first?.daysLogged == 3)
        #expect(try NutritionSummary(db: db).loggedFoods(on: today, in: time)?.isEmpty ?? true,
                "the seed logged something today, which every other screen would count")

        // A test that dismissed (or accepted) it can run again.
        try suggestions.dismiss(KitchenSeedPlan.oatsRef)
        #expect(try suggestions.suggestions(today: today, timeModel: time).isEmpty)
        try plan.apply(into: db, now: now, timeModel: time)
        #expect(try suggestions.suggestions(today: today, timeModel: time).map(\.ref) == [KitchenSeedPlan.oatsRef])
        try suggestions.accept(try #require(offered.first))
        try plan.apply(into: db, now: now, timeModel: time)
        #expect(try suggestions.suggestions(today: today, timeModel: time).map(\.ref) == [KitchenSeedPlan.oatsRef])

        // On a later day, the same three rows move rather than three more appearing.
        let later = now.addingTimeInterval(5 * 24 * 3600)
        try plan.apply(into: db, now: later, timeModel: time)
        let moved = try suggestions.suggestions(today: time.logicalDay(later), timeModel: time)
        #expect(moved.first?.daysLogged == 3)
        #expect(try db.query("SELECT COUNT(*) AS n FROM nutrition_log WHERE food_ref = ?;",
                             [.text(KitchenSeedPlan.oatsRef.description)]).first?.int("n") == 3)
    }
}
