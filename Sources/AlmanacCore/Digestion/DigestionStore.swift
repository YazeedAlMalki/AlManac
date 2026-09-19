import Foundation

/// Bristol Stool Scale, Type 1 (separate hard lumps) through Type 7 (liquid,
/// no solid pieces) — BRD §6.3's reference scale.
///
/// Presentation (picker vs. educational images/text) is a UI decision for
/// the Slice 9 handoff to settle; this is only the fixed domain value.
public enum BristolType: Int, Sendable, Codable, CaseIterable {
    case type1 = 1, type2, type3, type4, type5, type6, type7
}

/// A bowel movement log entry not yet written to storage.
public struct BowelMovementDraft: Sendable {
    public var timestamp: Date
    public var bristolType: BristolType
    public var color: String?
    public var bloodPresent: Bool
    public var bloodAmount: String?
    public var gas: Bool?
    public var urgency: Int?
    public var notes: String?

    public init(timestamp: Date, bristolType: BristolType, color: String? = nil,
                bloodPresent: Bool = false, bloodAmount: String? = nil,
                gas: Bool? = nil, urgency: Int? = nil, notes: String? = nil) {
        self.timestamp = timestamp
        self.bristolType = bristolType
        self.color = color
        self.bloodPresent = bloodPresent
        self.bloodAmount = bloodAmount
        self.gas = gas
        self.urgency = urgency
        self.notes = notes
    }
}

/// A bowel movement log entry read from storage.
public struct BowelMovementEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let logicalDay: String
    public let timestamp: Date
    public let bristolType: BristolType
    public let color: String?
    public let bloodPresent: Bool
    public let bloodAmount: String?
    public let gas: Bool?
    public let urgency: Int?
    public let notes: String?
    /// Set by a future, clinician-approved classifier. Nothing in this store
    /// computes it — see Migration032's doc comment.
    public let clinicianEscalationLevel: String?
    public let createdAt: Date
}

/// Bowel-movement logging and querying over `bowel_movement`.
public struct DigestionStore: @unchecked Sendable {
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
    public func log(_ draft: BowelMovementDraft, logicalDay: String) throws -> Int64 {
        try db.run("""
        INSERT INTO bowel_movement
            (logicalDay, timestamp, bristolType, color, bloodPresent, bloodAmount, gas, urgency, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(logicalDay),
            .text(iso(draft.timestamp)),
            .integer(Int64(draft.bristolType.rawValue)),
            draft.color.map { SQLValue.text($0) } ?? .null,
            .integer(draft.bloodPresent ? 1 : 0),
            draft.bloodAmount.map { SQLValue.text($0) } ?? .null,
            draft.gas.map { SQLValue.integer($0 ? 1 : 0) } ?? .null,
            draft.urgency.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(iso(clock.now))
        ])
        return try db.query("SELECT last_insert_rowid() AS id;").first?.int("id") ?? 0
    }

    public func entry(id: Int64) throws -> BowelMovementEntry? {
        try db.query("""
        SELECT id, logicalDay, timestamp, bristolType, color, bloodPresent, bloodAmount, gas, urgency, notes, clinicianEscalationLevel, createdAt
        FROM bowel_movement WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEntry)
    }

    public func logs(for logicalDay: String) throws -> [BowelMovementEntry] {
        try db.query("""
        SELECT id, logicalDay, timestamp, bristolType, color, bloodPresent, bloodAmount, gas, urgency, notes, clinicianEscalationLevel, createdAt
        FROM bowel_movement WHERE logicalDay = ? ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    private func rowToEntry(_ row: Row) -> BowelMovementEntry? {
        guard let id = row.int("id"),
              let logicalDay = row.string("logicalDay"),
              let timestampText = row.string("timestamp"),
              let timestamp = date(from: timestampText),
              let bristolRaw = row.int("bristolType"),
              let bristolType = BristolType(rawValue: Int(bristolRaw)) else { return nil }
        return BowelMovementEntry(
            id: id,
            logicalDay: logicalDay,
            timestamp: timestamp,
            bristolType: bristolType,
            color: row.string("color"),
            bloodPresent: (row.int("bloodPresent") ?? 0) == 1,
            bloodAmount: row.string("bloodAmount"),
            gas: row.isNull("gas") ? nil : (row.int("gas") == 1),
            urgency: row.int("urgency").map(Int.init),
            notes: row.string("notes"),
            clinicianEscalationLevel: row.string("clinicianEscalationLevel"),
            createdAt: row.string("createdAt").flatMap(date(from:)) ?? Date()
        )
    }
}
