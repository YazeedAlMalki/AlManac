import Foundation

/// Migration 016 — Slice 4 (Training/Exercise) schema.
///
/// Not transcribed from the original tech spec's §5.17 "Training Tables"
/// (`exercise`, `program`, `session`, `set_entry`, `workout_day`,
/// `workout_day_exercise`, `workout_merge_record`) — that shape is the
/// sets/reps/load model `prescription-model-v0.1.md` argues against at
/// length (§1: "silently corrupts every [training] kind" that isn't a
/// straight barbell lift). Nothing in §5.17 was ever built, so this is two
/// specs disagreeing before either is code, not implementation-exceeds-spec
/// like the four 2026-09-16 collisions. See
/// `docs/architecture/spec-reconciliation.md` §6 for the full note — this
/// migration follows the prescription model, camelCase, per the Slice 4
/// execution instructions (2026-09-16).
///
/// Four tables:
/// - `exerciseCatalog` — the movement library. `(sourceId, exerciseId)` is
///   the source-of-record key (e.g. `("wger", "132")`); `prescriptionType`
///   is Almanac's own mapping per §6, not something any source dictionary
///   carries.
/// - `prescribedWorkout` — a reusable template: a name plus a container
///   shape (§3). Templates are optional; a session can exist without one.
/// - `workoutSession` — one completed training session.
/// - `workoutBout` — one bout of work within a session, tied to a catalog
///   exercise. `prescriptionType`/`containerType` are copied onto the bout
///   at logging time rather than joined from the catalog row, because a
///   catalog mapping correction later must never reinterpret history (same
///   principle as nutrition's per-value provenance).
///
/// Prescribed vs. actual, not sets/reps/load: the twelve prescription types
/// disagree about which fields are the plan and which are the outcome
/// (§1, §2 — an AMRAP prescribes time and measures rounds; a straight set
/// prescribes reps and measures completion). Rather than one table per type
/// — real per §6.1's finding that 5 of 12 types have zero source content
/// today, so most of those tables would sit empty — `workoutBout` carries
/// the union of fields the twelve types need, all nullable, sparse by type.
/// A generic value table (type/key/value) was the other option; a wide,
/// nullable row was chosen to match how `vitals_record` and `mood_log`
/// already do "one flexible fact table" in this schema, and because the
/// twelve types (§2) are closed and enumerable, not open-ended like
/// vitals metrics.
///
/// Soft delete follows `nutrition_log`'s working pattern (`deletedAt`
/// nullable, cleared on revival, queries filter `WHERE deletedAt IS NULL`)
/// — not `sleep_episode`'s, which references a `deletedAt` column that was
/// never added to that table (found 2026-09-16, left for the HealthKit
/// track; see the collision-resolution commit's note).
public enum Migration016_TrainingSchema: Migration {
    public static let version = 16
    public static let name = "training_schema"

    /// The twelve prescription types (prescription-model-v0.1.md §2).
    public static let prescriptionTypes = [
        "reps_load", "reps_bodyweight", "time_under_load", "distance", "duration",
        "rounds_for_time", "work_in_time", "interval", "quality_reps",
        "hold_stretch", "release", "session_only"
    ]

    /// The ten container types (§3).
    public static let containerTypes = [
        "straight_sets", "superset", "circuit", "emom", "amrap", "for_time",
        "interval_block", "ladder", "skill_block", "flow"
    ]

    public static func up(_ db: Database) throws {
        let prescriptionCheck = prescriptionTypes.map { "'\($0)'" }.joined(separator: ", ")
        let containerCheck = containerTypes.map { "'\($0)'" }.joined(separator: ", ")

        try db.execute("""
        CREATE TABLE exerciseCatalog (
            id                  INTEGER PRIMARY KEY,
            sourceId            TEXT NOT NULL,
            exerciseId          TEXT NOT NULL,
            name                TEXT NOT NULL,
            category            TEXT,
            equipment           TEXT,
            force               TEXT,
            prescriptionType    TEXT NOT NULL CHECK(prescriptionType IN (\(prescriptionCheck))),
            licenseGroup        TEXT NOT NULL,
            confidence          TEXT CHECK(confidence IN ('high', 'medium', 'low') OR confidence IS NULL),
            notes               TEXT,
            deletedAt           TEXT,
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL,
            UNIQUE(sourceId, exerciseId)
        );
        """)
        try db.execute("CREATE INDEX idx_exercise_catalog_prescription_type ON exerciseCatalog(prescriptionType);")
        try db.execute("CREATE INDEX idx_exercise_catalog_name ON exerciseCatalog(name);")

        try db.execute("""
        CREATE TABLE prescribedWorkout (
            id              INTEGER PRIMARY KEY,
            name            TEXT NOT NULL,
            containerType   TEXT NOT NULL CHECK(containerType IN (\(containerCheck))),
            notes           TEXT,
            deletedAt       TEXT,
            createdAt       TEXT NOT NULL,
            updatedAt       TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE workoutSession (
            id                      INTEGER PRIMARY KEY,
            date                    TEXT NOT NULL,
            startTimestamp          TEXT,
            endTimestamp            TEXT,
            durationMinutes         INTEGER,
            rpe                     INTEGER CHECK(rpe IS NULL OR rpe BETWEEN 1 AND 10),
            notes                   TEXT,
            prescribedWorkoutId     INTEGER REFERENCES prescribedWorkout(id),
            deletedAt               TEXT,
            createdAt               TEXT NOT NULL,
            updatedAt               TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_workout_session_date ON workoutSession(date);")

        try db.execute("""
        CREATE TABLE workoutBout (
            id                          INTEGER PRIMARY KEY,
            sessionId                   INTEGER NOT NULL REFERENCES workoutSession(id),
            exerciseCatalogId           INTEGER NOT NULL REFERENCES exerciseCatalog(id),
            sequenceIndex               INTEGER NOT NULL DEFAULT 0,
            prescriptionType            TEXT NOT NULL CHECK(prescriptionType IN (\(prescriptionCheck))),
            containerType               TEXT CHECK(containerType IS NULL OR containerType IN (\(containerCheck))),
            -- Prescribed: what was planned. Sparse by prescriptionType (§2).
            prescribedSets              INTEGER,
            prescribedReps              INTEGER,
            prescribedLoadKg            REAL,
            prescribedDurationSeconds   REAL,
            prescribedDistanceMeters    REAL,
            prescribedWorkSeconds       REAL,
            prescribedRestSeconds       REAL,
            prescribedRounds            INTEGER,
            -- Actual: what was measured. Also sparse by prescriptionType —
            -- e.g. work_in_time prescribes time and measures actualRounds
            -- + actualReps; rounds_for_time prescribes work and measures
            -- elapsedSeconds. Never inferred from the prescribed side.
            actualSets                  INTEGER,
            actualReps                  INTEGER,
            actualLoadKg                REAL,
            actualDurationSeconds       REAL,
            actualDistanceMeters        REAL,
            actualRounds                INTEGER,
            elapsedSeconds              REAL,
            avgHeartRate                INTEGER,
            rpe                         INTEGER CHECK(rpe IS NULL OR rpe BETWEEN 1 AND 10),
            techniqueRating             TEXT,
            notes                       TEXT,
            deletedAt                   TEXT,
            createdAt                   TEXT NOT NULL,
            updatedAt                   TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_workout_bout_session ON workoutBout(sessionId);")
        try db.execute("CREATE INDEX idx_workout_bout_exercise ON workoutBout(exerciseCatalogId);")
    }
}
