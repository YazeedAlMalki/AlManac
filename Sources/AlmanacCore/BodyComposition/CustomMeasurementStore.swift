import Foundation

/// An owner-defined circumference measurement (e.g. "waist", "chest").
public struct CustomMeasurementDefinition: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    public let unit: String
    public let createdAt: Date

    public init(id: Int64, name: String, unit: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.unit = unit
        self.createdAt = createdAt
    }
}

/// A custom measurement log entry not yet written to storage.
public struct CustomMeasurementLogDraft: Sendable {
    public var definitionId: Int64
    public var value: Double
    public var timestamp: Date
    public var notes: String?

    public init(definitionId: Int64, value: Double, timestamp: Date, notes: String? = nil) {
        self.definitionId = definitionId
        self.value = value
        self.timestamp = timestamp
        self.notes = notes
    }
}

/// A custom measurement log entry read from storage.
public struct CustomMeasurementLogEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let definitionId: Int64
    public let value: Double
    public let timestamp: Date
    public let logicalDay: String
    public let notes: String?
    public let createdAt: Date

    public init(id: Int64, definitionId: Int64, value: Double, timestamp: Date,
                logicalDay: String, notes: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.definitionId = definitionId
        self.value = value
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Owner-definable circumference measurements — definitions and their logged
/// values, over `custom_measurement_definition` / `custom_measurement_log`.
public struct CustomMeasurementStore: @unchecked Sendable {
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

    // MARK: - Definitions

    @discardableResult
    public func createDefinition(name: String, unit: String) throws -> Int64 {
        try db.run("""
        INSERT INTO custom_measurement_definition (name, unit, createdAt)
        VALUES (?, ?, ?);
        """, [.text(name), .text(unit), .text(nowText)])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw CustomMeasurementStoreError.insertFailed
        }
        return id
    }

    public func definition(id: Int64) throws -> CustomMeasurementDefinition? {
        try db.query("""
        SELECT id, name, unit, createdAt FROM custom_measurement_definition WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToDefinition)
    }

    public func definitions() throws -> [CustomMeasurementDefinition] {
        try db.query("""
        SELECT id, name, unit, createdAt FROM custom_measurement_definition ORDER BY name;
        """).compactMap(rowToDefinition)
    }

    // MARK: - Log

    @discardableResult
    public func log(_ draft: CustomMeasurementLogDraft, logicalDay: String) throws -> Int64 {
        try db.run("""
        INSERT INTO custom_measurement_log (definitionId, timestamp, logicalDay, value, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?);
        """, [
            .integer(draft.definitionId),
            .text(iso(draft.timestamp)),
            .text(logicalDay),
            .real(draft.value),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(nowText)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw CustomMeasurementStoreError.insertFailed
        }
        return id
    }

    /// History for a definition within a logical-day range, ordered by timestamp — for charting.
    public func history(definitionId: Int64, from: String, to: String) throws -> [CustomMeasurementLogEntry] {
        try db.query("""
        SELECT id, definitionId, value, timestamp, logicalDay, notes, createdAt
        FROM custom_measurement_log WHERE definitionId = ? AND logicalDay >= ? AND logicalDay < ?
        ORDER BY timestamp;
        """, [.integer(definitionId), .text(from), .text(to)]).compactMap(rowToLogEntry)
    }

    // MARK: - Private

    private func rowToDefinition(_ row: Row) -> CustomMeasurementDefinition? {
        guard let id = row.int("id"),
              let name = row.string("name"),
              let unit = row.string("unit") else { return nil }
        return CustomMeasurementDefinition(
            id: id, name: name, unit: unit,
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date())
    }

    private func rowToLogEntry(_ row: Row) -> CustomMeasurementLogEntry? {
        guard let id = row.int("id"),
              let definitionId = row.int("definitionId"),
              let value = row.double("value"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }
        return CustomMeasurementLogEntry(
            id: id, definitionId: definitionId, value: value, timestamp: timestamp,
            logicalDay: logicalDay, notes: row.string("notes"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date())
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum CustomMeasurementStoreError: Error, Sendable {
    case insertFailed
}
