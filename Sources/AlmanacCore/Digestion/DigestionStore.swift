import Foundation

/// Bristol Stool Scale, Type 1 (separate hard lumps) through Type 7 (liquid,
/// no solid pieces) — BRD §6.3's reference scale.
///
/// Presentation (picker vs. educational images/text) is a UI decision for
/// the Slice 9 handoff to settle; this is only the fixed domain value.
public enum BristolType: Int, Sendable, Codable, CaseIterable {
    case type1 = 1, type2, type3, type4, type5, type6, type7

    /// The type's name on the scale, after Heaton & Lewis (1997), *Scoring
    /// systems of stool composition and physical form*.
    ///
    /// A picker of `1 2 3 4 5 6 7` is not a reference scale — the number only
    /// means something against its description, and the description is what the
    /// user is actually being asked to recognise. The seven names are the
    /// standard published wording rather than anything written here.
    ///
    /// **Attribution is an open item.** These strings are reproduced from a
    /// published scale, and `docs/features/digestion.md` records that the
    /// Attributions screen has not been extended to cover them.
    public var displayName: String {
        switch self {
        case .type1: return "Separate hard lumps"
        case .type2: return "Lumpy, sausage-shaped"
        case .type3: return "Sausage-shaped, smooth"
        case .type4: return "Smooth, soft sausage"
        case .type5: return "Soft blobs with clear edges"
        case .type6: return "Mushy pieces"
        case .type7: return "Entirely liquid"
        }
    }

    /// One clause of what the type looks like, for the picker's secondary line.
    /// The seven types differ as much in consistency as in shape, and "mushy
    /// pieces" alone does not say whether that is a lot or a little.
    public var summary: String {
        switch self {
        case .type1: return "Like nuts, hard to pass"
        case .type2: return "Lumpy and hard to pass"
        case .type3: return "Like a sausage, smooth"
        case .type4: return "Like a snake, smooth and soft"
        case .type5: return "Soft blobs, clearly separated"
        case .type6: return "Fluffy, shapeless pieces"
        case .type7: return "No solid pieces at all"
        }
    }

    /// The whole row, as a screen reader should announce it.
    ///
    /// BRD §6.3's accessibility rule is "never rely on colour alone; numeric
    /// grades + text + VoiceOver" — and the two halves of that have to travel
    /// together, or a grade travels without its meaning.
    public var accessibilityLabel: String { "Type \(rawValue), \(displayName)" }
}

/// Stool colour, BRD §6.3's own six: "brown range, pale, yellow, green, black,
/// red".
///
/// A closed set rather than the free `String?` the column holds, for the same
/// reason `BristolType` is closed: these are the values an escalation rule
/// would one day key on ("black", "red"), and a query over a spelling nobody
/// fixed in advance is a query that quietly finds nothing.
public enum StoolColor: String, Sendable, Codable, CaseIterable {
    case brown, pale, yellow, green, black, red

    public var displayName: String {
        switch self {
        case .brown: return "Brown"
        case .pale: return "Pale"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .black: return "Black"
        case .red: return "Red"
        }
    }
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

    /// Entries across a logical-day range, newest first.
    ///
    /// The same shape as `logs(for:)` but half-open over days, so a caller
    /// showing several days does not have to issue a query per day and stitch
    /// them. Newest first because every caller wants the most recent thing on
    /// screen, and a history list reads downward.
    public func logs(from: String, to: String) throws -> [BowelMovementEntry] {
        try db.query("""
        SELECT id, logicalDay, timestamp, bristolType, color, bloodPresent, bloodAmount, gas, urgency, notes, clinicianEscalationLevel, createdAt
        FROM bowel_movement WHERE logicalDay >= ? AND logicalDay < ?
        ORDER BY timestamp DESC;
        """, [.text(from), .text(to)]).compactMap(rowToEntry)
    }

    /// Removes an entry outright.
    ///
    /// `bowel_movement` has no `deletedAt` and nothing in the app derives from
    /// a row that is still here, so a hard delete is the honest operation. A
    /// mis-tap is the case this exists for, and a "deleted" row that only
    /// reports itself deleted would leave the user unable to tell the two
    /// apart.
    public func delete(id: Int64) throws {
        try db.run("DELETE FROM bowel_movement WHERE id = ?;", [.integer(id)])
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
