import Foundation

/// Migration 020 — a second pre-existing `vitals_record` bug, found
/// immediately after Migration019 fixed the first (upsert conflict target).
///
/// `VitalsRecordHealthBridge.apply`'s soft-delete sets `createdAt = NULL` to
/// mark a retracted HealthKit sample, but `vitals_record.createdAt` is
/// `NOT NULL` — every delete throws `SQLite error 19: NOT NULL constraint
/// failed`. Confirmed by `VitalsRecordHealthBridgeTests.softDeleteVitals`,
/// still failing after Migration019.
///
/// Adds a proper `deletedAt` column (same shape as
/// `body_composition_measurement.deletedAt`, Migration018) rather than
/// overloading `createdAt`.
public enum Migration020_VitalsRecordSoftDeleteColumn: Migration {
    public static let version = 20
    public static let name = "vitals_record_soft_delete_column"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE vitals_record ADD COLUMN deletedAt TEXT;")
    }
}
