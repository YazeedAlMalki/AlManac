import Foundation
import XCTest
@testable import AlmanacCore

final class HydrationSettingsTests: XCTestCase {
    var db: Database!
    var settingsStore: HydrationSettingsStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        settingsStore = HydrationSettingsStore(database: db)
    }

    func testDefaultSettingsCreation() throws {
        let settings = HydrationSettings(userId: "user1")

        XCTAssertEqual(settings.userId, "user1")
        XCTAssertFalse(settings.isCalorieTrackingEnabled)  // Default OFF
        XCTAssertTrue(settings.isDoubleTrackWarningEnabled)
        XCTAssertTrue(settings.showHydrationReminders)
    }

    func testSaveAndFetchSettings() throws {
        let original = HydrationSettings(
            userId: "user1",
            isCalorieTrackingEnabled: true,
            preferredReminderInterval: 30
        )
        try settingsStore.save(original)

        let fetched = try settingsStore.fetch(for: "user1")
        XCTAssertNotNil(fetched)
        XCTAssertTrue(fetched!.isCalorieTrackingEnabled)
        XCTAssertEqual(fetched!.preferredReminderInterval, 30)
    }

    func testGetOrCreateDefaults() throws {
        let settings1 = try settingsStore.getOrCreate(for: "user2")
        let settings2 = try settingsStore.getOrCreate(for: "user2")

        XCTAssertEqual(settings1.userId, settings2.userId)
        XCTAssertEqual(settings1.isCalorieTrackingEnabled, settings2.isCalorieTrackingEnabled)
    }

    func testUpdateCalorieTracking() throws {
        try settingsStore.getOrCreate(for: "user3")

        let updated = try settingsStore.setCalorieTracking(for: "user3", enabled: true)
        XCTAssertTrue(updated.isCalorieTrackingEnabled)

        let disabled = try settingsStore.setCalorieTracking(for: "user3", enabled: false)
        XCTAssertFalse(disabled.isCalorieTrackingEnabled)
    }

    func testUpdateDoubleTrackWarning() throws {
        try settingsStore.getOrCreate(for: "user4")

        let disabled = try settingsStore.setDoubleTrackWarning(for: "user4", enabled: false)
        XCTAssertFalse(disabled.isDoubleTrackWarningEnabled)
    }

    func testUpdateMultipleSettings() throws {
        try settingsStore.updateSetting(
            userId: "user5",
            calorieTrackingEnabled: true,
            reminderInterval: 45,
            trackSugar: false
        )

        let settings = try settingsStore.getOrCreate(for: "user5")
        XCTAssertTrue(settings.isCalorieTrackingEnabled)
        XCTAssertEqual(settings.preferredReminderInterval, 45)
        XCTAssertFalse(settings.trackSugar)
    }

    func testMinimalPreset() throws {
        let settings = HydrationSettingsPreset.minimal.toSettings(userId: "user6")

        XCTAssertFalse(settings.isCalorieTrackingEnabled)
        XCTAssertFalse(settings.showHydrationReminders)
        XCTAssertFalse(settings.trackSodium)
        XCTAssertFalse(settings.trackSugar)
    }

    func testComprehensivePreset() throws {
        let settings = HydrationSettingsPreset.comprehensive.toSettings(userId: "user7")

        XCTAssertTrue(settings.isCalorieTrackingEnabled)
        XCTAssertTrue(settings.showHydrationReminders)
        XCTAssertTrue(settings.isDoubleTrackWarningEnabled)
        XCTAssertTrue(settings.trackSodium)
        XCTAssertTrue(settings.trackSugar)
    }

    func testAthletePreset() throws {
        let settings = HydrationSettingsPreset.athlete.toSettings(userId: "user8")

        XCTAssertTrue(settings.isCalorieTrackingEnabled)
        XCTAssertTrue(settings.autoLogDrinksFromHealth)
        XCTAssertEqual(settings.preferredReminderInterval, 30)  // More frequent for athletes
    }

    func testCalorieCounterPreset() throws {
        let settings = HydrationSettingsPreset.calorieCounter.toSettings(userId: "user9")

        XCTAssertTrue(settings.isCalorieTrackingEnabled)
        XCTAssertTrue(settings.trackSugar)
        XCTAssertEqual(settings.preferredReminderInterval, 120)  // Less frequent
    }

    func testMigrateSettings() throws {
        let original = HydrationSettings(
            userId: "oldUser",
            isCalorieTrackingEnabled: true,
            preferredReminderInterval: 45
        )
        try settingsStore.save(original)

        try settingsStore.migrate(from: "oldUser", to: "newUser")

        let migrated = try settingsStore.fetch(for: "newUser")
        XCTAssertNotNil(migrated)
        XCTAssertTrue(migrated!.isCalorieTrackingEnabled)
        XCTAssertEqual(migrated!.preferredReminderInterval, 45)
    }

    func testDailyGoalSetting() throws {
        try settingsStore.updateSetting(userId: "user10", dailyGoal: 3000)

        let settings = try settingsStore.getOrCreate(for: "user10")
        XCTAssertNotNil(settings.dailyGoalMilliliters)
        XCTAssertEqual(settings.dailyGoalMilliliters, 3000)
    }

    func testSettingsTimestamp() throws {
        let before = Date()
        try settingsStore.updateSetting(userId: "user11")
        let after = Date()

        let settings = try settingsStore.getOrCreate(for: "user11")
        XCTAssertGreaterThanOrEqual(settings.updatedAt, before)
        XCTAssertLessThanOrEqual(settings.updatedAt, after)
    }
}
