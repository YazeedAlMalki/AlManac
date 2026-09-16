import Foundation

/// A `prayer_times_cache` row read from storage (§5.22, §12.3).
public struct CachedPrayerTimes: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let date: String
    public let times: [PrayerTime]
    public let latitude: Double
    public let longitude: Double
    public let calculationMethod: String
    public let isManualOverride: Bool
    public let createdAt: Date
}

/// Plain CRUD over `prayer_times_cache`. The §12.3/§12.4 orchestration
/// (when to recalculate, travel-distance thresholds) lives in
/// `PrayerTimeEngine`, which uses this store rather than duplicating its SQL.
public struct PrayerTimeCacheStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    /// Upserts by `date` (Migration024's unique index) — one row per day,
    /// replaced wholesale on recalculation rather than accumulating history.
    @discardableResult
    public func upsert(date: String, times: [PrayerTime], latitude: Double, longitude: Double,
                        calculationMethod: String, isManualOverride: Bool = false) throws -> Int64 {
        func time(_ name: String) -> Date? { times.first { $0.name == name }?.timestamp }
        guard let fajr = time("fajr"), let sunrise = time("sunrise"), let dhuhr = time("dhuhr"),
              let asr = time("asr"), let maghrib = time("maghrib"), let isha = time("isha") else {
            throw PrayerTimeCacheStoreError.incompleteTimes
        }

        try db.run("""
        INSERT INTO prayer_times_cache
            (date, fajr, sunrise, dhuhr, asr, maghrib, isha, latitude, longitude,
             calculationMethod, isManualOverride, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
            fajr = excluded.fajr, sunrise = excluded.sunrise, dhuhr = excluded.dhuhr,
            asr = excluded.asr, maghrib = excluded.maghrib, isha = excluded.isha,
            latitude = excluded.latitude, longitude = excluded.longitude,
            calculationMethod = excluded.calculationMethod,
            isManualOverride = excluded.isManualOverride;
        """, [
            .text(date), .text(iso(fajr)), .text(iso(sunrise)), .text(iso(dhuhr)),
            .text(iso(asr)), .text(iso(maghrib)), .text(iso(isha)),
            .real(latitude), .real(longitude), .text(calculationMethod),
            .integer(isManualOverride ? 1 : 0), .text(nowText)
        ])

        guard let row = try db.query("SELECT id FROM prayer_times_cache WHERE date = ?;", [.text(date)]).first,
              let id = row.int("id") else {
            throw PrayerTimeCacheStoreError.insertFailed
        }
        return id
    }

    /// Deletes cached rows strictly after `date`, for §12.4's "invalidate
    /// future prayer_times_cache rows" — except a day flagged
    /// `isManualOverride`, which exists specifically so a user's manual
    /// correction to one future day survives an automatic recalculation.
    @discardableResult
    public func deleteFuture(after date: String) throws -> Int {
        try db.run("DELETE FROM prayer_times_cache WHERE date > ? AND isManualOverride = 0;", [.text(date)])
    }

    // MARK: - Read

    public func cachedDay(_ date: String) throws -> CachedPrayerTimes? {
        try db.query("""
        SELECT id, date, fajr, sunrise, dhuhr, asr, maghrib, isha, latitude, longitude,
               calculationMethod, isManualOverride, createdAt
        FROM prayer_times_cache WHERE date = ?;
        """, [.text(date)]).first.flatMap(rowToCached)
    }

    /// Count of cached rows from `date` onward (inclusive) — §12.3's
    /// "fewer than 7 days are cached" trigger.
    public func cachedDayCount(from date: String) throws -> Int {
        Int(try db.query("SELECT COUNT(*) as n FROM prayer_times_cache WHERE date >= ?;",
                          [.text(date)]).first?.int("n") ?? 0)
    }

    // MARK: - Private

    private func rowToCached(_ row: Row) -> CachedPrayerTimes? {
        guard let id = row.int("id"), let date = row.string("date"),
              let latitude = row.double("latitude"), let longitude = row.double("longitude"),
              let calculationMethod = row.string("calculationMethod") else { return nil }

        let names = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
        let times: [PrayerTime] = names.compactMap { name in
            row.string(name).flatMap(iso8601ToDate).map { PrayerTime(name: name, timestamp: $0) }
        }
        guard times.count == names.count else { return nil }

        return CachedPrayerTimes(
            id: id, date: date, times: times, latitude: latitude, longitude: longitude,
            calculationMethod: calculationMethod,
            isManualOverride: row.int("isManualOverride") == 1,
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum PrayerTimeCacheStoreError: Error, Sendable {
    case incompleteTimes
    case insertFailed
}
