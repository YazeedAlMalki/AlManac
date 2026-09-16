import Foundation

/// A mood log entry not yet written to storage.
public struct MoodLogDraft: Sendable {
    public var score: Int  // 1-10
    public var timestamp: Date
    public var notes: String?
    public var timezoneOffset: Int?  // offset in minutes from UTC
    public var timezoneID: String?

    public init(score: Int, timestamp: Date, notes: String? = nil, 
                timezoneOffset: Int? = nil, timezoneID: String? = nil) {
        self.score = max(1, min(10, score))  // clamp to 1-10
        self.timestamp = timestamp
        self.notes = notes
        self.timezoneOffset = timezoneOffset
        self.timezoneID = timezoneID
    }
}

/// A mood log entry read from storage.
public struct MoodLogEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let score: Int
    public let timestamp: Date
    public let logicalDay: String  // YYYY-MM-DD
    public let notes: String?
    public let readinessCycleId: Int64?
    public let createdAt: Date

    public init(id: Int64, score: Int, timestamp: Date, logicalDay: String, 
                notes: String? = nil, readinessCycleId: Int64? = nil, createdAt: Date = Date()) {
        self.id = id
        self.score = score
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.notes = notes
        self.readinessCycleId = readinessCycleId
        self.createdAt = createdAt
    }
}

/// Mood logging and querying over `mood_log`.
public struct MoodLogStore: @unchecked Sendable {
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
    public func log(_ draft: MoodLogDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO mood_log
            (timestamp, timezoneOffset, logicalDay, score, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .integer(Int64(draft.score)),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(createdAt)
        ])
        
        // Fetch the last inserted rowid
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int64("id") {
            id = fetchedID
        }
        return id
    }

    /// Update mood score for an entry.
    public func updateScore(id: Int64, to score: Int) throws {
        let clamped = max(1, min(10, score))
        try db.run("""
        UPDATE mood_log SET score = ? WHERE id = ?;
        """, [.integer(Int64(clamped)), .integer(id)])
    }

    /// Update notes for an entry.
    public func updateNotes(id: Int64, to notes: String?) throws {
        try db.run("""
        UPDATE mood_log SET notes = ? WHERE id = ?;
        """, [notes.map { SQLValue.text($0) } ?? .null, .integer(id)])
    }

    /// Link a mood log entry to a readiness cycle.
    public func linkToReadinessCycle(id: Int64, cycleId: Int64?) throws {
        try db.run("""
        UPDATE mood_log SET readinessCycleId = ? WHERE id = ?;
        """, [cycleId.map { SQLValue.integer($0) } ?? .null, .integer(id)])
    }

    // MARK: - Read

    public func entry(id: Int64) throws -> MoodLogEntry? {
        try db.query("""
        SELECT id, score, timestamp, logicalDay, notes, readinessCycleId, createdAt
        FROM mood_log WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEntry)
    }

    /// Fetch all mood logs for a logical day.
    public func logs(for logicalDay: String) throws -> [MoodLogEntry] {
        return try db.query("""
        SELECT id, score, timestamp, logicalDay, notes, readinessCycleId, createdAt
        FROM mood_log WHERE logicalDay = ?
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    /// Fetch all mood logs for a readiness cycle.
    public func logs(for cycleId: Int64) throws -> [MoodLogEntry] {
        return try db.query("""
        SELECT id, score, timestamp, logicalDay, notes, readinessCycleId, createdAt
        FROM mood_log WHERE readinessCycleId = ?
        ORDER BY timestamp;
        """, [.integer(cycleId)]).compactMap(rowToEntry)
    }

    // MARK: - Private

    private func rowToEntry(_ row: Row) -> MoodLogEntry? {
        guard let id = row.int64("id"),
              let score = row.int("score"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }
        
        return MoodLogEntry(
            id: id,
            score: score,
            timestamp: timestamp,
            logicalDay: logicalDay,
            notes: row.string("notes"),
            readinessCycleId: row.int64("readinessCycleId"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
