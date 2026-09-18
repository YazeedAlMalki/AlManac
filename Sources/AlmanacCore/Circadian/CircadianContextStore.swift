import Foundation

/// A `circadian_context` row read from storage.
public struct CircadianContextRecord: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let date: String
    public let shiftType: ShiftType?
    public let contextType: CircadianContextType
    public let transitionDayN: Int?
    public let notes: String?
    public let createdAt: Date
}

/// Persists `CircadianContextEngine`'s pure output (§13) into
/// `circadian_context`, so `readiness_cycle.circadianContextId` — flagged
/// unstarted since the table's own migration — has something real to point
/// at.
///
/// One row per date. `upsert` replaces rather than duplicates: §13.1 says
/// the engine "runs once per readiness cycle", but a cycle can legitimately
/// be reprocessed (a corrected primary episode, a later-arriving shift
/// entry), and a stale context row would otherwise sit there uncorrected
/// while a second one for the same date piled up beside it. Migration028's
/// unique index on `date` is what makes `ON CONFLICT` well-defined here.
public struct CircadianContextStore: @unchecked Sendable {
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

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    // MARK: - Write

    /// Writes `context`, replacing any existing row for its date. Returns
    /// the row's id either way — queried back by the unique `date` rather
    /// than trusted from `last_insert_rowid()`, since that only advances on
    /// the insert branch of `ON CONFLICT`, not the update one.
    @discardableResult
    public func upsert(_ context: CircadianContext) throws -> Int64 {
        try db.run("""
        INSERT INTO circadian_context (date, shiftType, contextType, transitionDayN, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
            shiftType = excluded.shiftType,
            contextType = excluded.contextType,
            transitionDayN = excluded.transitionDayN;
        """, [
            .text(context.date.value),
            context.shiftType.map { SQLValue.text($0.rawValue) } ?? .null,
            .text(context.contextType.rawValue),
            context.transitionDayN.map { SQLValue.integer(Int64($0)) } ?? .null,
            .null,
            .text(iso(clock.now))
        ])

        guard let row = try db.query("SELECT id FROM circadian_context WHERE date = ?;",
                                      [.text(context.date.value)]).first,
              let id = row.int("id") else {
            throw CircadianContextStoreError.insertFailed
        }
        return id
    }

    // MARK: - Read

    public func context(for date: String) throws -> CircadianContextRecord? {
        try db.query("""
        SELECT id, date, shiftType, contextType, transitionDayN, notes, createdAt
        FROM circadian_context WHERE date = ?;
        """, [.text(date)]).first.flatMap(rowToRecord)
    }

    // MARK: - Private

    private func rowToRecord(_ row: Row) -> CircadianContextRecord? {
        guard let id = row.int("id"),
              let date = row.string("date"),
              let contextTypeRaw = row.string("contextType"),
              let contextType = CircadianContextType(rawValue: contextTypeRaw),
              let createdAt = row.string("createdAt").flatMap(iso8601ToDate) else { return nil }

        return CircadianContextRecord(
            id: id,
            date: date,
            shiftType: row.string("shiftType").flatMap(ShiftType.init(rawValue:)),
            contextType: contextType,
            transitionDayN: row.int("transitionDayN").map(Int.init),
            notes: row.string("notes"),
            createdAt: createdAt
        )
    }
}

public enum CircadianContextStoreError: Error, Sendable {
    case insertFailed
}
