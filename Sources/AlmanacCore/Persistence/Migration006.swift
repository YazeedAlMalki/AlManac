import Foundation

/// Migration 006 — editing, audited metadata corrections, and source ordering.
///
/// Appended; 001-005 are untouched.
///
/// Three things this adds:
///
/// 1. `lab_observation_metadata_revision` — the previous specimen, collection
///    time, catalog mapping and report association of an observation, so a
///    correction to any of them is auditable rather than an in-place update.
///    Metadata corrections were previously invisible: `record` compares result
///    *content*, so changing only the specimen changed nothing at all.
/// 2. Source ordering on reports. Without it, a re-imported older version of a
///    report would supersede the newer one already held, because arrival order
///    was the only signal. Ordering is stored as a kind plus its text so two
///    incomparable kinds can be detected instead of silently compared.
/// 3. `lab_report_revision.kind` — a superseded version and a *conflicting*
///    version are different facts. A conflict does not change what is current.
public enum Migration006_EditingAndSourceOrdering: Migration {
    public static let version = 6
    public static let name = "editing_and_source_ordering"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE lab_report ADD COLUMN source_ordering_kind TEXT;")
        try db.execute("ALTER TABLE lab_report ADD COLUMN source_ordering_text TEXT;")

        try db.execute("""
        ALTER TABLE lab_report_revision
            ADD COLUMN kind TEXT NOT NULL DEFAULT 'superseded';
        """)
        try db.execute("ALTER TABLE lab_report_revision ADD COLUMN source_ordering_kind TEXT;")
        try db.execute("ALTER TABLE lab_report_revision ADD COLUMN source_ordering_text TEXT;")
        // Replay detection reads this: an incoming fingerprint already present
        // in the history is a re-send of a version, not a new correction.
        try db.execute("""
        CREATE INDEX idx_lab_report_revision_fingerprint
            ON lab_report_revision (report_id, content_fingerprint);
        """)

        try db.execute("""
        CREATE TABLE lab_observation_metadata_revision (
            id                          TEXT    PRIMARY KEY,
            observation_id              TEXT    NOT NULL
                                            REFERENCES lab_observation(id) ON DELETE CASCADE,
            revision_number             INTEGER NOT NULL,
            report_id                   TEXT,
            catalog_analyte_id          TEXT,
            match_origin                TEXT,
            match_confidence            TEXT,
            specimen_kind               TEXT    NOT NULL,
            specimen_text               TEXT,
            collected_at                TEXT,
            collected_precision         TEXT    NOT NULL,
            collected_tz_offset_minutes INTEGER,
            collected_tz_id             TEXT,
            changed_fields              TEXT    NOT NULL,
            actor                       TEXT    NOT NULL,
            reason_text                 TEXT,
            recorded_at                 TEXT    NOT NULL
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_observation_metadata_revision_number
            ON lab_observation_metadata_revision (observation_id, revision_number);
        """)
    }
}
