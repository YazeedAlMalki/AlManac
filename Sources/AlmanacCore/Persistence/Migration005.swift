import Foundation

/// Migration 005 — specimen, catalog semantics, and report revisions.
///
/// Appended rather than folded into 002-004, which are committed. The rule the
/// runner enforces is that an applied migration is never edited; the rule this
/// file follows is that a *committed* one is not edited either, so the history
/// in git and the history in `schema_migrations` say the same thing.
///
/// Three corrections, one migration:
///
/// 1. `lab_observation.specimen_kind` — optional, defaulting to `unknown`, so
///    an incomplete manual entry is unaffected while a blood result and a urine
///    result stop being indistinguishable.
/// 2. `lab_catalog_analyte.measurement_role` — direct measurement, precursor,
///    functional marker or metabolic marker.
/// 3. `lab_report_revision` — the superseded values of a report whose source
///    later corrected its date or its laboratory name.
public enum Migration005_SpecimenAndCatalogSemantics: Migration {
    public static let version = 5
    public static let name = "specimen_and_catalog_semantics"

    public static func up(_ db: Database) throws {
        // Defaults chosen so existing rows stay truthful: an observation
        // recorded before this migration did not state a specimen, and
        // 'unknown' is exactly that.
        try db.execute("""
        ALTER TABLE lab_observation
            ADD COLUMN specimen_kind TEXT NOT NULL DEFAULT 'unknown';
        """)
        try db.execute("""
        CREATE INDEX idx_lab_observation_specimen
            ON lab_observation (catalog_analyte_id, specimen_kind);
        """)

        // 'direct' is the right default only because every entry seeded before
        // this migration is re-seeded with an explicit role immediately after.
        try db.execute("""
        ALTER TABLE lab_catalog_analyte
            ADD COLUMN measurement_role TEXT NOT NULL DEFAULT 'direct';
        """)

        // Holds what a report used to say. The live row in `lab_report` always
        // carries the newest source values; nothing is discarded to get there.
        try db.execute("""
        CREATE TABLE lab_report_revision (
            id                          TEXT    PRIMARY KEY,
            report_id                   TEXT    NOT NULL REFERENCES lab_report(id) ON DELETE CASCADE,
            revision_number             INTEGER NOT NULL,
            laboratory_name_text        TEXT,
            reported_at                 TEXT,
            reported_precision          TEXT    NOT NULL,
            reported_tz_offset_minutes  INTEGER,
            reported_tz_id              TEXT,
            header_text                 TEXT,
            content_fingerprint         TEXT    NOT NULL,
            actor                       TEXT    NOT NULL,
            superseded_at               TEXT    NOT NULL
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_report_revision_number
            ON lab_report_revision (report_id, revision_number);
        """)
    }
}
