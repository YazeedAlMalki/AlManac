import Foundation

/// Migration 055 — the exercises a workout template prescribes.
///
/// The owner's decision (2026-10-06): a template is **exercises, but editable**.
/// Applying one fills a session with its exercises as a starting point, and the
/// session is then his to change. Until this, `prescribedWorkout` held only a
/// name, a container shape and notes (Migration 016), so there was nothing to
/// apply.
///
/// One row per exercise, in order, carrying the same nullable `prescribed*`
/// columns `workoutBout` has — so applying is a copy column for column, and the
/// sparse-by-type rule of Migration 016 holds unchanged. `prescriptionType` is
/// copied from the catalog when the item is added, as a bout copies it, so a
/// later catalog correction never reinterprets a template.
///
/// No `deletedAt`: a template's items are replaced as a whole
/// (`PrescribedWorkoutStore.setItems`), the way a dish's recipe is. History is
/// safe because applying **copies** the values onto the session's bouts; no
/// bout ever points at an item.
public enum Migration055_PrescribedWorkoutItem: Migration {
    public static let version = 55
    public static let name = "prescribed_workout_item"

    public static func up(_ db: Database) throws {
        let prescriptionCheck = Migration016_TrainingSchema.prescriptionTypes
            .map { "'\($0)'" }.joined(separator: ", ")
        try db.execute("""
        CREATE TABLE prescribedWorkoutItem (
            id                          INTEGER PRIMARY KEY,
            prescribedWorkoutId         INTEGER NOT NULL REFERENCES prescribedWorkout(id),
            exerciseCatalogId           INTEGER NOT NULL REFERENCES exerciseCatalog(id),
            sequenceIndex               INTEGER NOT NULL,
            prescriptionType            TEXT NOT NULL CHECK(prescriptionType IN (\(prescriptionCheck))),
            prescribedSets              INTEGER,
            prescribedReps              INTEGER,
            prescribedLoadKg            REAL,
            prescribedDurationSeconds   REAL,
            prescribedDistanceMeters    REAL,
            prescribedWorkSeconds       REAL,
            prescribedRestSeconds       REAL,
            prescribedRounds            INTEGER,
            createdAt                   TEXT NOT NULL
        );
        CREATE UNIQUE INDEX idx_prescribed_workout_item_order
            ON prescribedWorkoutItem (prescribedWorkoutId, sequenceIndex);
        """)
    }
}
