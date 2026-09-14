import Foundation
import XCTest
@testable import AlmanacCore

final class HydrationStoreTests: XCTestCase {
    var db: Database!
    var store: HydrationStore!
    var runner: MigrationRunner!

    override func setUp() async throws {
        try await super.setUp()
        db = try Database.inMemory()
        runner = MigrationRunner(database: db)
        try await runner.run(AlmanacMigrations.all)
        store = HydrationStore(database: db)
    }

    func testSaveSample() throws {
        let sample = HydrationSample(
            id: "sample1",
            timestamp: Date(),
            volumeMilliliters: 250,
            liquidType: .water
        )

        try store.save(sample)

        let today = Calendar.current.startOfDay(for: Date())
        let samples = try store.fetchSamples(from: today, to: Date())

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.id, "sample1")
        XCTAssertEqual(samples.first?.volumeMilliliters, 250)
        XCTAssertEqual(samples.first?.liquidType, .water)
    }

    func testSaveMultipleSamples() throws {
        let sample1 = HydrationSample(id: "s1", timestamp: Date(), volumeMilliliters: 250, liquidType: .water)
        let sample2 = HydrationSample(id: "s2", timestamp: Date(), volumeMilliliters: 300, liquidType: .sportsDrink, sodiumMilligrams: 250)
        let sample3 = HydrationSample(id: "s3", timestamp: Date(), volumeMilliliters: 200, liquidType: .coconutWater)

        try store.save(sample1)
        try store.save(sample2)
        try store.save(sample3)

        let today = Calendar.current.startOfDay(for: Date())
        let samples = try store.fetchSamples(from: today, to: Date())

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0].liquidType, .coconutWater)  // Most recent first
        XCTAssertEqual(samples[1].sodiumMilligrams, 250)
    }

    func testDeleteSample() throws {
        let sample = HydrationSample(id: "del1", timestamp: Date(), volumeMilliliters: 250, liquidType: .water)
        try store.save(sample)

        try store.deleteSample("del1")

        let today = Calendar.current.startOfDay(for: Date())
        let samples = try store.fetchSamples(from: today, to: Date())

        XCTAssertEqual(samples.count, 0)
    }

    func testSaveMetrics() throws {
        let metrics = HydrationMetrics(
            date: Date(),
            totalVolumeMilliliters: 1500,
            totalSodiumMilligrams: 250,
            exerciseMinutes: 30,
            recommendedIntakeMilliliters: 2200,
            sampleCount: 4
        )

        try store.save(metrics)

        let today = Calendar.current.startOfDay(for: Date())
        let fetched = try store.fetchMetrics(for: today)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.totalVolumeMilliliters, 1500)
        XCTAssertEqual(fetched?.exerciseMinutes, 30)
        XCTAssertEqual(fetched?.hydrationPercentage, (1500 / 2200) * 100, accuracy: 0.01)
    }

    func testSaveProfile() throws {
        let profile = HydrationProfile(
            userId: "user1",
            baselineIntakeMilliliters: 2200,
            bodyWeightKg: 75,
            activityLevel: .moderate
        )

        try store.save(profile)

        let fetched = try store.fetchProfile(for: "user1")

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.baselineIntakeMilliliters, 2200)
        XCTAssertEqual(fetched?.bodyWeightKg, 75)
        XCTAssertEqual(fetched?.activityLevel, .moderate)
    }

    func testSaveReminder() throws {
        let reminder = HydrationReminder(
            id: "rem1",
            intervalMinutes: 45,
            startHour: 6,
            endHour: 23
        )

        try store.save(reminder)

        let reminders = try store.fetchReminders()

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.intervalMinutes, 45)
        XCTAssertTrue(reminders.first?.isEnabled ?? false)
    }

    func testDeleteReminder() throws {
        let reminder = HydrationReminder(id: "rem2", intervalMinutes: 60)
        try store.save(reminder)

        try store.deleteReminder("rem2")

        let reminders = try store.fetchReminders()
        XCTAssertEqual(reminders.count, 0)
    }

    func testFetchSamplesByDateRange() throws {
        let today = Date()
        let yesterday = today.addingTimeInterval(-86400)
        let twoDaysAgo = today.addingTimeInterval(-172800)

        let s1 = HydrationSample(id: "s1", timestamp: twoDaysAgo, volumeMilliliters: 250, liquidType: .water)
        let s2 = HydrationSample(id: "s2", timestamp: yesterday, volumeMilliliters: 300, liquidType: .water)
        let s3 = HydrationSample(id: "s3", timestamp: today, volumeMilliliters: 200, liquidType: .water)

        try store.save(s1)
        try store.save(s2)
        try store.save(s3)

        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        let startOfToday = Calendar.current.startOfDay(for: today)

        let samples = try store.fetchSamples(from: startOfYesterday, to: today)

        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(samples.allSatisfy { $0.timestamp >= startOfYesterday && $0.timestamp <= today })
    }

    func testCalculateTodayMetrics() throws {
        let calculator = HydrationCalculator()
        let profile = HydrationProfile(userId: "user1", baselineIntakeMilliliters: 2000)

        try store.save(profile)

        let s1 = HydrationSample(id: "s1", timestamp: Date(), volumeMilliliters: 500, liquidType: .water)
        let s2 = HydrationSample(id: "s2", timestamp: Date(), volumeMilliliters: 300, liquidType: .sportsDrink, sodiumMilligrams: 250)

        try store.save(s1)
        try store.save(s2)

        let metrics = try store.calculateTodayMetrics(calculator: calculator, profile: profile)

        XCTAssertEqual(metrics.totalVolumeMilliliters, 800)
        XCTAssertEqual(metrics.totalSodiumMilligrams, 250)
        XCTAssertEqual(metrics.sampleCount, 2)
    }

    func testLiquidTypeVariations() throws {
        let liquidTypes: [LiquidType] = [.water, .sportsDrink, .electrolyteSolution, .coconutWater, .juice, .tea, .coffee, .milk, .other]

        for (index, type) in liquidTypes.enumerated() {
            let sample = HydrationSample(
                id: "s\(index)",
                timestamp: Date(),
                volumeMilliliters: Double(100 + index),
                liquidType: type
            )
            try store.save(sample)
        }

        let today = Calendar.current.startOfDay(for: Date())
        let samples = try store.fetchSamples(from: today, to: Date())

        XCTAssertEqual(samples.count, liquidTypes.count)
        let fetchedTypes = Set(samples.map { $0.liquidType })
        XCTAssertEqual(fetchedTypes.count, liquidTypes.count)
    }
}
