import Foundation

/// Migration 021 — fixes `SyncAnchorStore`, which still queried `sync_anchor`
/// by its pre-Migration015 shape (`domain`/`anchor_token`/`last_synced`/
/// `last_error`). Migration015 already replaced the table with the spec's
/// shape (`sampleType`/`anchorData`/`lastSyncTimestamp`) — the store was
/// never updated to match, so every call failed with `no such column:
/// domain`. `docs/architecture/spec-reconciliation.md` §4.1 recorded the
/// table move as "decided and shipped"; the store was the other half nobody
/// finished.
///
/// Spec §5.24's `sync_anchor` has no error column at all, but
/// `SyncAnchorStoreTests.testFailureKeepsLastGoodAnchor` requires one (a
/// failed sync must stay visible without losing the last good anchor — real
/// behavior, not test debt). `lastError` is added here, same as `deletedAt`
/// was added to `body_composition_measurement`/`vitals_record` beyond the
/// spec's literal text.
///
/// (This slot was briefly a `sleep_episode.deletedAt` column for
/// `SleepEpisodeHealthBridge` — that bridge turned out to be a wrong-shaped
/// duplicate of the already-working `HealthSampleStore` and was deleted
/// rather than fixed; see `docs/implementation-status.md`. Renumbered down
/// to close the gap since nothing has shipped yet.)
public enum Migration021_SyncAnchorLastErrorColumn: Migration {
    public static let version = 21
    public static let name = "sync_anchor_last_error_column"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE sync_anchor ADD COLUMN lastError TEXT;")
    }
}
