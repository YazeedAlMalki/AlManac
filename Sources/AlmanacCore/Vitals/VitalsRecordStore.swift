import Foundation

/// A vitals record not yet written to storage.
public struct VitalsRecordDraft: Sendable {
    public var metric: String  // e.g., "rhr", "hrv", "spo2", "temp", "bp_systolic", "bp_diastolic"
    public var value: Double
    public var unit: String  // e.g., "bpm", "%", "mmHg"
    public var timestamp: Date
    public var source: String  // e.g., "healthkit", "manual", "device"
    public var healthKitUUID: String?  // if from HealthKit, the UUID
    public var timezoneOffset: Int?  // offset in minutes from UTC
    public var timezoneID: String?

    public init(metric: String, value: Double, unit: String, timestamp: Date,
                source: String, healthKitUUID: String? = nil, 
                timezoneOffset: Int? = nil, timezoneID: String? = nil) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.timezoneOffset = timezoneOffset
        self.timezoneID = timezoneID
    }
}

/// A vitals record read from storage.
public struct VitalsRecord: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let metric: String
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let logicalDay: String  // YYYY-MM-DD
    public let source: String
    public let healthKitUUID: String?
    public let createdAt: Date

    public init(id: Int64, metric: String, value: Double, unit: String, 
                timestamp: Date, logicalDay: String, source: String,
                healthKitUUID: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.createdAt = createdAt
    }
}

/// Vitals record logging and querying over `vitals_record`.
public struct VitalsRecordStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let zone: ZoneContext

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.zone = zone
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    @discardableResult
    public func record(_ draft: VitalsRecordDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO vitals_record
            (timestamp, timezoneOffset, logicalDay, metric, value, unit, source, healthKitUUID, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .text(draft.metric),
            .real(draft.value),
            .text(draft.unit),
            .text(draft.source),
            draft.healthKitUUID.map { SQLValue.text($0) } ?? .null,
            .text(createdAt)
        ])
        
        // Fetch the last inserted rowid
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int64("id") {
            id = fetchedID
        }
        return id
    }

    // MARK: - Read

    public func record(id: Int64) throws -> VitalsRecord? {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToRecord)
    }

    /// Fetch all vitals for a given logical day.
    public func records(for logicalDay: String) throws -> [VitalsRecord] {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE logicalDay = ?
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToRecord)
    }

    /// Fetch all records for a specific metric.
    public func records(metric: String, from: String, to: String) throws -> [VitalsRecord] {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ? AND logicalDay >= ? AND logicalDay < ?
        ORDER BY timestamp;
        """, [.text(metric), .text(from), .text(to)]).compactMap(rowToRecord)
    }

    /// Fetch the latest value for a specific metric.
    public func latestValue(for metric: String) throws -> VitalsRecord? {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ?
        ORDER BY timestamp DESC LIMIT 1;
        """, [.text(metric)]).first.flatMap(rowToRecord)
    }

    /// Fetch vitals for a range of logical days by metric.
    public func records(metric: String, logicalDays: [String]) throws -> [VitalsRecord] {
        guard !logicalDays.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: logicalDays.count).joined(separator: ",")
        let values: [SQLValue] = [.text(metric)] + logicalDays.map { SQLValue.text($0) }
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ? AND logicalDay IN (\(placeholders))
        ORDER BY timestamp;
        """, values).compactMap(rowToRecord)
    }

    // MARK: - Private

    private func rowToRecord(_ row: Row) -> VitalsRecord? {
        guard let id = row.int64("id"),
              let metric = row.string("metric"),
              let value = row.double("value"),
              let unit = row.string("unit"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let source = row.string("source"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }
        
        return VitalsRecord(
            id: id,
            metric: metric,
            value: value,
            unit: unit,
            timestamp: timestamp,
            logicalDay: logicalDay,
            source: source,
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
