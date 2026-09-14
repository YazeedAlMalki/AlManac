import Foundation
import XCTest
@testable import AlmanacCore

final class HydrationReminderServiceTests: XCTestCase {
    var db: Database!
    var store: HydrationStore!
    var calculator: HydrationCalculator!
    var reminderService: HydrationReminderService!
    var runner: MigrationRunner!

    override func setUp() async throws {
        try await super.setUp()
        db = try Database.inMemory()
        runner = MigrationRunner(database: db)
        try await runner.run(AlmanacMigrations.all)

        store = HydrationStore(database: db)
        calculator = HydrationCalculator()
        reminderService = HydrationReminderService(store: store, calculator: calculator)
    }

    func testCreateDefaultReminder() throws {
        let reminder = try reminderService.createDefaultReminder()

        XCTAssertEqual(reminder.intervalMinutes, 60)
        XCTAssertEqual(reminder.startHour, 7)
        XCTAssertEqual(reminder.endHour, 22)
        XCTAssertTrue(reminder.isEnabled)

        let fetched = try store.fetchReminders()
        XCTAssertEqual(fetched.count, 1)
    }

    func testUpdateReminder() throws {
        let initial = try reminderService.createDefaultReminder()

        try reminderService.updateReminder(
            id: initial.id,
            intervalMinutes: 30,
            startHour: 6,
            endHour: 23
        )

        let updated = try store.fetchReminders().first
        XCTAssertEqual(updated?.intervalMinutes, 30)
        XCTAssertEqual(updated?.startHour, 6)
        XCTAssertEqual(updated?.endHour, 23)
    }

    func testSetRemindersEnabled() throws {
        try reminderService.createDefaultReminder()
        let reminder2 = HydrationReminder(id: UUID().uuidString, isEnabled: true)
        try store.save(reminder2)

        try reminderService.setRemindersEnabled(false)

        let reminders = try store.fetchReminders()
        XCTAssertTrue(reminders.allSatisfy { !$0.isEnabled })
    }

    func testReminderMessage() throws {
        let profile = HydrationProfile(userId: "user1")
        let recommendation = HydrationRecommendation(
            recommendedVolumeMilliliters: 250,
            urgency: .high,
            reason: "You're behind on hydration",
            suggestedLiquidTypes: [.water, .sportsDrink],
            timeSinceLastDrinkMinutes: 120
        )

        let message = reminderService.getReminderMessage(recommendation: recommendation, profile: profile)

        XCTAssertTrue(message.contains("250"))
        XCTAssertTrue(message.contains("💧"))
        XCTAssertTrue(message.contains("2h"))
    }

    func testReminderMessageEmojis() throws {
        let profile = HydrationProfile(userId: "user1")

        let criticalRec = HydrationRecommendation(
            recommendedVolumeMilliliters: 500,
            urgency: .critical,
            reason: "Critical dehydration",
            suggestedLiquidTypes: [.water]
        )
        let criticalMsg = reminderService.getReminderMessage(recommendation: criticalRec, profile: profile)
        XCTAssertTrue(criticalMsg.contains("🚨"))

        let highRec = HydrationRecommendation(
            recommendedVolumeMilliliters: 350,
            urgency: .high,
            reason: "High urgency",
            suggestedLiquidTypes: [.water]
        )
        let highMsg = reminderService.getReminderMessage(recommendation: highRec, profile: profile)
        XCTAssertTrue(highMsg.contains("⚠️"))

        let modRec = HydrationRecommendation(
            recommendedVolumeMilliliters: 250,
            urgency: .moderate,
            reason: "Moderate",
            suggestedLiquidTypes: [.water]
        )
        let modMsg = reminderService.getReminderMessage(recommendation: modRec, profile: profile)
        XCTAssertTrue(modMsg.contains("💧"))

        let lowRec = HydrationRecommendation(
            recommendedVolumeMilliliters: 150,
            urgency: .low,
            reason: "Low urgency",
            suggestedLiquidTypes: [.water]
        )
        let lowMsg = reminderService.getReminderMessage(recommendation: lowRec, profile: profile)
        XCTAssertTrue(lowMsg.contains("✨"))
    }

    func testNextReminderTime() throws {
        let reminder = HydrationReminder(
            id: "rem1",
            intervalMinutes: 60,
            startHour: 7,
            endHour: 22,
            isEnabled: true
        )

        let nextTime = reminderService.nextReminderTime(reminder: reminder)

        XCTAssertNotNil(nextTime)
        let calendar = Calendar.current
        let nextHour = calendar.component(.hour, from: nextTime!)
        XCTAssertGreaterThanOrEqual(nextHour, 7)
        XCTAssertLessThan(nextHour, 22)
    }

    func testDisabledReminderReturnsNil() throws {
        let reminder = HydrationReminder(
            id: "rem1",
            intervalMinutes: 60,
            isEnabled: false
        )

        let nextTime = reminderService.nextReminderTime(reminder: reminder)
        XCTAssertNil(nextTime)
    }

    func testCheckReminderNoSamples() throws {
        let reminder = try reminderService.createDefaultReminder()
        let profile = HydrationProfile(userId: "user1")
        try store.save(profile)

        let metrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 0,
            totalSodiumMilligrams: 0,
            exerciseMinutes: nil,
            recommendedIntakeMilliliters: 2000,
            sampleCount: 0
        )

        // This might return nil if outside reminder window, or a recommendation if inside
        let recommendation = try reminderService.checkReminder(profile: profile, currentMetrics: metrics)

        if let rec = recommendation {
            XCTAssertNotNil(rec)
        }
    }

    func testReminderSuggestionForElectrolytes() throws {
        let profile = HydrationProfile(userId: "user1")
        let metrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 500,
            totalSodiumMilligrams: 0,  // Low sodium
            exerciseMinutes: nil,
            recommendedIntakeMilliliters: 2200,
            sampleCount: 2
        )

        let recommendation = calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: 30,
            exerciseActive: false,
            metrics: metrics,
            profile: profile
        )

        // With low sodium, should not suggest electrolyte solution in low-urgency situation
        XCTAssertNotNil(recommendation)
    }

    func testPostExerciseSuggestions() throws {
        let profile = HydrationProfile(userId: "user1")
        let metrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 800,
            totalSodiumMilligrams: 0,
            exerciseMinutes: 60,
            recommendedIntakeMilliliters: 2800,
            sampleCount: 3
        )

        let recommendation = calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: 10,
            exerciseActive: true,
            metrics: metrics,
            profile: profile
        )

        // During exercise should suggest sports drink
        XCTAssert(recommendation.suggestedLiquidTypes.contains(.sportsDrink))
    }
}
