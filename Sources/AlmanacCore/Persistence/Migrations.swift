import Foundation

/// Migration 001 — core infrastructure only.
///
/// IMPORTANT, READ BEFORE ADDING TABLES HERE.
///
/// Technical Specification v1.0 defines a 48-table domain schema. When this
/// migration was written that text was believed lost, so it creates only the
/// tables AlmanacCore itself owns and could define from first principles: the
/// sync anchor store and the backup manifest.
///
/// **The spec has since been recovered** (2026-09-15). Its own `sync_anchor`
/// (§5.24) is a different table from the one below — keyed on `sampleType`
/// with base64 `anchorData`, where this one is keyed on `domain` with an
/// `anchor_token` BLOB. Both cannot exist. That collision is unresolved and
/// recorded in docs/architecture/spec-reconciliation.md; until it is settled,
/// this table stands and the spec's is not created.
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
        Migration008_NutritionReference.self,
        Migration009_NutritionLog.self,
        Migration010_NutritionPortionsAndDishes.self,
        Migration011_PortionIdentity.self,
        Migration012_HydrationLog.self,
        Migration013_HydrationFeatures.self,
        Migration014_CoreDailySchema.self,
        Migration015_SchemaCollisionResolution.self,
        Migration016_TrainingSchema.self,
        Migration017_NutritionMealType.self,
        Migration018_BodyCompositionAndWellness.self,
        Migration019_VitalsRecordUpsertIndexFix.self,
        Migration020_VitalsRecordSoftDeleteColumn.self,
        Migration021_SyncAnchorLastErrorColumn.self
        // Technical Spec v1.0 was recovered on 2026-09-15 (see Migration014's
        // header). 014 transcribes the fourteen §5 tables Slice 2 needs, which
        // collide with nothing already here. Four spec tables DO collide with
        // 001-013 — sync_anchor, nutrition_log, hydration_log, lab_result —
        // and are deliberately not in 014; docs/architecture/spec-reconciliation.md
        // holds that decision. Renumbering 001-014 to match the spec's own
        // ordering stays free until a durable database exists.
    ]
}
