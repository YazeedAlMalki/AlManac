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
        #expect(try editor.dishes().count == 4)
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
}
