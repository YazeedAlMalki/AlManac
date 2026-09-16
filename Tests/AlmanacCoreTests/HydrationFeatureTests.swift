import XCTest
@testable import AlmanacCore

final class HydrationFeatureTests: XCTestCase {
    private func makeDB() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    // MARK: - Catalog

    func testCatalogSearchIsCaseInsensitive() {
        XCTAssertTrue(CatalogDrinks.search(query: "gatorade").contains { $0.id == "catalog_gatorade" })
        XCTAssertTrue(CatalogDrinks.search(query: "GATORADE").contains { $0.id == "catalog_gatorade" })
    }

    func testEveryCatalogDrinkIsTaggedUnsourced() {
        XCTAssertFalse(CatalogDrinks.all.isEmpty)
        XCTAssertTrue(CatalogDrinks.all.allSatisfy { $0.valueQualifier == .catalogUnsourcedEstimate })
    }

    // MARK: - Logging a catalog drink

    func testLoggingACatalogDrinkAtDefaultVolumeAttachesUnscaledFigures() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))
        let gatorade = CatalogDrinks.byID("catalog_gatorade")!

        let result = try service.logDrink(gatorade)
        let entry = try HydrationStore(db: db).entry(id: result.hydrationLogID)

        XCTAssertEqual(entry?.drink?.caloriesKcal, gatorade.caloriesKcal)
        XCTAssertEqual(entry?.drink?.sodiumMg, gatorade.sodiumMilligrams)
        XCTAssertEqual(entry?.drink?.qualifier, .catalogUnsourcedEstimate)
    }

    func testLoggingHalfAServingScalesEveryFigure() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))
        let coke = CatalogDrinks.byID("catalog_coke")!

        let result = try service.logDrink(coke, volume: Milliliters(coke.volumeMilliliters / 2))
        let entry = try HydrationStore(db: db).entry(id: result.hydrationLogID)

        XCTAssertEqual(entry?.drink?.caloriesKcal ?? 0, coke.caloriesKcal / 2, accuracy: 0.001)
        XCTAssertEqual(entry?.drink?.sugarG ?? 0, coke.sugarGrams! / 2, accuracy: 0.001)
    }

    func testAPlainAmountWithNoDrinkCarriesNoAttachment() throws {
        let db = try makeDB()
        let store = HydrationStore(db: db)
        let id = try store.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: Date()))
        let entry = try store.entry(id: id)
        XCTAssertNil(entry?.drink)
    }

    // MARK: - Custom drinks

    func testACustomDrinkIsTaggedUserEnteredAndRoundTrips() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))

        let drink = try service.saveCustomDrink(name: "My Protein Shake", liquidType: .milk,
                                                  volumeMilliliters: 300, caloriesKcal: 250,
                                                  sodiumMilligrams: 180, sugarGrams: 8)
        XCTAssertEqual(drink.valueQualifier, .userEntered)

        let stored = try service.customDrinks()
        XCTAssertEqual(stored.map(\.name), ["My Protein Shake"])

        let all = try service.allDrinks()
        XCTAssertTrue(all.contains { $0.name == "My Protein Shake" })
        XCTAssertTrue(all.contains { $0.id == "catalog_water" })
    }

    // MARK: - Double-track detection

    func testLoggingTheSameDrinkTwiceWithinTheWindowWarns() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))
        let water = CatalogDrinks.byID("catalog_water")!
        let now = Date()

        _ = try service.logDrink(water, at: now.addingTimeInterval(-60))
        let second = try service.logDrink(water, at: now)

        XCTAssertTrue(second.warnings.contains { $0.type == .possibleDoubleTrack })
    }

    func testLoggingADifferentDrinkWithinTheWindowDoesNotWarn() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))
        let water = CatalogDrinks.byID("catalog_water")!
        let coffee = CatalogDrinks.byID("catalog_coffee_black")!
        let now = Date()

        _ = try service.logDrink(water, at: now.addingTimeInterval(-60))
        let second = try service.logDrink(coffee, at: now)

        XCTAssertFalse(second.warnings.contains { $0.type == .possibleDoubleTrack })
    }

    func testLoggingTheSameDrinkOutsideTheWindowDoesNotWarn() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))
        let water = CatalogDrinks.byID("catalog_water")!
        let now = Date()

        _ = try service.logDrink(water, at: now.addingTimeInterval(-3600))
        let second = try service.logDrink(water, at: now)

        XCTAssertFalse(second.warnings.contains { $0.type == .possibleDoubleTrack })
    }

    func testHighSugarWarns() throws {
        let db = try makeDB()
        let service = HydrationLoggingService(store: HydrationStore(db: db), settingsStore: HydrationSettingsStore(db: db))
        let monster = CatalogDrinks.byID("catalog_monster")! // 54g sugar

        let result = try service.logDrink(monster)
        XCTAssertTrue(result.warnings.contains { $0.type == .highSugar })
    }

    // MARK: - Settings and profile

    func testSettingsGetOrCreateReturnsDefaultsThenPersists() throws {
        let db = try makeDB()
        let store = HydrationSettingsStore(db: db)

        let defaults = try store.getOrCreate()
        XCTAssertFalse(defaults.isCalorieTrackingEnabled)

        try store.save(HydrationSettings(isCalorieTrackingEnabled: true, remindersEnabled: false,
                                          updatedAt: Date()))

        let reread = try store.fetch()
        XCTAssertEqual(reread?.isCalorieTrackingEnabled, true)
        XCTAssertEqual(reread?.remindersEnabled, false)
    }

    func testProfileGetOrCreateReturnsDefaultsThenPersists() throws {
        let db = try makeDB()
        let store = HydrationProfileStore(db: db)

        let defaults = try store.getOrCreate()
        XCTAssertEqual(defaults.activityLevel, .moderate)

        try store.save(HydrationProfile(baselineIntakeMilliliters: 2500, bodyWeightKg: 80,
                                         activityLevel: .high, updatedAt: Date()))

        let reread = try store.fetch()
        XCTAssertEqual(reread?.bodyWeightKg, 80)
        XCTAssertEqual(reread?.activityLevel, .high)
    }

    // MARK: - Calculator (ported as-is; pinning the port did not change behaviour)

    func testCriticalUrgencyDuringExerciseWithALargeGap() {
        let calculator = HydrationCalculator()
        let profile = HydrationProfile(baselineIntakeMilliliters: 2000)
        let metrics = HydrationMetrics(date: Date(), totalVolumeMilliliters: 200,
                                        totalSodiumMilligrams: 0, exerciseMinutes: 30,
                                        recommendedIntakeMilliliters: 2000, sampleCount: 1)

        let rec = calculator.currentRecommendation(timeSinceLastDrinkMinutes: 150, exerciseActive: true,
                                                     metrics: metrics, profile: profile)
        XCTAssertEqual(rec.urgency, .critical)
        XCTAssertEqual(rec.reason, "You're exercising - stay hydrated! Drink water or electrolyte sports drink.")
    }

    func testLowUrgencyWhenWellHydrated() {
        let calculator = HydrationCalculator()
        let profile = HydrationProfile(baselineIntakeMilliliters: 2000)
        let metrics = HydrationMetrics(date: Date(), totalVolumeMilliliters: 2000,
                                        totalSodiumMilligrams: 0, exerciseMinutes: 0,
                                        recommendedIntakeMilliliters: 2000, sampleCount: 8)

        let rec = calculator.currentRecommendation(timeSinceLastDrinkMinutes: 10, exerciseActive: false,
                                                     metrics: metrics, profile: profile)
        XCTAssertEqual(rec.urgency, .low)
    }

    // MARK: - Health bridge

    func testExerciseMinutesClipsAWorkoutSpanningMidnight() throws {
        let db = try makeDB()
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 15
        let day = calendar.date(from: comps)!
        let dayStart = calendar.startOfDay(for: day)

        // A workout from 23:30 the day before to 00:30 this day: 30 min in each day.
        let workoutStart = dayStart.addingTimeInterval(-30 * 60)
        let workoutEnd = dayStart.addingTimeInterval(30 * 60)
        let iso = ISO8601DateFormatter()
        try db.run("""
        INSERT INTO health_sample (id, source_system, external_id, domain, start_at, end_at, value, unit, recorded_at)
        VALUES ('s1', 'test', 'ext1', 'workouts', ?, ?, NULL, NULL, ?);
        """, [.text(iso.string(from: workoutStart)), .text(iso.string(from: workoutEnd)), .text(iso.string(from: Date()))])

        let bridge = HydrationHealthBridge(db: db, calendar: calendar)
        let minutes = try bridge.exerciseMinutes(on: day)
        XCTAssertEqual(minutes, 30, accuracy: 0.01)
    }

    // MARK: - Reminder service

    func testCheckReminderReturnsNilWhenRemindersAreDisabled() throws {
        let db = try makeDB()
        let settingsStore = HydrationSettingsStore(db: db)
        try settingsStore.save(HydrationSettings(remindersEnabled: false))

        let service = HydrationReminderService(store: HydrationStore(db: db), settingsStore: settingsStore)
        let profile = HydrationProfile()
        let metrics = HydrationMetrics(date: Date(), totalVolumeMilliliters: 0, totalSodiumMilligrams: 0,
                                        exerciseMinutes: nil, recommendedIntakeMilliliters: 2000, sampleCount: 0)

        XCTAssertNil(try service.checkReminder(profile: profile, metrics: metrics))
    }

    func testCheckReminderFiresWhenOverdueWithinTheWindow() throws {
        let db = try makeDB()
        let settingsStore = HydrationSettingsStore(db: db)
        try settingsStore.save(HydrationSettings(remindersEnabled: true, reminderIntervalMinutes: 60,
                                                   reminderStartHour: 0, reminderEndHour: 23))

        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 15; comps.hour = 12
        let fixedNow = Calendar(identifier: .gregorian).date(from: comps)!
        let service = HydrationReminderService(store: HydrationStore(db: db), settingsStore: settingsStore,
                                                 clock: FixedClock(fixedNow))
        let profile = HydrationProfile()
        let metrics = HydrationMetrics(date: fixedNow, totalVolumeMilliliters: 0, totalSodiumMilligrams: 0,
                                        exerciseMinutes: nil, recommendedIntakeMilliliters: 2000, sampleCount: 0)

        // No entries logged today at all -> "time since last drink" falls back
        // to minutes since midnight, which at noon is 720 minutes -- well
        // past the 60-minute interval.
        XCTAssertNotNil(try service.checkReminder(profile: profile, metrics: metrics))
    }
}
