import Foundation

/// A soreness log entry not yet written to storage.
public struct SorenessLogDraft: Sendable {
    public var overallScore: Int  // 1-10
    public var timestamp: Date
    public var bodyAreas: [String]  // list of affected body area names
    public var notes: String?
    public var timezoneOffset: Int?  // offset in minutes from UTC
    public var timezoneID: String?

    public init(overallScore: Int, timestamp: Date, bodyAreas: [String] = [],
                notes: String? = nil, timezoneOffset: Int? = nil, timezoneID: String? = nil) {
        self.overallScore = max(1, min(10, overallScore))  // clamp to 1-10
        self.timestamp = timestamp
        self.bodyAreas = bodyAreas
        self.notes = notes
        self.timezoneOffset = timezoneOffset
        self.timezoneID = timezoneID
    }
}

/// A soreness log entry read from storage.
public struct SorenessLogEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let overallScore: Int
    public let timestamp: Date
    public let logicalDay: String  // YYYY-MM-DD
    public let bodyAreas: [String]  // stored as JSON array
    public let notes: String?
    public let readinessCycleId: Int64?
    public let createdAt: Date

    public init(id: Int64, overallScore: Int, timestamp: Date, logicalDay: String,
                bodyAreas: [String] = [], notes: String? = nil, 
                readinessCycleId: Int64? = nil, createdAt: Date = Date()) {
        self.id = id
        self.overallScore = overallScore
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.bodyAreas = bodyAreas
        self.notes = notes
        self.readinessCycleId = readinessCycleId
        self.createdAt = createdAt
    }
}

/// Soreness logging and querying over `soreness_log`.
public struct SorenessLogStore: @unchecked Sendable {
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
    public func log(_ draft: SorenessLogDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        
        let jsonData = try JSONEncoder().encode(draft.bodyAreas)
        let bodyAreasJSON = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO soreness_log
            (timestamp, timezoneOffset, logicalDay, overallScore, bodyAreas, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .integer(Int64(draft.overallScore)),
            .text(bodyAreasJSON),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(createdAt)
        ])
        
        // Fetch the last inserted rowid
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    /// Update overall soreness score for an entry.
    public func updateScore(id: Int64, to score: Int) throws {
        let clamped = max(1, min(10, score))
        try db.run("""
        UPDATE soreness_log SET overallScore = ? WHERE id = ?;
        """, [.integer(Int64(clamped)), .integer(id)])
    }

    /// Update body areas for an entry.
    public func updateBodyAreas(id: Int64, to bodyAreas: [String]) throws {
        let jsonData = try JSONEncoder().encode(bodyAreas)
        let bodyAreasJSON = String(data: jsonData, encoding: .utf8) ?? "[]"
        try db.run("""
        UPDATE soreness_log SET bodyAreas = ? WHERE id = ?;
        """, [.text(bodyAreasJSON), .integer(id)])
    }

    /// Update notes for an entry.
    public func updateNotes(id: Int64, to notes: String?) throws {
        try db.run("""
        UPDATE soreness_log SET notes = ? WHERE id = ?;
        """, [notes.map { SQLValue.text($0) } ?? .null, .integer(id)])
    }

    /// Link a soreness log entry to a readiness cycle.
    public func linkToReadinessCycle(id: Int64, cycleId: Int64?) throws {
        try db.run("""
        UPDATE soreness_log SET readinessCycleId = ? WHERE id = ?;
        """, [cycleId.map { SQLValue.integer($0) } ?? .null, .integer(id)])
    }

    // MARK: - Read

    public func entry(id: Int64) throws -> SorenessLogEntry? {
        try db.query("""
        SELECT id, overallScore, timestamp, logicalDay, bodyAreas, notes, readinessCycleId, createdAt
        FROM soreness_log WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEntry)
    }

    /// Fetch all soreness logs for a logical day.
    public func logs(for logicalDay: String) throws -> [SorenessLogEntry] {
        return try db.query("""
        SELECT id, overallScore, timestamp, logicalDay, bodyAreas, notes, readinessCycleId, createdAt
        FROM soreness_log WHERE logicalDay = ?
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    /// Fetch all soreness logs for a readiness cycle.
    public func logs(for cycleId: Int64) throws -> [SorenessLogEntry] {
        return try db.query("""
        SELECT id, overallScore, timestamp, logicalDay, bodyAreas, notes, readinessCycleId, createdAt
        FROM soreness_log WHERE readinessCycleId = ?
        ORDER BY timestamp;
        """, [.integer(cycleId)]).compactMap(rowToEntry)
    }

    // MARK: - Private

    private func rowToEntry(_ row: Row) -> SorenessLogEntry? {
        guard let id = row.int("id"),
              let score = row.int("overallScore"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }
        
        let bodyAreas: [String] = (row.string("bodyAreas") ?? "[]").decodeJSON() ?? []
        
        return SorenessLogEntry(
            id: id,
            overallScore: Int(score),
            timestamp: timestamp,
            logicalDay: logicalDay,
            bodyAreas: bodyAreas,
            notes: row.string("notes"),
            readinessCycleId: row.int("readinessCycleId"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

// MARK: - JSON Helper Extension

private extension String {
    func decodeJSON<T: Decodable>() -> T? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
