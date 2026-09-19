import Foundation

/// BRD §6.3's 8-level urination color chart, 1 (pale) through 8 (dark brown).
public enum UrinationColorGrade: Int, Sendable, Codable, CaseIterable {
    case grade1 = 1, grade2, grade3, grade4, grade5, grade6, grade7, grade8
}

/// A urination log entry not yet written to storage.
public struct UrinationDraft: Sendable {
    public var timestamp: Date
    public var colorGrade: UrinationColorGrade
    public var notes: String?

    public init(timestamp: Date, colorGrade: UrinationColorGrade, notes: String? = nil) {
        self.timestamp = timestamp
        self.colorGrade = colorGrade
        self.notes = notes
    }
}

/// A urination log entry read from storage.
public struct UrinationEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let logicalDay: String
    public let timestamp: Date
    public let colorGrade: UrinationColorGrade
    public let notes: String?
    /// Set by a future, clinician-approved classifier — see Migration032.
    public let clinicianEscalationLevel: String?
    public let createdAt: Date
}

/// Urination logging and querying over `urination_record`.
public struct UrinationStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
    private func date(from text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    @discardableResult
    public func log(_ draft: UrinationDraft, logicalDay: String) throws -> Int64 {
        try db.run("""
        INSERT INTO urination_record (logicalDay, timestamp, colorGrade, notes, createdAt)
        VALUES (?, ?, ?, ?, ?);
        """, [
            .text(logicalDay),
            .text(iso(draft.timestamp)),
            .integer(Int64(draft.colorGrade.rawValue)),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(iso(clock.now))
        ])
        return try db.query("SELECT last_insert_rowid() AS id;").first?.int("id") ?? 0
    }

    public func entry(id: Int64) throws -> UrinationEntry? {
        try db.query("""
        SELECT id, logicalDay, timestamp, colorGrade, notes, clinicianEscalationLevel, createdAt
        FROM urination_record WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEntry)
    }

    public func logs(for logicalDay: String) throws -> [UrinationEntry] {
        try db.query("""
        SELECT id, logicalDay, timestamp, colorGrade, notes, clinicianEscalationLevel, createdAt
        FROM urination_record WHERE logicalDay = ? ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    private func rowToEntry(_ row: Row) -> UrinationEntry? {
        guard let id = row.int("id"),
              let logicalDay = row.string("logicalDay"),
              let timestampText = row.string("timestamp"),
              let timestamp = date(from: timestampText),
              let colorRaw = row.int("colorGrade"),
              let colorGrade = UrinationColorGrade(rawValue: Int(colorRaw)) else { return nil }
        return UrinationEntry(
            id: id,
            logicalDay: logicalDay,
            timestamp: timestamp,
            colorGrade: colorGrade,
            notes: row.string("notes"),
            clinicianEscalationLevel: row.string("clinicianEscalationLevel"),
            createdAt: row.string("createdAt").flatMap(date(from:)) ?? Date()
        )
    }
}
