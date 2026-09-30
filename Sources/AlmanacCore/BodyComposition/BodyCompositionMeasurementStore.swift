import Foundation

/// A body composition measurement not yet written to storage.
public struct BodyCompositionMeasurementDraft: Sendable {
    public var metric: String  // weight | body_fat_pct | lean_mass_kg | skeletal_muscle_kg | visceral_rating
    public var value: Double
    public var unit: String  // kg | pct | rating
    public var timestamp: Date
    public var source: String  // apple_health | inbody | smart_scale | manual
    public var conditions: String  // fasted | non_fasted | unknown
    public var healthKitUUID: String?
    public var timezoneOffset: Int?  // offset in minutes from UTC
    public var timezoneIdentifier: String?

    public init(metric: String, value: Double, unit: String, timestamp: Date,
                source: String, conditions: String = "unknown",
                healthKitUUID: String? = nil, timezoneOffset: Int? = nil,
                timezoneIdentifier: String? = nil) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
        self.conditions = conditions
        self.healthKitUUID = healthKitUUID
        self.timezoneOffset = timezoneOffset
        self.timezoneIdentifier = timezoneIdentifier
    }
}

/// A body composition measurement read from storage.
public struct BodyCompositionMeasurement: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let metric: String
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let logicalDay: String  // YYYY-MM-DD
    public let source: String
    public let conditions: String
    public let healthKitUUID: String?
    public let timezoneOffset: Int?
    public let timezoneIdentifier: String?
    public let createdAt: Date

    public init(id: Int64, metric: String, value: Double, unit: String,
                timestamp: Date, logicalDay: String, source: String,
                conditions: String, healthKitUUID: String? = nil,
                timezoneOffset: Int? = nil, timezoneIdentifier: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.source = source
        self.conditions = conditions
        self.healthKitUUID = healthKitUUID
        self.timezoneOffset = timezoneOffset
        self.timezoneIdentifier = timezoneIdentifier
        self.createdAt = createdAt
    }
}

/// Body composition logging and querying over `body_composition_measurement`.
///
/// `weight` lives here, not in `vitals_record` — see
/// `docs/architecture/spec-reconciliation.md` §7 for why the two collided and
/// how it was resolved.
public struct BodyCompositionMeasurementStore: @unchecked Sendable {
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

    @discardableResult
    public func log(_ draft: BodyCompositionMeasurementDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        // A manual row of a metric HealthKit can hold is queued for write-back
        // by flagging it here, which is the only writer of the column. Rows of
        // `skeletal_muscle_kg` / `visceral_rating` are never flagged: there is
        // no HealthKit type to send them to, so a flag would be a row that can
        // never drain. See Migration018's comment and `BodyCompositionWriteback`.
        let pendingWrite = draft.source == "manual"
            && BodyCompositionMeasurementHealthBridge.healthKitDomain(forMetric: draft.metric) != nil

        try db.run("""
        INSERT INTO body_composition_measurement
            (timestamp, timezoneOffset, timezoneIdentifier, logicalDay, metric, value, unit, source, conditions, healthKitUUID, pendingHealthKitWrite, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.timezoneIdentifier.map { SQLValue.text($0) } ?? .null,
            .text(logicalDay),
            .text(draft.metric),
            .real(draft.value),
            .text(draft.unit),
            .text(draft.source),
            .text(draft.conditions),
            draft.healthKitUUID.map { SQLValue.text($0) } ?? .null,
            .integer(pendingWrite ? 1 : 0),
            .text(createdAt)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw BodyCompositionMeasurementStoreError.insertFailed
        }
        return id
    }

    // MARK: - Read

    public func measurement(id: Int64) throws -> BodyCompositionMeasurement? {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, timezoneOffset, timezoneIdentifier, createdAt
        FROM body_composition_measurement WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToMeasurement)
    }

    /// The most recent entry for a metric, by timestamp (not insertion order).
    /// Excludes soft-deleted (e.g. HealthKit-retracted) entries.
    public func latestValue(for metric: String) throws -> BodyCompositionMeasurement? {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, timezoneOffset, timezoneIdentifier, createdAt
        FROM body_composition_measurement WHERE metric = ? AND deletedAt IS NULL
        ORDER BY timestamp DESC LIMIT 1;
        """, [.text(metric)]).first.flatMap(rowToMeasurement)
    }

