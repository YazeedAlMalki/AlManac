import XCTest
@testable import AlmanacCore

final class HydrationStoreTests: XCTestCase {

    private func fixture() throws -> (Database, HydrationStore, FixedClock) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000)) // 2026-02-25T06:13:20Z
        return (db, HydrationStore(db: db, clock: clock), clock)
    }

    func testLogAndEditAndDeleteRoundTrip() throws {
        let (_, store, _) = try fixture()
        let loggedAt = Date(timeIntervalSince1970: 1_772_000_100)
        let id = try store.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: loggedAt, note: "Morning glass"))

        var entry = try XCTUnwrap(store.entry(id: id))
        XCTAssertEqual(entry.amount, Milliliters(250))
        XCTAssertEqual(entry.note, "Morning glass")
        XCTAssertEqual(entry.sourceSystem, "manual")
        XCTAssertFalse(entry.healthKitSynced)

        try store.editAmount(id: id, to: Milliliters(300))
        entry = try XCTUnwrap(store.entry(id: id))
        XCTAssertEqual(entry.amount, Milliliters(300))

        try store.delete(id: id)
        XCTAssertNil(try store.entry(id: id), "a soft-deleted entry must not be returned by reads")
    }

    func testSoftDeletedEntriesAreExcludedFromLogsAndTotal() throws {
        let (_, store, _) = try fixture()
        let day = Date(timeIntervalSince1970: 1_772_000_100)
        let keep = try store.log(HydrationLogDraft(amount: Milliliters(200), loggedAt: day))
        let drop = try store.log(HydrationLogDraft(amount: Milliliters(500), loggedAt: day))
        try store.delete(id: drop)

        let logs = try store.logs(from: "2026-02-25", to: "2026-02-26")
        XCTAssertEqual(logs.map(\.id), [keep])
        XCTAssertEqual(try store.total(from: "2026-02-25", to: "2026-02-26"), Milliliters(200))
    }

    func testTotalRespectsADayBoundary() throws {
        let (_, store, _) = try fixture()
        // 2026-02-25T23:50:00Z — still inside the 25th.
        _ = try store.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: Date(timeIntervalSince1970: 1_772_063_400)))
        // 2026-02-26T00:43:20Z — inside the 26th, must not count toward the 25th.
        _ = try store.log(HydrationLogDraft(amount: Milliliters(400), loggedAt: Date(timeIntervalSince1970: 1_772_066_600)))

        XCTAssertEqual(try store.total(from: "2026-02-25", to: "2026-02-26"), Milliliters(250))
        XCTAssertEqual(try store.total(from: "2026-02-26", to: "2026-02-27"), Milliliters(400))
    }

    func testLogsAreOrderedByLoggedAt() throws {
        let (_, store, _) = try fixture()
        let later = try store.log(HydrationLogDraft(amount: Milliliters(100), loggedAt: Date(timeIntervalSince1970: 1_772_010_000)))
        let earlier = try store.log(HydrationLogDraft(amount: Milliliters(200), loggedAt: Date(timeIntervalSince1970: 1_772_000_100)))

        let logs = try store.logs(from: "2026-02-25", to: "2026-02-26")
        XCTAssertEqual(logs.map(\.id), [earlier, later])
    }

    func testTimelineEntriesCarryTheHydrationDomainAndAreDefiniteFit() throws {
        let (_, store, _) = try fixture()
        _ = try store.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: Date(timeIntervalSince1970: 1_772_000_100), note: "Post-run"))

        let entries = try store.entries(from: "2026-02-25", to: "2026-02-26")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.domain, "hydration")
        XCTAssertEqual(entry.recordTable, "hydration_log")
        XCTAssertEqual(entry.basis, .occurrence)
        XCTAssertEqual(entry.rangeFit, .definite)
        XCTAssertEqual(entry.detail, "Post-run")
        if case .quantity(let text, let unit) = entry.value {
            XCTAssertEqual(text, "250.0")
            XCTAssertEqual(unit, "ml")
        } else {
            XCTFail("expected a quantity value")
        }
    }

    func testEditAmountAndDeleteAreNoOpsForAnUnknownID() throws {
        let (_, store, _) = try fixture()
        // Neither call should throw for an id that was never logged.
        XCTAssertNoThrow(try store.editAmount(id: "missing", to: Milliliters(500)))
        XCTAssertNoThrow(try store.delete(id: "missing"))
    }
}
