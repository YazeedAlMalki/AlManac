import Foundation

/// BRD §6.3's 8-level urination color chart, 1 (pale) through 8 (dark brown).
public enum UrinationColorGrade: Int, Sendable, Codable, CaseIterable {
    case grade1 = 1, grade2, grade3, grade4, grade5, grade6, grade7, grade8

    /// "Grade 4", and the two ends the spec actually names.
    ///
    /// BRD §6.3 asks for an "8-level chart" without giving it, and the only two
    /// points this repository can state are the ones the type's own doc comment
    /// already states: 1 is pale and 8 is dark brown. **Grades 2 to 7 are left
    /// as numbers rather than given descriptions.** A plausible-sounding ladder
    /// of eight colour descriptions would be eight clinical claims written by
    /// this codebase, and the BRD's own advisory section is explicitly held back
    /// for clinician review — inventing the middle of the chart would be doing
    /// the one thing that gate exists to prevent, a clause earlier and in a
    /// smaller font.
    public var displayName: String {
        switch self {
        case .grade1: return "Grade 1 — pale"
        case .grade8: return "Grade 8 — dark brown"
        default: return "Grade \(rawValue)"
        }
    }

    /// The grade announced as a whole, per BRD §6.3's "numeric grades + text +
    /// VoiceOver" and its "never rely on colour alone".
    public var accessibilityLabel: String { "Colour grade \(rawValue) of 8, \(displayName)" }
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

    /// Entries across a logical-day range, newest first — `DigestionStore`'s
    /// range query, for the same reason: one query rather than one per day.
    public func logs(from: String, to: String) throws -> [UrinationEntry] {
        try db.query("""
        SELECT id, logicalDay, timestamp, colorGrade, notes, clinicianEscalationLevel, createdAt
        FROM urination_record WHERE logicalDay >= ? AND logicalDay < ?
        ORDER BY timestamp DESC;
        """, [.text(from), .text(to)]).compactMap(rowToEntry)
    }

    /// Removes an entry outright; see `DigestionStore.delete(id:)` for why this
    /// is a hard delete rather than a soft one.
    public func delete(id: Int64) throws {
        try db.run("DELETE FROM urination_record WHERE id = ?;", [.integer(id)])
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
