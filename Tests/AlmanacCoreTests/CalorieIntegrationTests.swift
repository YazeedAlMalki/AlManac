import Foundation
import XCTest
@testable import AlmanacCore

final class CalorieIntegrationTests: XCTestCase {
    var db: Database!
    var calorieIntegration: CalorieIntegration!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        calorieIntegration = CalorieIntegration(database: db)
    }

    func testLogCalories() throws {
        let drink = Drink(
            name: "Pepsi",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 150,
            sodiumMilligrams: 30,
            sugarGrams: 41
        )

        let entryId = try calorieIntegration.logCalories(
            hydrationSampleId: "sample1",
            drink: drink,
            calorieAmount: 150
        )

        XCTAssertFalse(entryId.isEmpty)
    }

    func testFetchCalories() throws {
        let drink = CatalogDrinks.byId("catalog_coke")!

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample2",
            drink: drink,
            calorieAmount: 140
        )

        let today = Calendar.current.startOfDay(for: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())

        XCTAssertGreaterThan(entries.count, 0)
        XCTAssertEqual(entries.first?.caloriesKcal, 140)
    }

    func testGetDailyTotal() throws {
        let drink1 = CatalogDrinks.byId("catalog_pepsi")!
        let drink2 = CatalogDrinks.byId("catalog_gatorade")!

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample3",
            drink: drink1,
            calorieAmount: drink1.caloriesKcal
        )

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample4",
            drink: drink2,
            calorieAmount: drink2.caloriesKcal
        )

        let today = Calendar.current.startOfDay(for: Date())
        let total = try calorieIntegration.getDailyTotal(for: today)

        XCTAssertGreaterThan(total.totalCaloriesKcal, 0)
        XCTAssertEqual(total.entryCount, 2)
    }

    func testDetectDoubleTracking() throws {
        let drink = CatalogDrinks.byId("catalog_pepsi")!
        let now = Date()

        // Log same drink twice within 5 minutes
        try calorieIntegration.logCalories(
            hydrationSampleId: "sample5",
            drink: drink,
            calorieAmount: drink.caloriesKcal
        )

        // Wait a moment
        Thread.sleep(forTimeInterval: 0.1)

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample6",
            drink: drink,
            calorieAmount: drink.caloriesKcal
        )

        let suspicions = try calorieIntegration.detectDoubleTracking(
            userId: "user1",
            timeWindowMinutes: 5
        )

        // Should detect potential double-tracking
        XCTAssertGreaterThan(suspicions.count, 0)
    }

    func testDoubleTrackingConfidence() throws {
        let drink = CatalogDrinks.byId("catalog_coke")!

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample7",
            drink: drink,
            calorieAmount: drink.caloriesKcal
        )

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample8",
            drink: drink,
            calorieAmount: drink.caloriesKcal
        )

        let suspicions = try calorieIntegration.detectDoubleTracking(userId: "user1")

        if !suspicions.isEmpty {
            XCTAssertGreaterThan(suspicions.first!.confidence, 0)
            XCTAssertLessThanOrEqual(suspicions.first!.confidence, 1.0)
        }
    }

    func testDeleteEntry() throws {
        let drink = CatalogDrinks.byId("catalog_sprite")!

        let entryId = try calorieIntegration.logCalories(
            hydrationSampleId: "sample9",
            drink: drink,
            calorieAmount: drink.caloriesKcal
        )

        try calorieIntegration.deleteEntry(entryId)

        let today = Calendar.current.startOfDay(for: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())

        XCTAssertFalse(entries.contains { $0.id == entryId })
    }

    func testMarkAsReviewed() throws {
        let drink = CatalogDrinks.byId("catalog_fanta")!

        let entryId = try calorieIntegration.logCalories(
            hydrationSampleId: "sample10",
            drink: drink,
            calorieAmount: drink.caloriesKcal
        )

        try calorieIntegration.markAsReviewed(entryId)

        let today = Calendar.current.startOfDay(for: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())

        let reviewed = entries.first { $0.id == entryId }
        XCTAssertNotNil(reviewed)
        XCTAssertFalse(reviewed!.hasDoubleTrackWarning)
    }

    func testSugarTracking() throws {
        let highSugar = CatalogDrinks.byId("catalog_monster")!

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample11",
            drink: highSugar,
            calorieAmount: highSugar.caloriesKcal
        )

        let today = Calendar.current.startOfDay(for: Date())
        let total = try calorieIntegration.getDailyTotal(for: today)

        XCTAssertGreaterThan(total.totalSugarGrams, 0)
    }

    func testZeroCalorieDrink() throws {
        let dietCoke = CatalogDrinks.byId("catalog_coke_diet")!

        try calorieIntegration.logCalories(
            hydrationSampleId: "sample12",
            drink: dietCoke,
            calorieAmount: dietCoke.caloriesKcal
        )

        let today = Calendar.current.startOfDay(for: Date())
        let total = try calorieIntegration.getDailyTotal(for: today)

        XCTAssertEqual(total.totalCaloriesKcal, 0)
    }

    func testCalorieEntryStructure() throws {
        let drink = CatalogDrinks.byId("catalog_water")!

        let entryId = try calorieIntegration.logCalories(
            hydrationSampleId: "sample13",
            drink: drink,
            calorieAmount: 0
        )

        let today = Calendar.current.startOfDay(for: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())

        let entry = entries.first { $0.id == entryId }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry!.drinkName, "Water")
        XCTAssertEqual(entry!.caloriesKcal, 0)
    }
}
