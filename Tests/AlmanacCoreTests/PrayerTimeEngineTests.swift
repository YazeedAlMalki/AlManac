import Testing
import Foundation
@testable import AlmanacCore

@Suite("PrayerTimeEngine Tests")
struct PrayerTimeEngineTests {
    let db: Database
    let riyadhTZ = TimeZone(identifier: "Asia/Riyadh")!

    init() throws {
        db = try TestDatabase()
    }

    private func calendarDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        comps.timeZone = riyadhTZ
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private func riyadhSettings(method: String = "umm_al_qura") -> PrayerSettings {
        PrayerSettings(calculationMethod: method, customFajrAngleDeg: nil, customIshaAngleDeg: nil,
                        latitude: 24.7136, longitude: 46.6753, city: "Riyadh", country: "Saudi Arabia",
                        manualCityOverride: false, fajrOffsetMin: 0, dhuhrOffsetMin: 0, asrOffsetMin: 0,
                        maghribOffsetMin: 0, ishaOffsetMin: 0, timezone: "Asia/Riyadh", updatedAt: Date())
    }

    @Test("recalculateCache writes 30 consecutive days starting from the given date")
    func recalculateWritesThirtyDays() throws {
        let cacheStore = PrayerTimeCacheStore(db: db)
        let written = try PrayerTimeEngine.recalculateCache(
            cacheStore, settings: riyadhSettings(), timeZone: riyadhTZ,
            startDate: calendarDate(2026, 9, 17))

        #expect(written == 30)
        #expect(try cacheStore.cachedDay("2026-09-17") != nil)
        #expect(try cacheStore.cachedDay("2026-10-16") != nil)
        #expect(try cacheStore.cachedDay("2026-10-17") == nil)
    }

    @Test("recalculateCache skips a day already flagged as a manual override")
    func recalculateSkipsManualOverride() throws {
        let cacheStore = PrayerTimeCacheStore(db: db)
        let manualTimes = [
            PrayerTime(name: "fajr", timestamp: Date(timeIntervalSince1970: 0)),
            PrayerTime(name: "sunrise", timestamp: Date(timeIntervalSince1970: 1)),
            PrayerTime(name: "dhuhr", timestamp: Date(timeIntervalSince1970: 2)),
            PrayerTime(name: "asr", timestamp: Date(timeIntervalSince1970: 3)),
            PrayerTime(name: "maghrib", timestamp: Date(timeIntervalSince1970: 4)),
            PrayerTime(name: "isha", timestamp: Date(timeIntervalSince1970: 5))
        ]
        try cacheStore.upsert(date: "2026-09-18", times: manualTimes, latitude: 24.7136, longitude: 46.6753,
                               calculationMethod: "umm_al_qura", isManualOverride: true)

        let written = try PrayerTimeEngine.recalculateCache(
            cacheStore, settings: riyadhSettings(), timeZone: riyadhTZ,
            startDate: calendarDate(2026, 9, 17))

        #expect(written == 29)
        let untouched = try cacheStore.cachedDay("2026-09-18")
        #expect(untouched?.times.first?.timestamp == Date(timeIntervalSince1970: 0))
    }

    @Test("ensureCache recalculates when fewer than the minimum days are cached")
    func ensureCacheRecalculatesWhenSparse() throws {
        let cacheStore = PrayerTimeCacheStore(db: db)
        let didRecalculate = try PrayerTimeEngine.ensureCache(
            cacheStore, settings: riyadhSettings(), timeZone: riyadhTZ,
            at: calendarDate(2026, 9, 17))

        #expect(didRecalculate == true)
        #expect(try cacheStore.cachedDayCount(from: "2026-09-17") == 30)
    }

    @Test("ensureCache is a no-op once enough days are already cached")
    func ensureCacheNoOpWhenWarm() throws {
        let cacheStore = PrayerTimeCacheStore(db: db)
        try PrayerTimeEngine.recalculateCache(cacheStore, settings: riyadhSettings(), timeZone: riyadhTZ,
                                               startDate: calendarDate(2026, 9, 17))

        let didRecalculate = try PrayerTimeEngine.ensureCache(
            cacheStore, settings: riyadhSettings(), timeZone: riyadhTZ,
            at: calendarDate(2026, 9, 18))

        #expect(didRecalculate == false)
    }

