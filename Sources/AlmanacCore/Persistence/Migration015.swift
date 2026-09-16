import Foundation

/// Settle schema collisions per decision 2026-09-16: spec wins where ahead.
///
/// 1. Replaces sync_anchor (Migration001) with spec shape: keyed on sampleType,
///    base64 anchorData, lastSyncTimestamp. SyncAnchorStore moves with it.
///    
/// 2. Adds drink_entry (spec §5.12) — gaps in repo were: drinkType taxonomy,
///    per-drink caffeine/calories tracking, custom drink names.
///
/// 3. Adds caffeine_log (spec §5.14) — entire missing feature for shift workers:
///    hoursBeforeIntendedSleep, caffeineContext (early/normal/late/very_late),
///    contextual readiness impact per BRD §6.2.
///
/// Notes:
/// - Old sync_anchor is dropped; prior anchors are not migrated (next sync
///   rereads from the start for each type). This is acceptable because
///   HealthKit anchors are opaque, and the gain (spec parity) outweighs the
///   cost (one re-read per domain).
/// - nutrition_log and lab_result are recorded as amended to the spec
///   (not changed here; see docs/architecture/spec-reconciliation.md).
public enum Migration015_SchemaCollisionResolution: Migration {
    public static let version = 15
    public static let name = "schema_collision_resolution"

    public static func up(_ db: Database) throws {
        // Drop old sync_anchor and create new one per spec §5.24.
        try db.execute("DROP TABLE IF EXISTS sync_anchor;")
        try db.execute("""
        CREATE TABLE sync_anchor (
            id                  INTEGER PRIMARY KEY,
            sampleType          TEXT NOT NULL UNIQUE,
            anchorData          TEXT,
            lastSyncTimestamp   TEXT,
            updatedAt           TEXT NOT NULL
        );
        """)

        // Add drink_entry per spec §5.12.
        try db.execute("""
        CREATE TABLE drink_entry (
            id              INTEGER PRIMARY KEY,
            timestamp       TEXT NOT NULL,
            timezoneOffset  INTEGER,
            logicalDay      TEXT NOT NULL,
            drinkType       TEXT NOT NULL,
            drinkName       TEXT,
            fluidVolumeMl   REAL NOT NULL DEFAULT 0,
            caffeineMg      REAL NOT NULL DEFAULT 0,
            calories        REAL NOT NULL DEFAULT 0,
            proteinG        REAL NOT NULL DEFAULT 0,
            carbsG          REAL NOT NULL DEFAULT 0,
            fatG            REAL NOT NULL DEFAULT 0,
            notes           TEXT,
            createdAt       TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_drink_entry_logical_day ON drink_entry(logicalDay);")
        try db.execute("CREATE INDEX idx_drink_entry_timestamp ON drink_entry(timestamp);")

        // Add caffeine_log per spec §5.14.
        try db.execute("""
        CREATE TABLE caffeine_log (
            id                          INTEGER PRIMARY KEY,
            drinkEntryId                INTEGER REFERENCES drink_entry(id),
            timestamp                   TEXT NOT NULL,
            logicalDay                  TEXT NOT NULL,
            caffeineMg                  REAL NOT NULL,
            drinkType                   TEXT NOT NULL,
            intendedSleepTimestamp      TEXT,
            hoursBeforeIntendedSleep    REAL,
            caffeineContext             TEXT,
            createdAt                   TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_caffeine_log_timestamp ON caffeine_log(timestamp);")
        try db.execute("CREATE INDEX idx_caffeine_log_logical_day ON caffeine_log(logicalDay);")
    }
}
