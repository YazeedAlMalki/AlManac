import Testing
import Foundation
@testable import AlmanacCore

@Suite("PrayerTimeCacheStore Tests")
struct PrayerTimeCacheStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    private func sampleTimes(hourOffset: Int = 0) -> [PrayerTime] {
        let base = Date(timeIntervalSince1970: 1_700_000_000 + Double(hourOffset) * 3600)
        return [
            PrayerTime(name: "fajr", timestamp: base),
            PrayerTime(name: "sunrise", timestamp: base.addingTimeInterval(3600)),
            PrayerTime(name: "dhuhr", timestamp: base.addingTimeInterval(7 * 3600)),
            PrayerTime(name: "asr", timestamp: base.addingTimeInterval(10 * 3600)),
            PrayerTime(name: "maghrib", timestamp: base.addingTimeInterval(13 * 3600)),
            PrayerTime(name: "isha", timestamp: base.addingTimeInterval(14 * 3600))
        ]
    }

    @Test("Upserting a day can be read back with all six times")
    func upsertAndRead() throws {
        let store = PrayerTimeCacheStore(db: db)
        try store.upsert(date: "2026-09-17", times: sampleTimes(), latitude: 24.7136, longitude: 46.6753,
                          calculationMethod: "umm_al_qura")

        let cached = try store.cachedDay("2026-09-17")
        #expect(cached?.date == "2026-09-17")
        #expect(cached?.times.count == 6)
        #expect(cached?.times.first { $0.name == "fajr" } != nil)
        #expect(cached?.calculationMethod == "umm_al_qura")
        #expect(cached?.isManualOverride == false)
    }

    @Test("Upserting the same date twice replaces it rather than duplicating")
    func upsertReplaces() throws {
        let store = PrayerTimeCacheStore(db: db)
        try store.upsert(date: "2026-09-17", times: sampleTimes(), latitude: 24.7136, longitude: 46.6753,
                          calculationMethod: "umm_al_qura")
        try store.upsert(date: "2026-09-17", times: sampleTimes(hourOffset: 1), latitude: 24.7136, longitude: 46.6753,
                          calculationMethod: "mwl")

        let cached = try store.cachedDay("2026-09-17")
        #expect(cached?.calculationMethod == "mwl")
        let count = try db.query("SELECT COUNT(*) as n FROM prayer_times_cache;").first?.int("n")
        #expect(count == 1)
    }

    @Test("A date with no cached row returns nil")
    func missingDayIsNil() throws {
        let store = PrayerTimeCacheStore(db: db)
        #expect(try store.cachedDay("2026-09-17") == nil)
    }

    @Test("cachedDayCount counts rows from a date onward")
    func cachedDayCountFromDate() throws {
        let store = PrayerTimeCacheStore(db: db)
        for day in ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"] {
            try store.upsert(date: day, times: sampleTimes(), latitude: 24.7136, longitude: 46.6753,
                              calculationMethod: "umm_al_qura")
        }
        #expect(try store.cachedDayCount(from: "2026-09-16") == 3)
    }

    @Test("deleteFuture removes only rows after the given date, preserving history")
    func deleteFuturePreservesHistory() throws {
        let store = PrayerTimeCacheStore(db: db)
        for day in ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"] {
            try store.upsert(date: day, times: sampleTimes(), latitude: 24.7136, longitude: 46.6753,
                              calculationMethod: "umm_al_qura")
        }
        let deleted = try store.deleteFuture(after: "2026-09-16")

        #expect(deleted == 2)
        #expect(try store.cachedDay("2026-09-15") != nil)
        #expect(try store.cachedDay("2026-09-16") != nil)
        #expect(try store.cachedDay("2026-09-17") == nil)
        #expect(try store.cachedDay("2026-09-18") == nil)
    }

    @Test("deleteFuture never removes a manually overridden day")
    func deleteFuturePreservesManualOverride() throws {
        let store = PrayerTimeCacheStore(db: db)
        try store.upsert(date: "2026-09-20", times: sampleTimes(), latitude: 24.7136, longitude: 46.6753,
                          calculationMethod: "umm_al_qura", isManualOverride: true)

        let deleted = try store.deleteFuture(after: "2026-09-17")

        #expect(deleted == 0)
        #expect(try store.cachedDay("2026-09-20") != nil)
    }
}
