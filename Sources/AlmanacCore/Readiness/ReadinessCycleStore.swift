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
/// `createCycle`/`ensureCycle` make a bare cycle row with whatever
/// timestamps the caller already has — enough for the dashboard and
/// check-in screens to have a cycle id to link logs against today, before
/// any sleep has even been classified yet. `linkPrimaryEpisode`/
/// `closeCycle` below are the other half: backfilling a bare row (or
/// updating a real one) once a primary sleep episode is actually known.
/// Picking *which* episode is primary (§8.2's priority order) is not this
/// store's job — that happens earlier, inside `SleepClassifier`, before an
/// episode is ever persisted. Tying a stored primary episode to this table,
/// closing out the cycle before it, and re-linking wellness logs to both is
/// `ReadinessCyclePrimaryLinkingService`'s job — this store only exposes
/// the write primitives that service needs, including attaching a
/// precomputed `circadianContextId` (Migration028) when the caller has
/// one; this store never computes one itself.
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
                             primarySleepEpisodeId: Int64? = nil,
                             circadianContextId: Int64? = nil) throws -> Int64 {
        let createdAt = nowText
        try db.run("""
        INSERT INTO readiness_cycle
            (anchorDate, primaryWakeTimestamp, cycleStartTimestamp, primarySleepEpisodeId, circadianContextId, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(anchorDate),
            primaryWakeTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            cycleStartTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            primarySleepEpisodeId.map { SQLValue.integer($0) } ?? .null,
            circadianContextId.map { SQLValue.integer($0) } ?? .null,
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

    /// Backfills a primary sleep episode onto an existing cycle row —
    /// either a bare one `ensureCycle` made before classification ran, or a
    /// real one being corrected by reprocessing. Leaves `cycleEndTimestamp`
    /// untouched; closing a cycle is `closeCycle`'s job, kept separate
    /// because the two are decided by different events (this cycle's own
    /// wake vs. the *next* cycle's wake, per §7.3).
    @discardableResult
    public func linkPrimaryEpisode(id: Int64, primarySleepEpisodeId: Int64,
                                    primaryWakeTimestamp: Date, cycleStartTimestamp: Date,
                                    circadianContextId: Int64? = nil) throws -> Bool {
        let affected = try db.run("""
        UPDATE readiness_cycle
        SET primarySleepEpisodeId = ?, primaryWakeTimestamp = ?, cycleStartTimestamp = ?,
            circadianContextId = ?, updatedAt = ?
        WHERE id = ?;
        """, [
            .integer(primarySleepEpisodeId),
            .text(iso(primaryWakeTimestamp)),
            .text(iso(cycleStartTimestamp)),
            circadianContextId.map { SQLValue.integer($0) } ?? .null,
            .text(nowText),
            .integer(id)
        ])
        return affected > 0
    }

    /// §7.3 — "cycleEndTimestamp = start of NEXT primary sleep episode's end
    /// (the next wake)". Called once the *next* cycle's wake time is known,
    /// on whichever cycle was open before it. `cycleEndTimestamp: nil`
    /// reopens a cycle — needed when a correction moves a formerly-adjacent
    /// cycle's wake time away, so the cycle it used to close against is no
    /// longer bounded by anything.
    @discardableResult
    public func closeCycle(id: Int64, cycleEndTimestamp: Date?) throws -> Bool {
        let affected = try db.run("""
        UPDATE readiness_cycle SET cycleEndTimestamp = ?, updatedAt = ? WHERE id = ?;
        """, [
            cycleEndTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            .text(nowText),
            .integer(id)
        ])
        return affected > 0
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
    /// should be at most one — `closeCycle` is what keeps that true once a
    /// caller (`ReadinessCyclePrimaryLinkingService`) actually calls it on
    /// the right cycle at the right time, but nothing enforces it at the
    /// schema level, so this returns the most recently created one rather
    /// than assuming.
    public func openCycle() throws -> ReadinessCycleRecord? {
        try db.query("""
        SELECT id, anchorDate, primaryWakeTimestamp, cycleStartTimestamp, cycleEndTimestamp,
               primarySleepEpisodeId, circadianContextId, createdAt, updatedAt
        FROM readiness_cycle WHERE cycleEndTimestamp IS NULL
        ORDER BY id DESC LIMIT 1;
        """).first.flatMap(rowToRecord)
    }

    /// Every cycle in the table. `ReadinessCyclePrimaryLinkingService` uses
    /// this to find a wake time's true chronological neighbors (the cycle
    /// with the greatest `cycleStartTimestamp` below it, and the one with
    /// the smallest above it) rather than assuming "whichever cycle is
    /// currently open" is the right one to touch — the thing that made
    /// out-of-order backfill and reach-back corrections come out wrong
    /// before. One row per day in practice, so an unfiltered read here is
    /// not a real cost; this store does not offer a "neighbors of" query of
    /// its own.
    public func allCycles() throws -> [ReadinessCycleRecord] {
        try db.query("""
        SELECT id, anchorDate, primaryWakeTimestamp, cycleStartTimestamp, cycleEndTimestamp,
               primarySleepEpisodeId, circadianContextId, createdAt, updatedAt
        FROM readiness_cycle;
        """).compactMap(rowToRecord)
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
