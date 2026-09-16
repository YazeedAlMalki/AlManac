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

    public init(metric: String, value: Double, unit: String, timestamp: Date,
                source: String, conditions: String = "unknown",
                healthKitUUID: String? = nil, timezoneOffset: Int? = nil) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
        self.conditions = conditions
        self.healthKitUUID = healthKitUUID
        self.timezoneOffset = timezoneOffset
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
    public let createdAt: Date

    public init(id: Int64, metric: String, value: Double, unit: String,
                timestamp: Date, logicalDay: String, source: String,
                conditions: String, healthKitUUID: String? = nil,
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

        try db.run("""
        INSERT INTO body_composition_measurement
            (timestamp, timezoneOffset, logicalDay, metric, value, unit, source, conditions, healthKitUUID, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .text(draft.metric),
            .real(draft.value),
            .text(draft.unit),
            .text(draft.source),
            .text(draft.conditions),
            draft.healthKitUUID.map { SQLValue.text($0) } ?? .null,
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
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, createdAt
        FROM body_composition_measurement WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToMeasurement)
    }

    /// The most recent entry for a metric, by timestamp (not insertion order).
    /// Excludes soft-deleted (e.g. HealthKit-retracted) entries.
    public func latestValue(for metric: String) throws -> BodyCompositionMeasurement? {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, createdAt
        FROM body_composition_measurement WHERE metric = ? AND deletedAt IS NULL
        ORDER BY timestamp DESC LIMIT 1;
        """, [.text(metric)]).first.flatMap(rowToMeasurement)
    }

    /// History for a metric within a logical-day range, ordered by timestamp — for charting.
    /// Excludes soft-deleted (e.g. HealthKit-retracted) entries.
    public func records(metric: String, from: String, to: String) throws -> [BodyCompositionMeasurement] {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, conditions, healthKitUUID, createdAt
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
