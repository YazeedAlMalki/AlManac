import Foundation

/// Migration 019 — fixes a pre-existing bug in `vitals_record`'s upsert path,
/// found while building Migration018 (Slice 7, Body Composition) and giving
/// `body_composition_measurement` the same upsert shape.
///
/// `VitalsRecordHealthBridge.apply` (Slice 2) runs
/// `INSERT ... ON CONFLICT(source, healthKitUUID) WHERE healthKitUUID IS NOT NULL
/// DO UPDATE ...`, but Migration014 only gave `vitals_record` a single-column
/// `healthKitUUID TEXT UNIQUE`. SQLite requires an `ON CONFLICT` target to
/// match a real index's columns and partial condition, textually — a
/// same-named-but-narrower UNIQUE constraint does not satisfy it. Every
/// update (a HealthKit sample whose value changed since last sync) and every
/// soft-delete throws `SQLite error 1: ON CONFLICT clause does not match any
/// PRIMARY KEY or UNIQUE constraint`, unconditionally. Confirmed by running
/// `VitalsRecordHealthBridgeTests` before this migration existed: 4 of 5
/// tests failed with exactly that error. This predates this session — the
/// diff that removed `.bodyMass` from that bridge's metric map (Migration018)
/// did not touch the INSERT statement.
///
/// Migrations are append-only once authored (`Migration.swift`), so this
/// adds the missing index rather than editing Migration014.
public enum Migration019_VitalsRecordUpsertIndexFix: Migration {
    public static let version = 19
    public static let name = "vitals_record_upsert_index_fix"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE UNIQUE INDEX idx_vitals_record_source_hkuuid
            ON vitals_record(source, healthKitUUID)
            WHERE healthKitUUID IS NOT NULL;
        """)
    }
}
