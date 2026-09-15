import Foundation

/// Migration 012 — the hydration log.
///
/// Appended; 001-011 are untouched.
///
/// Identity columns are shaped like `nutrition_log` (Migration009):
/// `(source_system, external_id)` with a partial unique index, so a manual
/// tap (no external id) is never deduplicated against another manual tap,
/// while a HealthKit-sourced sample re-synced under the same external id
/// updates the same row instead of duplicating it.
///
/// Lifecycle is shaped like `health_sample` (Migration004) instead of
/// `nutrition_log`: soft delete only, **no revision table**. A hydration
/// entry has one actor and no correction-audit requirement — unlike a
/// laboratory result, nobody else contests how much water was logged. Soft
/// delete still matters: a HealthKit-sourced row deleted in the app must not
/// be resurrected the next time an inbound sync re-reads the same anchor
/// range.
///
/// `logged_at` is instant-precision only in this pass — a hydration entry is
/// either a live in-app tap or an already-exact HealthKit sample, neither of
/// which needs Laboratory-style imprecise/backfilled dating. The precision
/// and timezone columns are kept for schema consistency with the other
/// modules and to leave room to loosen this later, but every row written by
/// `HydrationStore` in v1 has `logged_precision = "instant"`.
///
/// `healthkit_synced_at` is the outbound half of sync: a manually-logged
/// entry not yet pushed to HealthKit has it `NULL`. That predicate —
/// `idx_hydration_log_pending_writeback` — **is** the offline queue: no
/// separate queue table, because the row itself, already durable in local
/// SQLite, is what survives an offline period or an app restart.
public enum Migration012_HydrationLog: Migration {
    public static let version = 12
    public static let name = "hydration_log"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE hydration_log (
            id                          TEXT    PRIMARY KEY,
            source_system               TEXT    NOT NULL,
            external_id                 TEXT,
            amount_ml                   REAL    NOT NULL CHECK (amount_ml > 0),
            note_text                   TEXT,
            logged_at                   TEXT    NOT NULL,
            logged_precision            TEXT    NOT NULL,
            logged_tz_offset_minutes    INTEGER,
            logged_tz_id                TEXT,
            recorded_at                 TEXT    NOT NULL,
            recorded_tz_offset_minutes  INTEGER,
            healthkit_synced_at         TEXT,
            healthkit_external_id       TEXT,
            deleted_at                  TEXT
        );
        """)

        // Identity, as for nutrition_log: the same external id from a
        // different source is a different entry. Manual taps carry no
        // external id and are therefore never deduplicated against each
        // other — logging water twice in a row is not a replay.
        try db.execute("""
        CREATE UNIQUE INDEX idx_hydration_log_source
            ON hydration_log (source_system, external_id)
            WHERE external_id IS NOT NULL;
        """)
        try db.execute("CREATE INDEX idx_hydration_log_time ON hydration_log (logged_at);")

        // Drains the outbound HealthKit queue: "manual entries not yet
        // pushed." A row leaves this index the moment it is written back
        // successfully, never before.
        try db.execute("""
        CREATE INDEX idx_hydration_log_pending_writeback
            ON hydration_log (healthkit_synced_at)
            WHERE healthkit_synced_at IS NULL AND deleted_at IS NULL;
        """)
    }
}
