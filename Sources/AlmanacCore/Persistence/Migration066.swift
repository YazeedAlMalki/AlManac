import Foundation

/// Migration 066 — every source behind an exercise record.
///
/// The owner's rule (2026-10-19): one record per real exercise across
/// workout-guide, free-exercise-db and wger, keeping every source's
/// attribution and which source each field came from. `exerciseCatalog` keeps
/// one row per record; this table holds one row per source that contributed to
/// it, with that source's own field values as JSON. Two sources that disagree
/// on a field are two rows here, so both values are kept
/// (`docs/features/exercise-merge-log.md` lists the disagreements).
public enum Migration066_ExerciseSource: Migration {
    public static let version = 66
    public static let name = "exercise_source"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE exerciseSource (
            id                  INTEGER PRIMARY KEY,
            exerciseCatalogId   INTEGER NOT NULL REFERENCES exerciseCatalog(id),
            sourceId            TEXT NOT NULL,
            sourceExerciseId    TEXT NOT NULL,
            licenseGroup        TEXT NOT NULL,
            licenseAuthor       TEXT,
            fields              TEXT NOT NULL,
            createdAt           TEXT NOT NULL,
            UNIQUE(sourceId, sourceExerciseId)
        );
        """)
        try db.execute("CREATE INDEX idx_exercise_source_catalog ON exerciseSource(exerciseCatalogId);")
    }
}
