import Foundation

/// A supplement adherence entry not yet written to storage.
public struct SupplementLogDraft: Sendable {
    public var planId: Int64
    public var timestamp: Date
    public var taken: Bool
    public var notes: String?

    public init(planId: Int64, timestamp: Date, taken: Bool = true, notes: String? = nil) {
        self.planId = planId
        self.timestamp = timestamp
        self.taken = taken
        self.notes = notes
    }
}

/// A supplement adherence entry read from storage.
public struct SupplementLogEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let planId: Int64
    public let timestamp: Date
    public let logicalDay: String
    public let taken: Bool
    public let notes: String?
    public let createdAt: Date

    public init(id: Int64, planId: Int64, timestamp: Date, logicalDay: String,
                taken: Bool = true, notes: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.planId = planId
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.taken = taken
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Supplement adherence logging over `supplement_log`.
public struct SupplementLogStore: @unchecked Sendable {
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

    @discardableResult
    public func log(_ draft: SupplementLogDraft, logicalDay: String) throws -> Int64 {
        try db.run("""
        INSERT INTO supplement_log (planId, timestamp, logicalDay, taken, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?);
        """, [
            .integer(draft.planId),
            .text(iso(draft.timestamp)),
            .text(logicalDay),
            .integer(draft.taken ? 1 : 0),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(nowText)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw SupplementLogStoreError.insertFailed
        }
        return id
    }

    /// Adherence entries for a logical day, across all plans.
    public func entries(for logicalDay: String) throws -> [SupplementLogEntry] {
        try db.query("""
        SELECT id, planId, timestamp, logicalDay, taken, notes, createdAt
        FROM supplement_log WHERE logicalDay = ?
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    /// Adherence entries for one plan within a logical-day range.
    public func entries(planId: Int64, from: String, to: String) throws -> [SupplementLogEntry] {
        try db.query("""
        SELECT id, planId, timestamp, logicalDay, taken, notes, createdAt
        FROM supplement_log WHERE planId = ? AND logicalDay >= ? AND logicalDay < ?
        ORDER BY timestamp;
        """, [.integer(planId), .text(from), .text(to)]).compactMap(rowToEntry)
    }

    private func rowToEntry(_ row: Row) -> SupplementLogEntry? {
        guard let id = row.int("id"),
              let planId = row.int("planId"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }
        return SupplementLogEntry(
            id: id, planId: planId, timestamp: timestamp, logicalDay: logicalDay,
            taken: (row.int("taken") ?? 1) != 0, notes: row.string("notes"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date())
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum SupplementLogStoreError: Error, Sendable {
    case insertFailed
}
