import Foundation

/// Migration 046 — `import_job`, the record that a laboratory import ran and how
/// it went.
///
/// **This is a repo-owned table, not a §5 table.** The spec's own inventory
/// lists import jobs as explicitly *not* in scope (technical spec v0.2's
/// "Not covered in v0.2" line names them), so there is no clause to transcribe
/// and no §-number to cite. It follows the snake_case of `lab_report` and
/// `lab_observation`, which it reads, rather than the camelCase of the §5
/// tables this repo added from Migration014 on — a job is about laboratory
/// rows, and `reports_created` sits one line away from `source_report_id`.
///
/// **The status is a TEXT column holding a closed set, not free text.** The
/// alternative is a status nobody can enumerate, and the screen that lists
/// imports has to be able to say "these need you". `LabImportStatus` is the
/// one definition of that set; this column is where it lands.
///
/// **The outcome counts are a reconciled view of the observations, not a tally
/// the import kept.** `rows_matched`, `rows_ambiguous` and `rows_unmatched` are
/// written by `LabImportJobReconciler` from the `lab_observation` rows the
/// import produced. The alternative — freezing the numbers at import time —
/// makes them wrong the moment a person fixes a row by hand, or teaches the
/// catalog an alias the import could not have known. `observations_created`,
/// `observations_unchanged`, `observations_revised` and `invalid_rows` *are*
/// frozen, because they describe what the attempt did and nothing later can
/// change that.
///
/// **`catalog_generation` is what makes a closed job reopenable.** It holds the
/// number of `lab_catalog_alias` rows when the job was last reconciled. The
/// reconciler's queue is "unresolved, or behind the current generation", so
/// adding an alias that resolves four previously unmatched rows updates that
/// job's outcome on the next pass. Without it a job could be closed once and
/// never looked at again, which would make the whole screen a snapshot of the
/// catalog as it stood on the day the file was imported — the exact opposite of
/// what a later alias is for.
///
/// The generation is *derived* (`COUNT(*)` over the alias table) rather than
/// held in a counter row, because a counter that can drift from the thing it
/// counts is a second source of truth for the same fact. Aliases are only ever
/// inserted — `addAlias` upserts on `(analyte_id, alias_fold)`, so re-adding a
/// name that already matches nothing new changes no rows — which is what makes
/// the count monotonic enough to be a generation.
///
/// **`status = 'unresolved'` is a real, expected state.** It is what a job is
/// written as when the import has run but has not yet been reconciled. It is
/// deliberately not a status a person is shown as a problem: it is the
/// reconciler's queue.
public enum Migration046_LabImportJob: Migration {
    public static let version = 46
    public static let name = "import_job"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE import_job (
            id                        INTEGER PRIMARY KEY,
            source_name               TEXT,
            source_system             TEXT NOT NULL,
            status                    TEXT NOT NULL,
            started_at                TEXT NOT NULL,
            finished_at               TEXT,
            source_report_ids         TEXT NOT NULL DEFAULT '[]',
            groups                    INTEGER NOT NULL DEFAULT 0,
            reports_created           INTEGER NOT NULL DEFAULT 0,
            reports_unchanged         INTEGER NOT NULL DEFAULT 0,
            report_conflicts          INTEGER NOT NULL DEFAULT 0,
            observations_created      INTEGER NOT NULL DEFAULT 0,
            observations_unchanged    INTEGER NOT NULL DEFAULT 0,
            observations_revised      INTEGER NOT NULL DEFAULT 0,
            invalid_rows              INTEGER NOT NULL DEFAULT 0,
            rows_usable               INTEGER NOT NULL DEFAULT 0,
            rows_matched              INTEGER NOT NULL DEFAULT 0,
            rows_ambiguous            INTEGER NOT NULL DEFAULT 0,
            rows_unmatched            INTEGER NOT NULL DEFAULT 0,
            catalog_generation        INTEGER NOT NULL DEFAULT -1,
            failure_reason            TEXT
        );
        """)
        // The listing reads the jobs that need a person, newest first. A
        // partial index would be smaller but this table has one row per import
        // and is read whole.
        try db.execute("CREATE INDEX idx_import_job_started ON import_job (started_at DESC);")
        try db.execute("CREATE INDEX idx_import_job_status ON import_job (status);")
        // The reconciler's queue: jobs whose outcome was worked out against an
        // older catalog than the one that exists now. `catalog_generation` is
        // the count of `lab_catalog_alias` rows at the moment of the last
        // reconciliation, so "behind" means the catalog has learned something
        // since — see the header comment for why that is the trigger.
        try db.execute("""
        CREATE INDEX idx_import_job_stale
            ON import_job (catalog_generation, status);
        """)
    }
}
