import Foundation
import XCTest
@testable import AlmanacCore

final class HydrationLoggingServiceTests: XCTestCase {
    var db: Database!
    var hydrationStore: HydrationStore!
    var calorieIntegration: CalorieIntegration!
    var settingsStore: HydrationSettingsStore!
    var loggingService: HydrationLoggingService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)

        hydrationStore = HydrationStore(database: db)
        calorieIntegration = CalorieIntegration(database: db)
        settingsStore = HydrationSettingsStore(database: db)
        loggingService = HydrationLoggingService(
            hydrationStore: hydrationStore,
            calorieIntegration: calorieIntegration,
            settingsStore: settingsStore
        )
    }

    func testLogDrinkWithCalorieTrackingOff() async throws {
        // Default settings: calorie tracking OFF.
        let drink = CatalogDrinks.byId("catalog_pepsi")!

        let result = try await loggingService.logDrink(drink: drink, userId: "user1")

        XCTAssertNil(result.calorieEntryId)
        XCTAssertNil(result.calorieAmount)

        let today = Calendar.current.startOfDay(for: Date())
        let samples = try hydrationStore.fetchSamples(from: today, to: Date())
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.volumeMilliliters, drink.volumeMilliliters)
    }

    func testLogDrinkWithCalorieTrackingOn() async throws {
        try settingsStore.updateSetting(userId: "user2", calorieTrackingEnabled: true)
        let drink = CatalogDrinks.byId("catalog_gatorade")!

        let result = try await loggingService.logDrink(drink: drink, userId: "user2")

        XCTAssertNotNil(result.calorieEntryId)
        XCTAssertEqual(result.calorieAmount, drink.caloriesKcal)

        let today = Calendar.current.startOfDay(for: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.caloriesKcal, drink.caloriesKcal)
    }

    func testCustomVolumeScalesCalories() async throws {
        try settingsStore.updateSetting(userId: "user3", calorieTrackingEnabled: true)
        let drink = CatalogDrinks.byId("catalog_coke")!  // 355ml, 140 cal

        // Log half the standard serving.
        let result = try await loggingService.logDrink(
            drink: drink,
            customVolume: drink.volumeMilliliters / 2,
            userId: "user3"
        )

        let today = Calendar.current.startOfDay(for: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())
        let logged = entries.first { $0.id == result.calorieEntryId }

        XCTAssertNotNil(logged)
        XCTAssertEqual(logged!.caloriesKcal, drink.caloriesKcal / 2, accuracy: 0.01)
    }

    func testDoubleTrackWarningFiresWhenEnabled() async throws {
        try settingsStore.updateSetting(
            userId: "user4",
            calorieTrackingEnabled: true,
            doubleTrackWarningEnabled: true
        )
        let drink = CatalogDrinks.byId("catalog_pepsi")!

        _ = try await loggingService.logDrink(drink: drink, userId: "user4")
        let second = try await loggingService.logDrink(drink: drink, userId: "user4")

        XCTAssertTrue(second.warnings.contains { $0.type == .possibleDoubleTrack })
    }

    func testDoubleTrackWarningSilencedWhenDisabled() async throws {
        try settingsStore.updateSetting(
            userId: "user5",
            calorieTrackingEnabled: true,
            doubleTrackWarningEnabled: false
        )
        let drink = CatalogDrinks.byId("catalog_pepsi")!

        _ = try await loggingService.logDrink(drink: drink, userId: "user5")
        let second = try await loggingService.logDrink(drink: drink, userId: "user5")

        XCTAssertFalse(second.warnings.contains { $0.type == .possibleDoubleTrack })
    }

    func testDifferentDrinksDoNotTriggerDoubleTrackWarning() async throws {
        try settingsStore.updateSetting(userId: "user6", calorieTrackingEnabled: true)
        let pepsi = CatalogDrinks.byId("catalog_pepsi")!
        let coffee = CatalogDrinks.byId("catalog_coffee_black")!

        _ = try await loggingService.logDrink(drink: pepsi, userId: "user6")
        let second = try await loggingService.logDrink(drink: coffee, userId: "user6")

        XCTAssertFalse(second.warnings.contains { $0.type == .possibleDoubleTrack })
    }

    func testHighSugarWarning() async throws {
        let monster = CatalogDrinks.byId("catalog_monster")!  // 54g sugar

        let result = try await loggingService.logDrink(drink: monster, userId: "user7")

        XCTAssertTrue(result.warnings.contains { $0.type == .highSugar })
    }

    func testHighSodiumWarning() async throws {
        let pedialyte = CatalogDrinks.byId("catalog_pedialyte")!  // 750mg sodium

        let result = try await loggingService.logDrink(drink: pedialyte, userId: "user8")

        XCTAssertTrue(result.warnings.contains { $0.type == .highSodium })
    }

    func testWaterHasNoWarnings() async throws {
        let water = CatalogDrinks.byId("catalog_water")!

        let result = try await loggingService.logDrink(drink: water, userId: "user9")

        XCTAssertFalse(result.hasWarnings)
    }

    func testCustomDrinkPersistsAndReloads() async throws {
        _ = try await loggingService.logCustomDrink(
            name: "Homemade Electrolyte Mix",
            liquidType: .other,
            volume: 500,
            calories: 80,
            sodium: 400,
            sugar: 20,
            userId: "user10"
        )

        let customDrinks = try loggingService.getCustomDrinks(for: "user10")
        XCTAssertEqual(customDrinks.count, 1)
        XCTAssertEqual(customDrinks.first?.name, "Homemade Electrolyte Mix")
        XCTAssertEqual(customDrinks.first?.isCustom, true)
    }

    func testCustomDrinksAreScopedPerUser() async throws {
        _ = try await loggingService.logCustomDrink(
            name: "User A's Drink", liquidType: .other, volume: 300,
            calories: 50, sodium: 100, sugar: nil, userId: "userA"
        )
        _ = try await loggingService.logCustomDrink(
            name: "User B's Drink", liquidType: .other, volume: 300,
            calories: 50, sodium: 100, sugar: nil, userId: "userB"
        )

        let aDrinks = try loggingService.getCustomDrinks(for: "userA")
        let bDrinks = try loggingService.getCustomDrinks(for: "userB")

        XCTAssertEqual(aDrinks.count, 1)
        XCTAssertEqual(bDrinks.count, 1)
        XCTAssertEqual(aDrinks.first?.name, "User A's Drink")
        XCTAssertEqual(bDrinks.first?.name, "User B's Drink")
    }

    func testDeleteLoggedDrinkRemovesCalorieEntryToo() async throws {
        try settingsStore.updateSetting(userId: "user11", calorieTrackingEnabled: true)
        let drink = CatalogDrinks.byId("catalog_pepsi")!

        let result = try await loggingService.logDrink(drink: drink, userId: "user11")
        try loggingService.deleteLoggedDrink(result.hydrationSampleId)

        let today = Calendar.current.startOfDay(for: Date())
        let samples = try hydrationStore.fetchSamples(from: today, to: Date())
        let entries = try calorieIntegration.fetchCalories(from: today, to: Date())

        XCTAssertTrue(samples.isEmpty)
        XCTAssertTrue(entries.isEmpty)
    }

    func testUndoLastDrink() async throws {
        let water = CatalogDrinks.byId("catalog_water")!
        let result = try await loggingService.logDrink(drink: water, userId: "user12")

        let undoneId = try loggingService.undoLastDrink()

        XCTAssertEqual(undoneId, result.hydrationSampleId)
        let today = Calendar.current.startOfDay(for: Date())
        let samples = try hydrationStore.fetchSamples(from: today, to: Date())
        XCTAssertTrue(samples.isEmpty)
    }

    func testTodaySummaryReflectsCalorieToggle() async throws {
        try settingsStore.updateSetting(userId: "user13", calorieTrackingEnabled: false)
        let gatorade = CatalogDrinks.byId("catalog_gatorade")!
        _ = try await loggingService.logDrink(drink: gatorade, userId: "user13")

        let summaryOff = try await loggingService.getTodaySummary(userId: "user13")
        XCTAssertEqual(summaryOff.totalCaloriesKcal, 0)
        XCTAssertFalse(summaryOff.isCalorieTrackingEnabled)
        XCTAssertEqual(summaryOff.drinkCount, 1)
        XCTAssertEqual(summaryOff.totalVolumeMl, gatorade.volumeMilliliters)

        try settingsStore.setCalorieTracking(for: "user13", enabled: true)
        _ = try await loggingService.logDrink(drink: gatorade, userId: "user13")

        let summaryOn = try await loggingService.getTodaySummary(userId: "user13")
        XCTAssertEqual(summaryOn.totalCaloriesKcal, gatorade.caloriesKcal)
        XCTAssertTrue(summaryOn.isCalorieTrackingEnabled)
        XCTAssertEqual(summaryOn.drinkCount, 2)
    }
}
