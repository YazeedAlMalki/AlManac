import Foundation

/// A `readiness_cycle` row read from storage.
public struct ReadinessCycleRecord: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let anchorDate: String
    public let primaryWakeTimestamp: Date?
    public let cycleStartTimestamp: Date?
    public let cycleEndTimestamp: Date?
    public let primarySleepEpisodeId: Int64?
    public let circadianContextId: Int64?
    public let createdAt: Date
    public let updatedAt: Date
}

/// Reading and creating `readiness_cycle` rows (§5.7, §7.3, §8.4).
///
/// **What this deliberately does not do:** derive a cycle from
/// `SleepEpisodeStore`'s primary episode. §8.4 says a cycle's
/// `primaryWakeTimestamp`/`cycleStartTimestamp`/`primarySleepEpisodeId` come
/// from "primary sleep is determined for a cycle" — that determination
/// (picking the primary episode out of a night's episodes and closing the
/// previous cycle's `cycleEndTimestamp` when it does) is its own task, not
/// yet built anywhere in this repo (`docs/implementation-status.md`,
/// 2026-09-16 entry). `createCycle`/`ensureCycle` here make a bare cycle row
/// with whatever timestamps the caller already has — enough for the
/// dashboard and check-in screens to have a cycle id to link logs against
/// today — and leave `primarySleepEpisodeId`/`circadianContextId` nil until
/// that real linking task lands.
public struct ReadinessCycleStore: @unchecked Sendable {
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

    // MARK: - Write

    @discardableResult
    public func createCycle(anchorDate: String,
                             primaryWakeTimestamp: Date? = nil,
                             cycleStartTimestamp: Date? = nil,
                             primarySleepEpisodeId: Int64? = nil) throws -> Int64 {
        let createdAt = nowText
        try db.run("""
        INSERT INTO readiness_cycle
            (anchorDate, primaryWakeTimestamp, cycleStartTimestamp, primarySleepEpisodeId, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?);
        """, [
            .text(anchorDate),
            primaryWakeTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            cycleStartTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            primarySleepEpisodeId.map { SQLValue.integer($0) } ?? .null,
            .text(createdAt),
            .text(createdAt)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw ReadinessCycleStoreError.insertFailed
        }
        return id
    }

    /// The cycle for `anchorDate` if one already exists; otherwise a new bare
    /// one, anchored at `timestamp`. Never creates a second cycle for the
    /// same anchor date.
    @discardableResult
    public func ensureCycle(anchorDate: String, at timestamp: Date) throws -> Int64 {
        if let existing = try cycle(anchorDate: anchorDate) { return existing.id }
        return try createCycle(anchorDate: anchorDate,
                                primaryWakeTimestamp: timestamp,
                                cycleStartTimestamp: timestamp)
    }

    // MARK: - Read

    public func cycle(id: Int64) throws -> ReadinessCycleRecord? {
        try db.query("""
        SELECT id, anchorDate, primaryWakeTimestamp, cycleStartTimestamp, cycleEndTimestamp,
               primarySleepEpisodeId, circadianContextId, createdAt, updatedAt
        FROM readiness_cycle WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToRecord)
    }

    public func cycle(anchorDate: String) throws -> ReadinessCycleRecord? {
        try db.query("""
        SELECT id, anchorDate, primaryWakeTimestamp, cycleStartTimestamp, cycleEndTimestamp,
               primarySleepEpisodeId, circadianContextId, createdAt, updatedAt
        FROM readiness_cycle WHERE anchorDate = ?
        ORDER BY id DESC LIMIT 1;
        """, [.text(anchorDate)]).first.flatMap(rowToRecord)
    }

    /// The still-open cycle (§7.3: `cycleEndTimestamp IS NULL`), if any. There
    /// should be at most one — nothing enforces that at the schema level
    /// (closing a cycle is part of the not-yet-built primary-sleep-linking
    /// task above), so this returns the most recently created one.
    public func openCycle() throws -> ReadinessCycleRecord? {
        try db.query("""
        SELECT id, anchorDate, primaryWakeTimestamp, cycleStartTimestamp, cycleEndTimestamp,
               primarySleepEpisodeId, circadianContextId, createdAt, updatedAt
        FROM readiness_cycle WHERE cycleEndTimestamp IS NULL
        ORDER BY id DESC LIMIT 1;
        """).first.flatMap(rowToRecord)
    }

    // MARK: - Private

    private func rowToRecord(_ row: Row) -> ReadinessCycleRecord? {
        guard let id = row.int("id"),
              let anchorDate = row.string("anchorDate"),
              let createdAt = row.string("createdAt").flatMap(iso8601ToDate),
              let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) else { return nil }

        return ReadinessCycleRecord(
            id: id,
            anchorDate: anchorDate,
            primaryWakeTimestamp: row.string("primaryWakeTimestamp").flatMap(iso8601ToDate),
            cycleStartTimestamp: row.string("cycleStartTimestamp").flatMap(iso8601ToDate),
            cycleEndTimestamp: row.string("cycleEndTimestamp").flatMap(iso8601ToDate),
            primarySleepEpisodeId: row.int("primarySleepEpisodeId"),
            circadianContextId: row.int("circadianContextId"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum ReadinessCycleStoreError: Error, Sendable {
    case insertFailed
}
