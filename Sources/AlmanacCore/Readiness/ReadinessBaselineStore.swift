import Foundation

/// A `readiness_baseline` row read from storage (§5.23).
public struct StoredReadinessBaseline: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let type: ReadinessBaselineType
    /// Non-nil exactly when `type == .shiftSpecific` — the column is nullable in
    /// §5.23 and there is nothing else for it to say.
    public let shiftType: ShiftType?
    public let validDayCount: Int
    public let rollingWindowDays: Int
    public let averageSleepDurationMinutes: Double?
    public let averageRestingHeartRate: Double?
    public let averageHRV: Double?
    public let averageSoreness: Double?
    public let averageMood: Double?
    public let windowStartDate: String
    public let windowEndDate: String
    public let formulaVersion: String
    public let updatedAt: Date
}

/// Persists the baselines `ReadinessBaselineService` computes into
/// `readiness_baseline` (§5.23), which Migration014 created and which nothing
/// had ever written to until now.
///
/// **Idempotent by replacement, not by a unique index.** §5.23's table has no
/// constraint on `(baselineType, shiftType)`, so `upsert` is delete-then-insert
/// inside one transaction. A unique index would need a new migration and a
/// migration that only exists to make an upsert tidier is not worth a schema
/// change on a table that has never shipped. The transaction is what makes it
/// safe: a reader never sees a window with no row.
///
/// **Deliberately not read back by the scoring path.** The service computes
/// from the same stores the row summarises, so reading the row back would mean
/// a day's score could be measured against a snapshot that a later pass has not
/// yet refreshed — a stale baseline is worse than a recomputed one, and §9.8
/// says "updated daily after readiness calculation" rather than "read from
/// storage". The row is the record, and `ReadinessBaseline` is the working
/// value.
public struct ReadinessBaselineStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: clock.now)
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// Replaces the stored row for `type` (and `shiftType`, when the type is
    /// shift-specific) with one summarising `baseline` over
    /// `windowStartDate...windowEndDate`.
    ///
    /// A resolution with no window — nothing qualified — writes nothing rather
    /// than a row with empty bounds, so "we have no baseline" stays
    /// distinguishable from "our baseline is empty".
    public func save(_ baseline: ReadinessBaseline, type: ReadinessBaselineType,
                     shiftType: ShiftType? = nil, windowStartDate: String,
                     windowEndDate: String, rollingWindowDays: Int) throws {
        guard type == .shiftSpecific ? shiftType != nil : true else {
            throw ReadinessBaselineStoreError.shiftSpecificBaselineNeedsAShiftType
        }
        let now = nowText
        try db.transaction {
            try db.run("""
            DELETE FROM readiness_baseline WHERE baselineType = ?
                AND ((shiftType IS NULL AND ? IS NULL) OR shiftType = ?);
            """, [.text(type.rawValue),
                  shiftType.map { SQLValue.text($0.rawValue) } ?? .null,
                  shiftType.map { SQLValue.text($0.rawValue) } ?? .null])

            try db.run("""
            INSERT INTO readiness_baseline
                (baselineType, shiftType, validDayCount, rollingWindowDays,
                 avgSleepDurationMin, avgRHR, avgHRV, avgSoreness, avgMood,
                 windowStartDate, windowEndDate, formulaVersion, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(type.rawValue),
                shiftType.map { SQLValue.text($0.rawValue) } ?? .null,
                .integer(Int64(baseline.validDayCount)),
                .integer(Int64(rollingWindowDays)),
                .null,
                baseline.restingHeartRate.map { SQLValue.real($0) } ?? .null,
                baseline.hrv.map { SQLValue.real($0) } ?? .null,
                .null,
                .null,
                .text(windowStartDate),
                .text(windowEndDate),
                .text(ReadinessFormula.version),
                .text(now)
            ])
        }
    }

    /// The stored row for one baseline type, newest write wins if a caller ever
    /// managed to leave two.
    public func baseline(type: ReadinessBaselineType, shiftType: ShiftType? = nil) throws -> StoredReadinessBaseline? {
        try db.query("""
        SELECT id, baselineType, shiftType, validDayCount, rollingWindowDays,
               avgSleepDurationMin, avgRHR, avgHRV, avgSoreness, avgMood,
               windowStartDate, windowEndDate, formulaVersion, updatedAt
        FROM readiness_baseline
        WHERE baselineType = ?
          AND ((shiftType IS NULL AND ? IS NULL) OR shiftType = ?)
        ORDER BY updatedAt DESC LIMIT 1;
        """, [
            .text(type.rawValue),
            shiftType.map { SQLValue.text($0.rawValue) } ?? .null,
            shiftType.map { SQLValue.text($0.rawValue) } ?? .null
        ]).first.flatMap(rowToBaseline)
    }

    public func allBaselines() throws -> [StoredReadinessBaseline] {
        try db.query("""
        SELECT id, baselineType, shiftType, validDayCount, rollingWindowDays,
               avgSleepDurationMin, avgRHR, avgHRV, avgSoreness, avgMood,
               windowStartDate, windowEndDate, formulaVersion, updatedAt
        FROM readiness_baseline ORDER BY baselineType, shiftType;
        """).compactMap(rowToBaseline)
    }

    private func rowToBaseline(_ row: Row) -> StoredReadinessBaseline? {
        guard let id = row.int("id"),
              let typeRaw = row.string("baselineType"),
              let type = ReadinessBaselineType(rawValue: typeRaw),
              let validDayCount = row.int("validDayCount"),
              let rollingWindowDays = row.int("rollingWindowDays"),
              let windowStartDate = row.string("windowStartDate"),
              let windowEndDate = row.string("windowEndDate"),
              let formulaVersion = row.string("formulaVersion"),
              let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) else { return nil }

        return StoredReadinessBaseline(
            id: id, type: type,
            shiftType: row.string("shiftType").flatMap(ShiftType.init(rawValue:)),
            validDayCount: Int(validDayCount), rollingWindowDays: Int(rollingWindowDays),
            averageSleepDurationMinutes: row.double("avgSleepDurationMin"),
            averageRestingHeartRate: row.double("avgRHR"),
            averageHRV: row.double("avgHRV"),
            averageSoreness: row.double("avgSoreness"),
            averageMood: row.double("avgMood"),
            windowStartDate: windowStartDate, windowEndDate: windowEndDate,
            formulaVersion: formulaVersion, updatedAt: updatedAt)
    }
}

public enum ReadinessBaselineStoreError: Error, Sendable, Equatable {
    case shiftSpecificBaselineNeedsAShiftType
}
