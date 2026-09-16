import Foundation

/// Migration 018 — Slice 7 (Body Composition & Wellness), the part of §5.18
/// and §5.20 not already built by Migration014's five wellness stores.
///
/// Transcribed verbatim from `../../../almanac-tech-spec-v1.0.md`, camelCase,
/// following the Migration014-onward convention
/// (`docs/architecture/spec-reconciliation.md` §5). See
/// `docs/features/body-composition.md` for the design this implements.
///
/// Deliberately excluded:
/// - `progress_photo` (§5.18) — the owner deferred progress photos to a later
///   update (`docs/features/body-composition.md` §1); no schema for it yet.
/// - `lab_result` (§5.18) — superseded by this repository's own ~14-table
///   laboratory module (`docs/architecture/spec-reconciliation.md` §4.4).
/// - `mood_log`, `soreness_log`, `injury_note` (§5.20) — already shipped in
///   Migration014.
public enum Migration018_BodyCompositionAndWellness: Migration {
    public static let version = 18
    public static let name = "body_composition_and_wellness"

    public static func up(_ db: Database) throws {
        // §5.18 Body Composition Tables (minus progress_photo, lab_result).
        //
        // `metric` includes 'weight' — this is the sole home for it. A prior
        // HealthKit bridge (Slice 2) wrote bodyMass into vitals_record; that
        // is corrected as part of this migration's follow-up work, not the
        // schema itself (docs/architecture/spec-reconciliation.md §7).
        try db.execute("""
        CREATE TABLE body_composition_measurement (
            id              INTEGER PRIMARY KEY,
            timestamp       TEXT NOT NULL,
            timezoneOffset  TEXT,
            logicalDay      TEXT NOT NULL,
            metric          TEXT NOT NULL,
            value           REAL NOT NULL,
            unit            TEXT NOT NULL,
            source          TEXT NOT NULL,
            conditions      TEXT NOT NULL DEFAULT 'unknown',
            healthKitUUID   TEXT UNIQUE,
            pendingHealthKitWrite INTEGER NOT NULL DEFAULT 0,
            createdAt       TEXT NOT NULL,
            deletedAt       TEXT
        );
        """)
        try db.execute("CREATE INDEX idx_body_comp_metric ON body_composition_measurement(metric, timestamp);")
        // Matches BodyCompositionMeasurementHealthBridge's
        // `ON CONFLICT(source, healthKitUUID) WHERE healthKitUUID IS NOT NULL`
        // exactly — SQLite requires the conflict target to match a real
        // index, textually, not just column-level UNIQUE. See Migration019
        // for the same bug already present in vitals_record.
        try db.execute("""
        CREATE UNIQUE INDEX idx_body_comp_source_hkuuid
            ON body_composition_measurement(source, healthKitUUID)
            WHERE healthKitUUID IS NOT NULL;
        """)

        try db.execute("""
        CREATE TABLE custom_measurement_definition (
            id      INTEGER PRIMARY KEY,
            name    TEXT NOT NULL UNIQUE,
            unit    TEXT NOT NULL,
            createdAt TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE custom_measurement_log (
            id              INTEGER PRIMARY KEY,
            definitionId    INTEGER NOT NULL REFERENCES custom_measurement_definition(id),
            timestamp       TEXT NOT NULL,
            logicalDay      TEXT NOT NULL,
            value           REAL NOT NULL,
            notes           TEXT,
            createdAt       TEXT NOT NULL
        );
        """)

        // §5.20 Wellness Tables (supplement + context, the parts not built yet).
        try db.execute("""
        CREATE TABLE supplement_plan (
            id          INTEGER PRIMARY KEY,
            name        TEXT NOT NULL,
            doseAmount  REAL NOT NULL,
            doseUnit    TEXT NOT NULL,
            frequency   TEXT NOT NULL,
            timingNotes TEXT,
            isActive    INTEGER NOT NULL DEFAULT 1,
            createdAt   TEXT NOT NULL,
            updatedAt   TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE supplement_log (
            id              INTEGER PRIMARY KEY,
            planId          INTEGER NOT NULL REFERENCES supplement_plan(id),
            timestamp       TEXT NOT NULL,
            logicalDay      TEXT NOT NULL,
            taken           INTEGER NOT NULL DEFAULT 1,
            notes           TEXT,
            createdAt       TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE context_event (
            id          INTEGER PRIMARY KEY,
            date        TEXT NOT NULL,
            tags        TEXT NOT NULL DEFAULT '[]',
            notes       TEXT,
            createdAt   TEXT NOT NULL,
            updatedAt   TEXT NOT NULL
        );
        """)
    }
}
