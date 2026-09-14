import Foundation
import XCTest
@testable import AlmanacCore

final class DrinkCatalogTests: XCTestCase {
    func testCatalogHasCommonDrinks() {
        let all = CatalogDrinks.all
        XCTAssertGreaterThan(all.count, 20)

        // Should have major brands
        XCTAssertNotNil(all.first { $0.name == "Pepsi" })
        XCTAssertNotNil(all.first { $0.name == "Coca-Cola" })
        XCTAssertNotNil(all.first { $0.name == "Gatorade (Orange)" })
        XCTAssertNotNil(all.first { $0.name == "Water" })
    }

    func testRegularSodaVsDiet() {
        let regular = CatalogDrinks.byId("catalog_pepsi")
        let diet = CatalogDrinks.byId("catalog_pepsi_diet")

        XCTAssertNotNil(regular)
        XCTAssertNotNil(diet)

        // Regular should have calories, diet should not
        XCTAssertGreaterThan(regular!.caloriesKcal, 0)
        XCTAssertEqual(diet!.caloriesKcal, 0)

        // Both should have similar sodium
        XCTAssertGreaterThan(regular!.sodiumMilligrams, 0)
        XCTAssertGreaterThan(diet!.sodiumMilligrams, 0)
    }

    func testSportsDrinkNutrition() {
        let gatorade = CatalogDrinks.byId("catalog_gatorade")
        XCTAssertNotNil(gatorade)

        // Should have significant sodium for electrolytes
        XCTAssertGreaterThan(gatorade!.sodiumMilligrams, 200)
        // Should have carbs for energy
        XCTAssertGreaterThan(gatorade!.caloriesKcal, 100)
    }

    func testSearchFunctionality() {
        let cokeResults = CatalogDrinks.search(query: "coke")
        XCTAssertGreaterThan(cokeResults.count, 0)
        XCTAssert(cokeResults.allSatisfy { $0.name.lowercased().contains("coke") })

        let gatoradeResults = CatalogDrinks.search(query: "gatorade")
        XCTAssertGreaterThan(gatoradeResults.count, 0)
    }

    func testSearchCaseInsensitive() {
        let lowerResults = CatalogDrinks.search(query: "coffee")
        let upperResults = CatalogDrinks.search(query: "COFFEE")

        XCTAssertEqual(lowerResults.count, upperResults.count)
    }

    func testAllDrinksHaveRequiredFields() {
        let all = CatalogDrinks.all

        for drink in all {
            XCTAssertFalse(drink.name.isEmpty)
            XCTAssertGreaterThanOrEqual(drink.volumeMilliliters, 0)
            XCTAssertGreaterThanOrEqual(drink.caloriesKcal, 0)
            XCTAssertGreaterThanOrEqual(drink.sodiumMilligrams, 0)
        }
    }

    func testWaterHasZeroCalories() {
        let water = CatalogDrinks.byId("catalog_water")
        XCTAssertNotNil(water)
        XCTAssertEqual(water!.caloriesKcal, 0)
        XCTAssertEqual(water!.sodiumMilligrams, 0)
    }

    func testHighSugarDrinks() {
        let pepsi = CatalogDrinks.byId("catalog_pepsi")
        XCTAssertNotNil(pepsi!.sugarGrams)
        XCTAssertGreaterThan(pepsi!.sugarGrams!, 30)
    }

    func testZeroSugarDrinks() {
        let dietCoke = CatalogDrinks.byId("catalog_coke_diet")
        XCTAssertNotNil(dietCoke)
        XCTAssertEqual(dietCoke!.sugarGrams ?? 0, 0)
        XCTAssertEqual(dietCoke!.caloriesKcal, 0)
    }
}
