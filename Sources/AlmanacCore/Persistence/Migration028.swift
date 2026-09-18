import Foundation

/// Migration 028 — a unique index on `circadian_context.date`.
///
/// Needed to wire `readiness_cycle.circadianContextId` (flagged as
/// unstarted since Migration014 created the table): §13.1 runs the engine
/// "once per readiness cycle", but a cycle can be reprocessed — a corrected
/// primary episode, a later-arriving shift entry — so `CircadianContextStore`
/// needs to *replace* a date's row rather than accumulate duplicates.
/// `INSERT ... ON CONFLICT(date) DO UPDATE` needs this index to have a
/// conflict target; nothing enforced one-per-date before this, though
/// nothing ever wrote more than one either, so there is no dedup to do
/// first.
public enum Migration028_CircadianContextUniqueDate: Migration {
    public static let version = 28
    public static let name = "circadian_context_unique_date"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE UNIQUE INDEX idx_circadian_context_date ON circadian_context(date);
        """)
    }
}