    /// Every reading for any mix of metrics within a logical-day range.
    ///
    /// **The one read a card grid costs.** The grid shows five metrics, and the
    /// obvious implementation is five calls to `records(metric:from:to:)` — five
    /// queries to draw one screen, and five chances for the five cards to be
    /// looking at slightly different data if a write lands between them. This
    /// returns the whole window in one row-set and the caller groups it.
    ///
    /// `metrics` is filtered in SQL rather than in Swift on purpose. The filter
    /// matters when the window is wide and the table holds years: body
    /// composition readings accumulate forever, and pulling every row since the
    /// app was installed to hand back the last thirty days is the kind of "works,
    /// but why is this slow" that only shows up on a device with two years of
    /// readings. Pass `nil` for every metric rather than spelling out all five.
    public func records(forMetrics metrics: [String]? = nil,
                        from: String,
                        to: String) throws -> [BodyCompositionMeasurement] {
        let clause = (metrics?.isEmpty == false)
            ? "AND metric IN (\(Self.placeholders(metrics!.count)))"
            : ""
        let parameters: [SQLValue] = [.text(from), .text(to)] + (metrics ?? []).map { .text($0) }
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, timezoneOffset, timezoneIdentifier, createdAt
        FROM body_composition_measurement
        WHERE logicalDay >= ? AND logicalDay < ? AND deletedAt IS NULL \(clause)
        ORDER BY timestamp DESC;
        """, parameters).compactMap(rowToMeasurement)
    }

    /// The most recent reading for each of `metrics`, in one read.
    ///
    /// Separate from `records(forMetrics:from:to:)` because a card wants *the
    /// latest value* and a sparkline wants *the series*, and the two want
    /// different queries. A per-metric `GROUP BY` subquery does the latest-1
    /// pick in SQLite, which is a different plan from scanning the window — and
    /// the card grid is the screen that opens on a cold database, so it gets the
    /// cheaper of the two.
    ///
    /// A missing key means "no reading", not "not asked about" — the caller
    /// always asks for the full set, so the difference is not one it needs to
    /// draw. That is why the return type is not `[String: BodyCompositionMeasurement?]`
    /// and why this method does not try to insert nil placeholders.
    public func latestPerMetric(_ metrics: [String] = BodyMetric.allCases.map(\.id)) throws -> [String: BodyCompositionMeasurement] {
        let placeholders = Self.placeholders(metrics.count)
        let rows = try db.query("""
        SELECT m.id, m.metric, m.value, m.unit, m.timestamp, m.logicalDay, m.source,
               m.conditions, m.healthKitUUID, m.timezoneOffset, m.timezoneIdentifier, m.createdAt
        FROM body_composition_measurement m
        JOIN (
            SELECT metric, MAX(timestamp) AS latest
            FROM body_composition_measurement
            WHERE deletedAt IS NULL AND metric IN (\(placeholders))
            GROUP BY metric
        ) newest
          ON m.metric = newest.metric AND m.timestamp = newest.latest
        WHERE m.deletedAt IS NULL
        ORDER BY m.timestamp DESC;
        """, metrics.map { .text($0) })

        var out: [String: BodyCompositionMeasurement] = [:]
        for row in rows {
            guard let measurement = rowToMeasurement(row) else { continue }
            // Two rows can share a timestamp — a scale and HealthKit recording the
            // same reading in the same second. `ORDER BY timestamp DESC` alone
            // leaves which one wins to the query plan, so the tie is broken here:
            // highest id is the later insert, which is the one the person just
            // made.
            if let existing = out[measurement.metric], existing.timestamp == measurement.timestamp,
               existing.id > measurement.id { continue }
            out[measurement.metric] = measurement
        }
        return out
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    /// History for a metric within a logical-day range, ordered by timestamp — for charting.
    /// Excludes soft-deleted (e.g. HealthKit-retracted) entries.
    public func records(metric: String, from: String, to: String) throws -> [BodyCompositionMeasurement] {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, timezoneOffset, timezoneIdentifier, createdAt
        FROM body_composition_measurement WHERE metric = ? AND logicalDay >= ? AND logicalDay < ? AND deletedAt IS NULL
        ORDER BY timestamp;
        """, [.text(metric), .text(from), .text(to)]).compactMap(rowToMeasurement)
    }

    // MARK: - Private

    private func rowToMeasurement(_ row: Row) -> BodyCompositionMeasurement? {
        guard let id = row.int("id"),
              let metric = row.string("metric"),
              let value = row.double("value"),
              let unit = row.string("unit"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let source = row.string("source"),
              let conditions = row.string("conditions"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }

        return BodyCompositionMeasurement(
            id: id,
            metric: metric,
            value: value,
            unit: unit,
            timestamp: timestamp,
            logicalDay: logicalDay,
            source: source,
            conditions: conditions,
            healthKitUUID: row.string("healthKitUUID"),
            timezoneOffset: row.int("timezoneOffset").map(Int.init)
                ?? row.string("timezoneOffset").flatMap(Int.init),
            timezoneIdentifier: row.string("timezoneIdentifier"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum BodyCompositionMeasurementStoreError: Error, Sendable {
    case insertFailed
}