    @Test("ensureCache does nothing when no location has been set yet")
    func ensureCacheNoLocationYet() throws {
        let cacheStore = PrayerTimeCacheStore(db: db)
        let noLocation = PrayerSettings(calculationMethod: "umm_al_qura", customFajrAngleDeg: nil,
                                         customIshaAngleDeg: nil, latitude: nil, longitude: nil,
                                         city: nil, country: nil, manualCityOverride: false,
                                         fajrOffsetMin: 0, dhuhrOffsetMin: 0, asrOffsetMin: 0,
                                         maghribOffsetMin: 0, ishaOffsetMin: 0, timezone: "Asia/Riyadh",
                                         updatedAt: Date())

        let didRecalculate = try PrayerTimeEngine.ensureCache(
            cacheStore, settings: noLocation, timeZone: riyadhTZ, at: calendarDate(2026, 9, 17))

        #expect(didRecalculate == false)
        #expect(try cacheStore.cachedDayCount(from: "2026-09-17") == 0)
    }

    @Test("A location update under 50 km is not a real move — no invalidation, no recalculation")
    func smallMoveIsIgnored() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                          country: "Saudi Arabia", manualCityOverride: false)
        try PrayerTimeEngine.recalculateCache(cacheStore, settings: try settingsStore.settings(),
                                               timeZone: riyadhTZ, startDate: calendarDate(2026, 9, 17))

        // ~5 km away within Riyadh.
        let moved = try PrayerTimeEngine.applyLocationUpdate(
            latitude: 24.76, longitude: 46.71, at: calendarDate(2026, 9, 17), timeZone: riyadhTZ,
            settingsStore: settingsStore, cacheStore: cacheStore)

        #expect(moved == false)
        #expect(try settingsStore.settings().latitude == 24.7136)
        #expect(try cacheStore.cachedDayCount(from: "2026-09-17") == 30)
    }

    @Test("A location update over 50 km updates settings, invalidates future cache, and recalculates")
    func largeMoveTriggersFullTravelFlow() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                          country: "Saudi Arabia", manualCityOverride: true)
        try PrayerTimeEngine.recalculateCache(cacheStore, settings: try settingsStore.settings(),
                                               timeZone: riyadhTZ, startDate: calendarDate(2026, 9, 17))

        // Jeddah — roughly 850 km from Riyadh.
        let jeddahTZ = TimeZone(identifier: "Asia/Riyadh")!
        let moved = try PrayerTimeEngine.applyLocationUpdate(
            latitude: 21.4858, longitude: 39.1925, at: calendarDate(2026, 9, 17), timeZone: jeddahTZ,
            settingsStore: settingsStore, cacheStore: cacheStore)

        #expect(moved == true)
        let settings = try settingsStore.settings()
        #expect(settings.latitude == 21.4858)
        #expect(settings.longitude == 39.1925)
        #expect(settings.manualCityOverride == false)

        // Cache should now reflect Jeddah's coordinates, not Riyadh's.
        let refreshed = try cacheStore.cachedDay("2026-09-17")
        #expect(refreshed?.latitude == 21.4858)
        #expect(try cacheStore.cachedDayCount(from: "2026-09-17") == 30)
    }

    @Test("A large move never touches past cached dates")
    func largeMovePreservesHistory() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                          country: "Saudi Arabia", manualCityOverride: false)
        try cacheStore.upsert(date: "2026-09-10", times: [
            PrayerTime(name: "fajr", timestamp: Date(timeIntervalSince1970: 100)),
            PrayerTime(name: "sunrise", timestamp: Date(timeIntervalSince1970: 101)),
            PrayerTime(name: "dhuhr", timestamp: Date(timeIntervalSince1970: 102)),
            PrayerTime(name: "asr", timestamp: Date(timeIntervalSince1970: 103)),
            PrayerTime(name: "maghrib", timestamp: Date(timeIntervalSince1970: 104)),
            PrayerTime(name: "isha", timestamp: Date(timeIntervalSince1970: 105))
        ], latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")

        _ = try PrayerTimeEngine.applyLocationUpdate(
            latitude: 21.4858, longitude: 39.1925, at: calendarDate(2026, 9, 17), timeZone: riyadhTZ,
            settingsStore: settingsStore, cacheStore: cacheStore)

        let historical = try cacheStore.cachedDay("2026-09-10")
        #expect(historical?.latitude == 24.7136)
        #expect(historical?.times.first?.timestamp == Date(timeIntervalSince1970: 100))
    }
}
