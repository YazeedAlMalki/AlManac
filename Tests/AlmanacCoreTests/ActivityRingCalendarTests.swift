import XCTest
import AlmanacCore

final class ActivityRingCalendarTests: XCTestCase {
    func testHydrationRingUsesTheFourAMLogicalDayBoundary() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        let hydration = HydrationStore(db: db, zone: ZoneContext(timeModel.timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone

        let beforeBoundary = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 24, hour: 3, minute: 30
        ))!
        let afterBoundary = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 24, hour: 4
        ))!
        try hydration.log(HydrationLogDraft(amount: Milliliters(500), loggedAt: beforeBoundary))
        try hydration.log(HydrationLogDraft(amount: Milliliters(700), loggedAt: afterBoundary))
        try HydrationSettingsStore(db: db).save(HydrationSettings(dailyGoalMilliliters: 1_000))

        let month = try ActivityRingCalendar(db: db, timeModel: timeModel)
            .month(containing: beforeBoundary)

        let previousDay = try XCTUnwrap(month.day(on: "2026-09-23"))
        XCTAssertEqual(previousDay.hydrationTotalMilliliters, Milliliters(500))
        XCTAssertEqual(previousDay.hydrationTargetMilliliters, Milliliters(1_000))
        XCTAssertEqual(previousDay.hydration, .incomplete)

        let currentDay = try XCTUnwrap(month.day(on: "2026-09-24"))
        XCTAssertEqual(currentDay.hydrationTotalMilliliters, Milliliters(700))
        XCTAssertEqual(currentDay.hydration, .incomplete)
    }

    func testTrainingRingIsCompleteOnlyWhenTheDayHasALiveSession() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        let store = WorkoutSessionStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        let sessionID = try store.log(WorkoutSessionDraft(date: "2026-09-24", durationMinutes: 45))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let containing = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!

        let month = try ActivityRingCalendar(db: db, timeModel: timeModel)
            .month(containing: containing)

        XCTAssertEqual(try XCTUnwrap(month.day(on: "2026-09-24")).training, .complete)
        XCTAssertEqual(try XCTUnwrap(month.day(on: "2026-09-25")).training, .incomplete)

        try store.delete(id: sessionID)
        let afterDelete = try ActivityRingCalendar(db: db, timeModel: timeModel)
            .month(containing: containing)
        XCTAssertEqual(try XCTUnwrap(afterDelete.day(on: "2026-09-24")).training, .incomplete)
    }

    func testDayWithoutNutritionLogsHasNoNutritionRing() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!

        let day = try XCTUnwrap(ActivityRingCalendar(db: db, timeModel: timeModel)
            .month(containing: date).day(on: "2026-09-24"))

        XCTAssertEqual(day.nutrition, .notLogged)
    }

    func testLoggedNutritionWaitsForDietProfileTargets() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        let zone = ZoneContext(timeModel.timeZone)
        let log = NutritionLogStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)), zone: zone)
        try log.record(NutritionLogDraft(
            foodRef: SourceIdentifier(namespace: .usda, localID: "1105904"),
            grams: 150,
            eatenAt: PartialDateTime(text: "2026-09-24T12:30:00+03:00", precision: .instant, zone: zone),
            foodNameText: "Rice"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!

        let day = try XCTUnwrap(ActivityRingCalendar(db: db, timeModel: timeModel)
            .month(containing: date).day(on: "2026-09-24"))

        XCTAssertEqual(day.nutrition, .dietProfileRequired)
    }

    func testDigestionRingSettingPersistsWithoutInventingAFillRule() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let settings = ActivityRingSettingsStore(db: db)
        let rings = ActivityRingCalendar(db: db, timeModel: timeModel)

        XCTAssertEqual(try XCTUnwrap(rings.month(containing: date).day(on: "2026-09-24")).digestion, .disabled)
        XCTAssertFalse(try settings.isDigestionEnabled())

        try settings.setDigestionEnabled(true)
        XCTAssertTrue(try settings.isDigestionEnabled())
        XCTAssertEqual(try XCTUnwrap(rings.month(containing: date).day(on: "2026-09-24")).digestion, .fillRuleUnavailable)
    }

    func testGoldenDayIsNotAwardedWithoutNutritionTargets() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        try HydrationSettingsStore(db: db).save(HydrationSettings(dailyGoalMilliliters: 1_000))
        try HydrationStore(db: db, zone: ZoneContext(timeModel.timeZone))
            .log(HydrationLogDraft(amount: Milliliters(1_000), loggedAt: date))
        try WorkoutSessionStore(db: db).log(WorkoutSessionDraft(date: "2026-09-24"))
        let rings = ActivityRingCalendar(db: db, timeModel: timeModel)

        let complete = try XCTUnwrap(rings.month(containing: date).day(on: "2026-09-24"))
        XCTAssertFalse(complete.isGolden)

        let zone = ZoneContext(timeModel.timeZone)
        try NutritionLogStore(db: db, zone: zone).record(NutritionLogDraft(
            foodRef: SourceIdentifier(namespace: .usda, localID: "1105904"),
            grams: 150,
            eatenAt: PartialDateTime(text: "2026-09-24T12:30:00+03:00", precision: .instant, zone: zone)
        ))
        let unresolved = try XCTUnwrap(rings.month(containing: date).day(on: "2026-09-24"))
        XCTAssertFalse(unresolved.isGolden)
    }

    func testMonthContainsTheCivilDatesOfThatMonth() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!

        let month = try ActivityRingCalendar(db: db, timeModel: timeModel).month(containing: date)

        XCTAssertEqual(month.days.count, 30)
        XCTAssertEqual(month.days.first?.day.value, "2026-09-01")
        XCTAssertEqual(month.days.last?.day.value, "2026-09-30")
    }
}
