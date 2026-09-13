import Foundation

/// Migration 001 — core infrastructure only.
///
/// IMPORTANT, READ BEFORE ADDING TABLES HERE.
///
/// Technical Specification v1.0 defines a 48-table domain schema. That text is
/// not available to this package, so **none of those 48 tables are invented
/// here**. This migration creates only the tables AlmanacCore itself owns and
/// can define from first principles: the sync anchor store and the backup
/// manifest. The domain schema belongs in migration 002 and must be
/// transcribed from the spec, not reconstructed.
///
/// If the spec's own build order names the 48-table migration "Migration_001",
/// renumber this one to 000 or fold it into 001 at that point — nothing has
/// shipped, so the renumber is free today and expensive after the first install.
public enum Migration001_CoreInfrastructure: Migration {
    public static let version = 1
    public static let name = "core_infrastructure"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE sync_anchor (
            domain        TEXT    PRIMARY KEY,
            anchor_token  BLOB,
            last_synced   TEXT,
            last_error    TEXT
        );
        """)

        try db.execute("""
        CREATE TABLE backup_manifest (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at    TEXT    NOT NULL,
            schema_version INTEGER NOT NULL,
            byte_count    INTEGER NOT NULL,
            sha256        TEXT    NOT NULL,
            note          TEXT
        );
        """)

        try db.execute("""
        CREATE INDEX idx_backup_manifest_created_at
            ON backup_manifest (created_at DESC);
        """)
    }
}

/// The migration list the app runs at launch. Append only.
public enum AlmanacMigrations {
    public static let all: [any Migration.Type] = [
        Migration001_CoreInfrastructure.self,
        Migration002_LaboratoryCatalog.self,
        Migration003_LaboratoryRecords.self,
        Migration004_HealthSamples.self,
        Migration005_SpecimenAndCatalogSemantics.self,
        Migration006_EditingAndSourceOrdering.self,
        Migration007_ConflictResolution.self,
        Migration008_NutritionReference.self
        // The Technical Spec v1.0 48-table schema is still unavailable and is
        // still not authored from inference. Numbering for it is settled per
        // docs/architecture/health-data-foundation.md §11, and renumbering
        // 002-004 stays free until a durable database exists.
    ]
}
