import XCTest
@testable import AlmanacCore

/// BRD §6.2: one drink entry fills hydration, caffeine and nutrition, and the
/// caffeine is judged against intended sleep, not the clock. Acceptance A1's
/// latte step. Before Migration 063 a logged drink recorded no caffeine at all.
final class DrinkCaffeineTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let day = "2026-09-16"

    private func makeDB() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func store(_ db: Database) -> HydrationStore {
        HydrationStore(db: db, zone: ZoneContext(utc))
    }

    private func service(_ db: Database) -> HydrationLoggingService {
        HydrationLoggingService(store: store(db), settingsStore: HydrationSettingsStore(db: db),
                                timeModel: TimeModel(timeZone: utc))
    }

    private func at(_ time: String) -> Date {
        ISO8601DateFormatter().date(from: "\(day)T\(time):00Z")!
    }

    private func caffeine(_ db: Database) throws -> [CaffeineLogEntry] {
        try CaffeineLogStore(db: db).entries(for: day)
    }

    private func link(_ db: Database) throws -> [String?] {
        try db.query("SELECT hydrationLogId FROM caffeine_log ORDER BY id;").map { $0.string("hydrationLogId") }
    }

    // MARK: - One entry, every part

    func testALatteRecordsItsCaffeineWithTheWater() throws {
        let db = try makeDB()
        let latte = CatalogDrinks.byID("catalog_coffee_latte")!

        let result = try service(db).logDrink(latte, at: at("09:00"))

        XCTAssertEqual(try store(db).entry(id: result.hydrationLogID)?.drink?.caloriesKcal, latte.caloriesKcal)
        let entries = try caffeine(db)
        XCTAssertEqual(entries.map(\.caffeineMg), [latte.caffeineMilligrams])
        XCTAssertEqual(entries.first?.drinkType, "catalog_coffee_latte")
        XCTAssertEqual(entries.first?.timestamp, at("09:00"))
        XCTAssertEqual(try link(db), [result.hydrationLogID])
    }

    func testCaffeineScalesWithTheAmountDrunk() throws {
        let db = try makeDB()
        let coke = CatalogDrinks.byID("catalog_coke")!

        try service(db).logDrink(coke, volume: Milliliters(coke.volumeMilliliters / 2), at: at("12:00"))

        XCTAssertEqual(try caffeine(db).first?.caffeineMg ?? 0, coke.caffeineMilligrams / 2, accuracy: 0.001)
    }

    func testADrinkWithoutCaffeineRecordsNone() throws {
        let db = try makeDB()
        try service(db).logDrink(CatalogDrinks.byID("catalog_water")!, at: at("10:00"))
        try service(db).logDrink(CatalogDrinks.byID("catalog_orange_juice")!, at: at("10:30"))
        XCTAssertTrue(try caffeine(db).isEmpty)
    }

    func testCoffeeAndTeaCarryCaffeineAndWaterDoesNot() {
        for drink in CatalogDrinks.all where drink.liquidType == .coffee || drink.liquidType == .tea {
            XCTAssertGreaterThan(drink.caffeineMilligrams, 0, drink.id)
        }
        XCTAssertEqual(CatalogDrinks.byID("catalog_water")?.caffeineMilligrams, 0)
    }

    // MARK: - Judged against intended sleep

    /// The BRD's own example: 8 AM coffee is late for a night-shift worker
    /// who sleeps at 10 AM.
    func testMorningCoffeeIsLateForSomeoneWhoSleepsAtTen() throws {
        let db = try makeDB()
        let shifts = ShiftScheduleStore(db: db)
        let schedule = try shifts.createSchedule(ShiftScheduleDraft(name: "Nights"))
        try shifts.logOccurrence(ShiftOccurrenceDraft(scheduleId: schedule, date: day, shiftType: .night,
                                                      expectedSleepWindowStart: at("10:00")))

        try service(db).logDrink(CatalogDrinks.byID("catalog_coffee_black")!, at: at("08:00"))

        let entry = try XCTUnwrap(caffeine(db).first)
        XCTAssertEqual(entry.caffeineContext, "very_late")
        XCTAssertEqual(entry.hoursBeforeIntendedSleep ?? 0, 2, accuracy: 0.001)
    }

    func testWithNoScheduleTheCaffeineIsRecordedUnclassified() throws {
        let db = try makeDB()
        try service(db).logDrink(CatalogDrinks.byID("catalog_coffee_black")!, at: at("08:00"))
        let entry = try XCTUnwrap(caffeine(db).first)
        XCTAssertNil(entry.caffeineContext)
        XCTAssertEqual(entry.caffeineMg, 95)
    }

    // MARK: - The caffeine follows the drink

    func testResizingTheDrinkResizesItsCaffeine() throws {
        let db = try makeDB()
        let coffee = CatalogDrinks.byID("catalog_coffee_black")!
        let id = try service(db).logDrink(coffee, at: at("08:00")).hydrationLogID

        try store(db).editAmount(id: id, to: Milliliters(coffee.volumeMilliliters * 2))

        XCTAssertEqual(try caffeine(db).first?.caffeineMg ?? 0, coffee.caffeineMilligrams * 2, accuracy: 0.001)
    }

    func testMovingTheDrinkJudgesItsCaffeineAgain() throws {
        let db = try makeDB()
        let shifts = ShiftScheduleStore(db: db)
        let schedule = try shifts.createSchedule(ShiftScheduleDraft(name: "Days"))
        try shifts.logOccurrence(ShiftOccurrenceDraft(scheduleId: schedule, date: day, shiftType: .day,
                                                      expectedSleepWindowStart: at("23:00")))
        let id = try service(db).logDrink(CatalogDrinks.byID("catalog_coffee_black")!, at: at("08:00"))
            .hydrationLogID
        XCTAssertEqual(try caffeine(db).first?.caffeineContext, "early")

        try store(db).editLoggedAt(id: id, to: at("21:00"))

        let entry = try XCTUnwrap(caffeine(db).first)
        XCTAssertEqual(entry.timestamp, at("21:00"))
        XCTAssertEqual(entry.caffeineContext, "very_late")
    }

    func testDeletingTheDrinkDeletesItsCaffeine() throws {
        let db = try makeDB()
        let id = try service(db).logDrink(CatalogDrinks.byID("catalog_coffee_black")!, at: at("08:00"))
            .hydrationLogID
        try service(db).logDrink(CatalogDrinks.byID("catalog_tea_black")!, at: at("15:00"))

        try store(db).delete(id: id)

        XCTAssertEqual(try caffeine(db).map(\.drinkType), ["catalog_tea_black"])
        XCTAssertEqual(try CaffeineLogStore(db: db).totalCaffeine(for: day), 47)
    }
}
