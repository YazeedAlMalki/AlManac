import Foundation

/// Migration 049 — the program layer above a session: `trainingProgram`,
/// `programDay`, `programDayExercisePool`, plus the `workoutSession` and
/// `workoutBout` columns that let a session be a *pass through a rotation*
/// rather than an ad-hoc log.
///
/// ## What this is
///
/// Slice 4 (Migration016) built the layer **at and below a session**: an
/// exercise catalogue, a thin template, a session and a bout. The 2026-10-01
/// handoff adds the layer **above** one — "I follow PPL", each day holds a pool
/// of exercises that rotate across sessions, and the app generates that
/// session's exercise list. `docs/features/training.md` §5 lists "no
/// `program`/multi-week structure" as a deliberate absence rather than a gap;
/// this is that structure, and the handoff is where it got designed.
///
/// Note what is deliberately *not* here, per §5: no multi-week dated plan, no
/// deload-week data model, and no automatic scheduling. Decision "day selection
/// is always manual" is a product decision, so nothing in this schema assumes a
/// calendar can drive a session.
///
/// ## Two table names in the handoff do not exist in this repo, and the
/// collision is recorded rather than quietly resolved
///
/// The handoff's schema sketch names **`workout_session`** and
/// **`workout_session_set`**. Neither is a table here: they are
/// `workoutSession` and `workoutBout`, from Migration016. This is the same
/// snake_case-vs-camelCase split `spec-reconciliation.md` §3 records across the
/// schema, and it is the reason the extension below reads `ALTER TABLE
/// workoutBout` — following the handoff literally would mean creating a second
/// table for work `workoutBout` already holds.
///
/// Two of the four columns the handoff asks for on `workout_session_set`
/// **already exist**:
///
/// | Handoff column | Already present as | Since |
/// |---|---|---|
/// | `prescribed_reps` | `workoutBout.prescribedReps` | Migration016 |
/// | `prescribed_load_kg` | `workoutBout.prescribedLoadKg` | Migration016 |
///
/// So only two columns are added to `workoutBout`, not four. Adding
/// `prescribed_reps` a second time under a second name would give one bout two
/// columns claiming the same prescription, with nothing saying which is the
/// plan — which is precisely the ambiguity Migration016's prescribed/actual
/// split exists to prevent.
///
/// ## camelCase, matching the module
///
/// Every Training table is camelCase — `exerciseCatalog`, `prescribedWorkout`,
/// `workoutSession`, `workoutBout`, `exerciseMuscle` — while the handoff's
/// sketch is snake_case. Migration044's header states the rule this follows:
/// *"snake_case, matching its table rather than the spec… a new column is not
/// the place to half-apply it."* The new tables are camelCase; the two altered
/// tables gain camelCase columns beside camelCase columns. The one place the
/// handoff's shape is kept verbatim is `progression_condition`'s *value*
/// vocabulary, which is quoted text (`all_reps_completed`) and is checked in
/// `ProgressionCondition`.
///
/// ## `prescribed*` on the pool item, named to match the log it is copied to
///
/// The handoff lists `sets, reps, load_kg, duration_s, rest_s`. They are named
/// `prescribedSets` / `prescribedReps` / `prescribedLoadKg` /
/// `prescribedDurationSeconds` / `prescribedRestSeconds` so that this table and
/// `workoutBout` speak one language for the same five numbers. A pool item's
/// prescription **is copied onto the bout** when a session starts — the
/// `prescribed*` prefix is then literally true of both, and the key rule from
/// the handoff ("the prescription never changes based on what was logged") has
/// one spelling rather than two.
///
/// ## `is_active` is not `deletedAt`, and the difference is the feature
///
/// A soft-deleted row is one that was in a pool and left it. An `is_active =
/// false` row is one the user *kept* — Decision 3's "equipment not owned at
/// this gym, a variation the user dislikes, or any condition that holds every
/// time" — and it is **re-offerable**, which is why rotation reads it by
/// `is_active` rather than by `deletedAt IS NULL`, and why the rotation tests
/// distinguish the two. Making permanent removal a soft delete would make it
/// indistinguishable from an exercise the user tidied out of the editor.
///
/// ## `wasSkippedForSession` is on the bout, and that is what makes a skip a log
///
/// Decision 3's per-session skip writes **no pool state at all** — that is the
/// entire content of "holds its position". So the only record that it happened
/// is on the log side: the skipped slot gets a bout row with
/// `wasSkippedForSession = 1` and no actuals. That is why the column exists and
/// why it defaults to 0 rather than being nullable — a skipped slot is a fact
/// about the session, and every other bout is `false`.
public enum Migration049_TrainingProgram: Migration {
    public static let version = 49
    public static let name = "training_program"

