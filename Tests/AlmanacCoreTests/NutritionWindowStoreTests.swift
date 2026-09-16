import Testing
import Foundation
@testable import AlmanacCore

@Suite("NutritionWindowStore Tests")
struct NutritionWindowStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    // Maghrib(D) = 2026-09-17 17:55 Riyadh (UTC+3) = 14:55 UTC.
    // Fajr(D+1)  = 2026-09-18 04:22 Riyadh          = 01:22 UTC.
    private var maghribD: Date { Date(timeIntervalSince1970: 1_789_656_900) }  // 2026-09-17T14:55:00Z
    private var fajrDPlus1: Date { Date(timeIntervalSince1970: 1_789_694_520) } // 2026-09-18T01:22:00Z

    @Test("A created night window can be read back by date and type")
    func createAndRead() throws {
        let store = NutritionWindowStore(db: db)
        try store.createWindow(date: "2026-09-17", windowType: "night_nutrition_window",
                                startTimestamp: maghribD, endTimestamp: fajrDPlus1,
                                fajrTimestamp: fajrDPlus1, maghribTimestamp: maghribD)

        let window = try store.window(date: "2026-09-17", windowType: "night_nutrition_window")
        #expect(window?.startTimestamp == maghribD)
        #expect(window?.endTimestamp == fajrDPlus1)
    }

    @Test("Creating a window twice for the same (date, windowType) replaces it")
    func createTwiceReplaces() throws {
        let store = NutritionWindowStore(db: db)
        try store.createWindow(date: "2026-09-17", windowType: "night_nutrition_window",
                                startTimestamp: maghribD, endTimestamp: fajrDPlus1)
        try store.createWindow(date: "2026-09-17", windowType: "night_nutrition_window",
                                startTimestamp: maghribD.addingTimeInterval(60), endTimestamp: fajrDPlus1)

        let window = try store.window(date: "2026-09-17", windowType: "night_nutrition_window")
        #expect(window?.startTimestamp == maghribD.addingTimeInterval(60))
        let count = try db.query("SELECT COUNT(*) as n FROM nutrition_window;").first?.int("n")
        #expect(count == 1)
    }

    @Test("A 03:50 suhoor entry on the calendar day after Maghrib still belongs to D's window")
    func suhoorAfterMidnightBelongsToPreviousDaysWindow() throws {
        let store = NutritionWindowStore(db: db)
        try store.createWindow(date: "2026-09-17", windowType: "night_nutrition_window",
                                startTimestamp: maghribD, endTimestamp: fajrDPlus1)

        // 2026-09-18T00:50:00Z = 03:50 Riyadh time, still before Fajr(D+1).
        let suhoorEntry = Date(timeIntervalSince1970: 1_789_692_600)
        let window = try store.window(containing: suhoorEntry)

        #expect(window?.date == "2026-09-17")
    }

    @Test("An entry before Maghrib or at/after Fajr does not match the night window")
    func entryOutsideWindowDoesNotMatch() throws {
        let store = NutritionWindowStore(db: db)
        try store.createWindow(date: "2026-09-17", windowType: "night_nutrition_window",
                                startTimestamp: maghribD, endTimestamp: fajrDPlus1)

        #expect(try store.window(containing: maghribD.addingTimeInterval(-60)) == nil)
        #expect(try store.window(containing: fajrDPlus1) == nil)
    }

    @Test("A window with no matching date/type returns nil")
    func missingWindowIsNil() throws {
        let store = NutritionWindowStore(db: db)
        #expect(try store.window(date: "2026-09-17", windowType: "night_nutrition_window") == nil)
    }
}
