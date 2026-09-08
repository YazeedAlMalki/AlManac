import Foundation

// Numbering. Migration 001 is preserved exactly as declared. These three are
// appended after it. Before applying them to any database that already exists,
// read its `schema_migrations` table: MigrationRunner refuses a version behind
// the applied head, and the correct fix at that point is to renumber these
// (free while nothing durable has been created) rather than to edit 001.
// See docs/architecture/health-data-foundation.md §11.

/// Migration 002 — the laboratory catalog.
///
/// Catalog identity is an Almanac-owned string (`almanac:lab.<slug>`) that is
/// stable for the life of the product. External codes live in their own table
/// and carry a `verified` flag, so an unverified LOINC guess can never be
/// mistaken for a confirmed one — and none are seeded unverified.
public enum Migration002_LaboratoryCatalog: Migration {
    public static let version = 2
    public static let name = "laboratory_catalog"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE lab_catalog_analyte (
            id                  TEXT PRIMARY KEY,
            canonical_name      TEXT NOT NULL,
            family              TEXT NOT NULL,
            subfamily           TEXT,
            form                TEXT,
            default_value_type  TEXT NOT NULL,
            notes               TEXT,
            created_at          TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE lab_catalog_external_code (
            analyte_id  TEXT    NOT NULL REFERENCES lab_catalog_analyte(id) ON DELETE CASCADE,
            system      TEXT    NOT NULL,
            code        TEXT    NOT NULL,
            verified    INTEGER NOT NULL DEFAULT 0,
            verified_at TEXT,
            verified_by TEXT,
            PRIMARY KEY (analyte_id, system, code)
        );
        """)

        try db.execute("""
        CREATE TABLE lab_catalog_alias (
            id          TEXT NOT NULL PRIMARY KEY,
            analyte_id  TEXT NOT NULL REFERENCES lab_catalog_analyte(id) ON DELETE CASCADE,
            alias_text  TEXT NOT NULL,
            alias_fold  TEXT NOT NULL,
            locale      TEXT,
            origin      TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_lab_alias_fold ON lab_catalog_alias (alias_fold);")
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_alias_unique
            ON lab_catalog_alias (analyte_id, alias_fold);
        """)

        try db.execute("""
        CREATE TABLE lab_catalog_localization (
            analyte_id TEXT NOT NULL REFERENCES lab_catalog_analyte(id) ON DELETE CASCADE,
            locale     TEXT NOT NULL,
            name       TEXT NOT NULL,
            PRIMARY KEY (analyte_id, locale)
        );
        """)

        try db.execute("""
        CREATE TABLE lab_panel (
            id         TEXT PRIMARY KEY,
            name       TEXT NOT NULL,
            origin     TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE lab_panel_member (
            panel_id   TEXT    NOT NULL REFERENCES lab_panel(id) ON DELETE CASCADE,
            analyte_id TEXT    NOT NULL REFERENCES lab_catalog_analyte(id) ON DELETE CASCADE,
            position   INTEGER NOT NULL,
            PRIMARY KEY (panel_id, analyte_id)
        );
        """)
    }
}

/// Migration 003 — laboratory records.
///
/// The identity split that matters: `lab_observation` is the stable thing a
/// source keeps calling by the same id, and `lab_observation_revision` is one
/// version of its content. A source that re-reports the same observation id
/// with new content produces a second revision of one observation, not a
/// second observation.
public enum Migration003_LaboratoryRecords: Migration {
    public static let version = 3
    public static let name = "laboratory_records"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE lab_report (
            id                          TEXT PRIMARY KEY,
            source_system               TEXT,
            source_report_id            TEXT,
            laboratory_name_text        TEXT,
            reported_at                 TEXT,
            reported_precision          TEXT NOT NULL,
            reported_tz_offset_minutes  INTEGER,
            reported_tz_id              TEXT,
            header_text                 TEXT,
            entry_origin                TEXT NOT NULL,
            recorded_at                 TEXT NOT NULL,
            recorded_tz_offset_minutes  INTEGER
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_report_source
            ON lab_report (source_system, source_report_id)
            WHERE source_system IS NOT NULL AND source_report_id IS NOT NULL;
        """)

        try db.execute("""
        CREATE TABLE lab_observation (
            id                           TEXT PRIMARY KEY,
            report_id                    TEXT REFERENCES lab_report(id) ON DELETE SET NULL,
            source_system                TEXT,
            source_observation_id        TEXT,
            catalog_analyte_id           TEXT REFERENCES lab_catalog_analyte(id) ON DELETE SET NULL,
            match_origin                 TEXT,
            match_confidence             TEXT,
            time_point_label             TEXT,
            repeat_index                 INTEGER NOT NULL DEFAULT 0,
            collected_at                 TEXT,
            collected_precision          TEXT NOT NULL,
            collected_tz_offset_minutes  INTEGER,
            collected_tz_id              TEXT,
            specimen_text                TEXT,
            created_at                   TEXT NOT NULL
        );
        """)
        // Scoped to the issuing source, and only where the source gave an id.
        // Two sources may reuse a string without colliding; manual entries are
        // unconstrained, which is what lets legitimate repeats coexist.
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_observation_source
            ON lab_observation (source_system, source_observation_id)
            WHERE source_system IS NOT NULL AND source_observation_id IS NOT NULL;
        """)
        try db.execute("""
        CREATE INDEX idx_lab_observation_time ON lab_observation (collected_at);
        """)

        try db.execute("""
        CREATE TABLE lab_observation_revision (
            id                    TEXT    PRIMARY KEY,
            observation_id        TEXT    NOT NULL REFERENCES lab_observation(id) ON DELETE CASCADE,
            revision_number       INTEGER NOT NULL,
            source_revision_id    TEXT,
            is_current            INTEGER NOT NULL DEFAULT 1,
            lifecycle             TEXT    NOT NULL,
            value_type            TEXT    NOT NULL,
            comparator            TEXT    NOT NULL,
            derivation            TEXT    NOT NULL,
            missing_reason        TEXT,
            numeric_value         REAL,
            coded_value           TEXT,
            text_value            TEXT,
            ratio_numerator       REAL,
            ratio_denominator     REAL,
            titer_numerator       INTEGER,
            titer_denominator     INTEGER,
            unit_text             TEXT,
            lod_text              TEXT,
            loq_text              TEXT,
            range_text            TEXT,
            range_low             REAL,
            range_high            REAL,
            range_unit_text       TEXT,
            flag_text             TEXT,
            comment_text          TEXT,
            method_text           TEXT,
            source_analyte_text   TEXT,
            source_value_text     TEXT,
            content_origin        TEXT    NOT NULL,
            actor                 TEXT    NOT NULL,
            recorded_at           TEXT    NOT NULL,
            reason_text           TEXT,
            content_fingerprint   TEXT    NOT NULL,
            CHECK (missing_reason IS NULL OR value_type = 'absent'),
            CHECK (value_type <> 'absent' OR missing_reason IS NOT NULL)
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_revision_number
            ON lab_observation_revision (observation_id, revision_number);
        """)
        // Re-importing content already held is a no-op, not a new revision.
        try db.execute("""
        CREATE UNIQUE INDEX idx_lab_revision_fingerprint
            ON lab_observation_revision (observation_id, content_fingerprint);
        """)
        try db.execute("""
        CREATE INDEX idx_lab_revision_current
            ON lab_observation_revision (observation_id, is_current);
        """)

        // Document metadata only. The bytes live in an app-managed directory
        // addressed by `relative_path`; see Documents/DocumentStore.swift and
        // docs/architecture/health-data-foundation.md §16.
        try db.execute("""
        CREATE TABLE lab_document (
            id            TEXT PRIMARY KEY,
            kind          TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            original_name TEXT,
            byte_count    INTEGER,
            sha256        TEXT,
            added_at      TEXT NOT NULL
        );
        """)
        try db.execute("""
        CREATE TABLE lab_document_link (
            document_id  TEXT NOT NULL REFERENCES lab_document(id) ON DELETE CASCADE,
            target_table TEXT NOT NULL,
            target_id    TEXT NOT NULL,
            role         TEXT NOT NULL,
            PRIMARY KEY (document_id, target_table, target_id, role)
        );
        """)
    }
}

/// Migration 004 — persisted health samples.
///
/// Closes the gap where `HealthProvider.changes(in:since:)` returned samples
/// that nothing stored. Deletion is soft, because a source withdrawing a
/// sample is a fact about the source, not permission to erase history.
public enum Migration004_HealthSamples: Migration {
    public static let version = 4
    public static let name = "health_samples"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE health_sample (
            id                         TEXT PRIMARY KEY,
            source_system              TEXT NOT NULL,
            external_id                TEXT NOT NULL,
            domain                     TEXT NOT NULL,
            start_at                   TEXT NOT NULL,
            end_at                     TEXT NOT NULL,
            value                      REAL,
            unit                       TEXT,
            source_name                TEXT,
            recorded_at                TEXT NOT NULL,
            recorded_tz_offset_minutes INTEGER,
            deleted_at                 TEXT
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_health_sample_source
            ON health_sample (source_system, external_id);
        """)
        try db.execute("""
        CREATE INDEX idx_health_sample_domain_time
            ON health_sample (domain, start_at);
        """)
    }
}