    public static func up(_ db: Database) throws {
        // A *program* is the split above a day: "My PPL", "Mobility".
        // Decision 6 is that several may be active at once, so there is no
        // is-active column and nothing to arbitrate between two programs.
        try db.execute("""
        CREATE TABLE trainingProgram (
            id          INTEGER PRIMARY KEY,
            name        TEXT    NOT NULL,
            notes       TEXT,
            deletedAt   TEXT,
            createdAt   TEXT    NOT NULL,
            updatedAt   TEXT    NOT NULL
        );
        """)

        // One part of the split. `label` is free text, not an enum: "Push" /
        // "Pull" / "Legs" is a PPL's vocabulary, not the app's, and a mobility
        // routine's days are named by the user. Migration026's header states the
        // same reasoning for `workoutSession.sessionType`.
        try db.execute("""
        CREATE TABLE programDay (
            id          INTEGER PRIMARY KEY,
            programId   INTEGER NOT NULL REFERENCES trainingProgram(id),
            label       TEXT    NOT NULL,
            deletedAt   TEXT,
            createdAt   TEXT    NOT NULL,
            updatedAt   TEXT    NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_program_day_program ON programDay(programId);")

        // The pool a day rotates through. This table **is** the prescription:
        // the handoff's key rule is that it never changes because of what was
        // logged, only because the user edited it or set `isActive = false`.
        try db.execute("""
        CREATE TABLE programDayExercisePool (
            id                       INTEGER PRIMARY KEY,
            programDayId             INTEGER NOT NULL REFERENCES programDay(id),
            exerciseCatalogId        INTEGER NOT NULL REFERENCES exerciseCatalog(id),
            -- Where this item sits in the rotation. Advanced by completed
            -- sessions only, never by a gap in the calendar (Decision 2), and
            -- never by a per-session skip (Decision 3).
            rotationPosition         INTEGER NOT NULL,
            -- Which slot of a generated session this item occupies. Distinct
            -- from `rotationPosition`: the position says *when in the cycle*,
            -- this says *how many exercises a session of this day has*. See
            -- `RotationEngine`.
            positionWithinSession    INTEGER NOT NULL,
            -- Decision 3's permanent removal. Not `deletedAt` — see the header.
            isActive                 INTEGER NOT NULL DEFAULT 1,
            prescriptionType         TEXT    NOT NULL CHECK(prescriptionType IN (\(prescriptionTypeCheck))),
            containerType            TEXT    CHECK(containerType IS NULL OR containerType IN (\(containerTypeCheck))),
            prescribedSets           INTEGER,
            prescribedReps           INTEGER,
            prescribedLoadKg         REAL,
            prescribedDurationSeconds REAL,
            prescribedRestSeconds    REAL,
            -- Decision 4: off by default, enabled per exercise, with a
            -- user-defined increment and condition. `progressionIncrementKg` has
            -- no default because a rule with no increment is not a rule; the
            -- store refuses the pairing.
            progressionEnabled       INTEGER NOT NULL DEFAULT 0,
            progressionIncrementKg   REAL,
            progressionCondition     TEXT    CHECK(progressionCondition IS NULL OR progressionCondition IN (\(progressionConditionCheck))),
            notes                    TEXT,
            deletedAt                TEXT,
            createdAt                TEXT    NOT NULL,
            updatedAt                TEXT    NOT NULL
        );
        """)
        // The rotation read is "the active items of this day, in cycle order",
        // asked once per generated session. Without this the sort is over every
        // item the day has ever had, including the permanently removed ones the
        // read has to filter out on the way.
        try db.execute("""
        CREATE INDEX idx_pool_day_rotation
            ON programDayExercisePool(programDayId, isActive, rotationPosition);
        """)
        // Progression and both progress graphs ask the same question from the
        // other direction: "every pool item using this exercise", so a
        // progression suggestion can be found from the item and a graph can be
        // drawn without walking every program.
        try db.execute("""
        CREATE INDEX idx_pool_exercise
            ON programDayExercisePool(exerciseCatalogId);
        """)

        // --- workoutSession: the three columns that make a session a rotation pass
        try db.execute("""
        ALTER TABLE workoutSession ADD COLUMN programDayId
            INTEGER REFERENCES programDay(id);
        """)
        // Which pass through the pool this session was. Nullable with a session
        // that is not part of any program — the ad-hoc session every existing
        // test and every HealthKit-derived workout is.
        try db.execute("ALTER TABLE workoutSession ADD COLUMN rotationIndex INTEGER;")
        // Whether the user said yes to "Factor in your readiness score?" when
        // starting. NOT NULL with a false default rather than nullable: this
        // records a decision, and the decision for a session nobody asked is
        // "no", which is the same answer as being asked and declining.
        try db.execute("""
        ALTER TABLE workoutSession ADD COLUMN readinessAdjusted
            INTEGER NOT NULL DEFAULT 0;
        """)
        try db.execute("""
        CREATE INDEX idx_workout_session_program_day
            ON workoutSession(programDayId, rotationIndex);
        """)

        // --- workoutBout: two columns, not four — see the header on the two that
        // already exist. `prescribedReps` / `prescribedLoadKg` arrived in 016.
        try db.execute("""
        ALTER TABLE workoutBout ADD COLUMN equipmentVariant
            TEXT CHECK(equipmentVariant IS NULL OR equipmentVariant IN (\(equipmentVariantCheck)));
        """)
        try db.execute("""
        ALTER TABLE workoutBout ADD COLUMN wasSkippedForSession
            INTEGER NOT NULL DEFAULT 0;
        """)
    }

    // The three enumerations, quoted from the sources that own them rather than
    // retyped, so this migration cannot drift from `Migration016` or from
    // `ProgramVocabulary` without one of those two breaking first.
    private static var prescriptionTypeCheck: String {
        Migration016_TrainingSchema.prescriptionTypes.map { "'\($0)'" }.joined(separator: ", ")
    }
    private static var containerTypeCheck: String {
        Migration016_TrainingSchema.containerTypes.map { "'\($0)'" }.joined(separator: ", ")
    }
    private static var progressionConditionCheck: String {
        ProgressionCondition.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    }
    private static var equipmentVariantCheck: String {
        EquipmentVariant.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    }
}
