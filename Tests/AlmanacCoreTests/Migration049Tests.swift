import Foundation
import Testing
@testable import AlmanacCore

/// Migration 049 — the program layer above a session.
///
/// Two kinds of check, in the order that has caught real problems in this repo
/// (see `Migration048Tests`):
///
/// - *Shape*: the tables and columns exist, with the right types, nullability
///   and CHECK constraints. Catches a typo in an `ALTER TABLE` and a value the
///   model should refuse.
/// - *Compatibility*: a database migrated through 48 and then through 49 holds
///   exactly the same training rows as one migrated straight to 49. This is the
///   only kind of check that can catch a migration described as additive that
///   quietly rewrites a value on the way past.
///
/// The third section is the one that is specific to this migration: the
/// handoff's schema sketch does not match the schema that exists, and two of
/// its columns already exist under other names. Those are pinned here so the
/// collision stays *recorded* rather than being re-resolved — silently — by
/// whoever reads the handoff next.
@Suite("Migration 049 — training program")
struct Migration049Tests {

    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func columns(_ db: Database, table: String) throws -> [String: (type: String, notNull: Bool, defaultValue: String?)] {
        var result: [String: (type: String, notNull: Bool, defaultValue: String?)] = [:]
        for row in try db.query("PRAGMA table_info(\(table));") {
            guard let name = row.string("name") else { continue }
            // PRAGMA reports booleans as integers.
            result[name] = (row.string("type") ?? "", (row.int("notnull") ?? 0) == 1, row.string("dflt_value"))
        }
        return result
    }

    private func tableNames(_ db: Database) throws -> Set<String> {
        Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table';").compactMap { $0.string("name") })
    }

    // MARK: - The three new tables

    @Test("All three program tables exist, and each parent links to the one above it")
    func tablesExist() throws {
        let db = try migrated()
        let tables = try tableNames(db)
        for name in ["trainingProgram", "programDay", "programDayExercisePool"] {
            #expect(tables.contains(name), "\(name) is missing")
        }
        #expect(try db.query("PRAGMA foreign_key_list(programDay);").contains { $0.string("table") == "trainingProgram" })
        #expect(try db.query("PRAGMA foreign_key_list(programDayExercisePool);").contains { $0.string("table") == "programDay" })
        // The pool points at the *catalogue*, not at a copy of the exercise: the
        // prescription lives here, but which movement it is for is the
        // catalogue's identity and must not be duplicated into this table.
        #expect(try db.query("PRAGMA foreign_key_list(programDayExercisePool);").contains { $0.string("table") == "exerciseCatalog" })
    }

    @Test("A pool item carries the rotation position, the slot, and the prescription")
    func poolColumns() throws {
        let db = try migrated()
        let pool = try columns(db, table: "programDayExercisePool")
        for name in ["programDayId", "exerciseCatalogId", "rotationPosition", "positionWithinSession",
                     "prescriptionType", "prescribedSets", "prescribedReps", "prescribedLoadKg",
                     "prescribedDurationSeconds", "prescribedRestSeconds",
                     "progressionEnabled", "progressionIncrementKg", "progressionCondition", "notes"] {
            #expect(pool[name] != nil, "programDayExercisePool.\(name) is missing")
        }
        #expect(pool["rotationPosition"]?.notNull == true)
        #expect(pool["positionWithinSession"]?.notNull == true)
        #expect(pool["prescriptionType"]?.notNull == true)
        // Everything else in the prescription is nullable per prescription type —
        // the same sparse-by-type discipline `workoutBout` follows.
        for name in ["prescribedSets", "prescribedReps", "prescribedLoadKg",
                     "prescribedDurationSeconds", "prescribedRestSeconds"] {
            #expect(pool[name]?.notNull == false, "pool.\(name) should be nullable")
        }
        // Decision 4: progressive overload is off by default. A `true` default
        // would start suggesting loads for exercises nobody opted in.
        #expect(pool["progressionEnabled"]?.defaultValue == "0")
        // Decision 3: `is_active` defaults true, and is a separate column from
        // `deletedAt` — a permanently removed item is kept, not deleted.
        #expect(pool["isActive"]?.defaultValue == "1")
        #expect(pool["isActive"]?.notNull == true)
        #expect(pool["deletedAt"] != nil)
    }

    // MARK: - Constraints: the closed sets refuse what they should

    @Test("A prescription type outside the twelve is refused")
    func prescriptionTypeIsConstrained() throws {
        let db = try migrated()
        let store = ProgramStore(db: db)
        let programId = try store.create(name: "PPL")
        let dayId = try ProgramDayStore(db: db).create(programId: programId, label: "Push")
        let exerciseId = try seedExercise(db, name: "Bench Press")

        #expect(throws: (any Error).self, "prescriptionType accepted 'push_ups'") {
            try db.run("""
            INSERT INTO programDayExercisePool
                (programDayId, exerciseCatalogId, rotationPosition, positionWithinSession,
                 prescriptionType, createdAt, updatedAt)
            VALUES (?, ?, 0, 0, 'push_ups', '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
            """, [.integer(dayId), .integer(exerciseId)])
        }

        // The twelve themselves all write. This is the drift guard: the CHECK is
        // built from `Migration016`'s array, so if the enum and the array ever
        // disagree it shows up as a migration that will not create its table.
        for kind in PrescriptionKind.allCases {
            try db.run("""
            INSERT INTO programDayExercisePool
                (programDayId, exerciseCatalogId, rotationPosition, positionWithinSession,
                 prescriptionType, createdAt, updatedAt)
            VALUES (?, ?, ?, 1, ?, '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
            """, [.integer(dayId), .integer(exerciseId), .integer(Int64(kind.rawValue.count + 100)), .text(kind.rawValue)])
        }
    }

    @Test("An equipment variant outside the four is refused, and all four write")
    func equipmentVariantIsConstrained() throws {
        let db = try migrated()
        let sessionId = try WorkoutSessionStore(db: db).log(WorkoutSessionDraft(date: "2026-10-01"))
        let exerciseId = try seedExercise(db, name: "Cable Fly")
        let boutId = try WorkoutBoutStore(db: db).log(WorkoutBoutDraft(
            sessionId: sessionId, exerciseCatalogId: exerciseId, prescriptionType: "reps_load"))

        for variant in EquipmentVariant.allCases {
            try db.run("UPDATE workoutBout SET equipmentVariant = ? WHERE id = ?;",
                       [.text(variant.rawValue), .integer(boutId)])
            #expect(try db.query("SELECT equipmentVariant FROM workoutBout WHERE id = ?;", [.integer(boutId)])
                .first?.string("equipmentVariant") == variant.rawValue)
        }
        // Decision 1 names four. A free-text fifth would be how "DB" and "db"
        // become two lines on a graph that should show one.
        for bad in ["DB", "kettlebell", "", "Bodyweight"] {
            #expect(throws: (any Error).self, "equipmentVariant accepted \(bad.debugDescription)") {
                try db.run("UPDATE workoutBout SET equipmentVariant = ? WHERE id = ?;",
                           [.text(bad), .integer(boutId)])
            }
        }
        // Null stays legal: a bodyweight movement has no variant, and every bout
        // logged before this migration has none recorded.
        try db.run("UPDATE workoutBout SET equipmentVariant = NULL WHERE id = ?;", [.integer(boutId)])
    }

    @Test("A progression condition outside the named set is refused")
    func progressionConditionIsConstrained() throws {
        let db = try migrated()
        let store = ProgramStore(db: db)
        let programId = try store.create(name: "PPL")
        let dayId = try ProgramDayStore(db: db).create(programId: programId, label: "Push")
        let exerciseId = try seedExercise(db, name: "Overhead Press")

        // Only `all_reps_completed` is named by the handoff, so only it writes.
        try db.run("""
        INSERT INTO programDayExercisePool
            (programDayId, exerciseCatalogId, rotationPosition, positionWithinSession,
             prescriptionType, progressionEnabled, progressionIncrementKg, progressionCondition,
             createdAt, updatedAt)
        VALUES (?, ?, 0, 0, 'reps_load', 1, 2.5, 'all_reps_completed',
                '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
        """, [.integer(dayId), .integer(exerciseId)])

        for bad in ["felt_easy", "ALL_REPS_COMPLETED", ""] {
            #expect(throws: (any Error).self, "progressionCondition accepted \(bad.debugDescription)") {
                try db.run("UPDATE programDayExercisePool SET progressionCondition = ?;", [.text(bad)])
            }
        }
    }

    // MARK: - The two workout tables

    @Test("workoutSession gains exactly the three program columns")
    func sessionColumns() throws {
        let db = try migrated()
        let session = try columns(db, table: "workoutSession")
        #expect(session["programDayId"] != nil)
        #expect(session["rotationIndex"] != nil)
        #expect(session["readinessAdjusted"] != nil)
        // Nullable: a session that is not part of a program is the ordinary case
        // for every ad-hoc and HealthKit-derived session.
        #expect(session["programDayId"]?.notNull == false)
        #expect(session["rotationIndex"]?.notNull == false)
        // The readiness answer records a decision, so it has a truthful default
        // rather than a null meaning "nobody asked".
        #expect(session["readinessAdjusted"]?.notNull == true)
        #expect(session["readinessAdjusted"]?.defaultValue == "0")
    }

    @Test("The two prescription columns the handoff asks for already existed, and are not duplicated")
    func prescribedColumnsAreNotDuplicated() throws {
        let db = try migrated()
        let bout = try columns(db, table: "workoutBout")
        // Present since Migration016 — the handoff's `prescribed_reps` /
        // `prescribed_load_kg` are these two under their own names.
        #expect(bout["prescribedReps"]?.type == "INTEGER")
        #expect(bout["prescribedLoadKg"]?.type == "REAL")
        // And only the two genuinely new ones were added.
        #expect(bout["equipmentVariant"] != nil)
        #expect(bout["wasSkippedForSession"]?.defaultValue == "0")
        #expect(bout["wasSkippedForSession"]?.notNull == true)
        // The snake_case spellings must not have been created as a second home
        // for the same prescription. This is the assertion that keeps a literal
        // reading of the handoff from being implemented later by accident.
        for absent in ["prescribed_reps", "prescribed_load_kg", "was_skipped_for_session",
                       "equipment_variant", "program_day_id", "rotation_index", "readiness_adjusted"] {
            #expect(bout[absent] == nil, "workoutBout.\(absent) should not exist")
            let onSession = try session_column(db, absent)
            #expect(!onSession, "workoutSession.\(absent) should not exist")
        }
    }

    private func session_column(_ db: Database, _ name: String) throws -> Bool {
        (try columns(db, table: "workoutSession"))[name] != nil
    }

    @Test("The handoff's workout_session_set is workoutBout, and no second table was created")
    func noSecondSetTable() throws {
        // The handoff's `workout_session_set` has no counterpart here; creating
        // one would put a second home for a bout's prescription and its actuals.
        let db = try migrated()
        let tables = try tableNames(db)
        #expect(!tables.contains("workout_session_set"))
        #expect(!tables.contains("workout_session"))
        #expect(tables.contains("workoutBout"))
        #expect(tables.contains("workoutSession"))
    }

    // MARK: - Upgrade from the previous schema

    @Test("Upgrading from 48 changes nothing about existing training data")
    func upgradeIsAdditive() throws {
        let at48 = try Database.inMemory()
        try MigrationRunner(
            migrations: AlmanacMigrations.all.filter { $0.version <= 48 }
        ).migrate(at48)

        // Real rows in the tables a person actually has data in.
        try at48.execute("""
        INSERT INTO exerciseCatalog (id, sourceId, exerciseId, name, prescriptionType, licenseGroup, createdAt, updatedAt)
        VALUES (1, 'workout-guide', '1', 'Barbell Bench Press', 'reps_load', 'cc-by-sa-4.0',
                '2026-09-20T00:00:00Z', '2026-09-20T00:00:00Z');
        INSERT INTO workoutSession (id, date, durationMinutes, rpe, sessionType, createdAt, updatedAt)
        VALUES (1, '2026-09-20', 55, 7, 'weightlifting', '2026-09-20T18:00:00Z', '2026-09-20T18:30:00Z');
        INSERT INTO workoutBout (id, sessionId, exerciseCatalogId, sequenceIndex, prescriptionType,
                                 prescribedSets, prescribedReps, prescribedLoadKg,
                                 actualSets, actualReps, actualLoadKg, createdAt, updatedAt)
        VALUES (1, 1, 1, 0, 'reps_load', 4, 6, 60.0, 4, 6, 62.5,
                '2026-09-20T18:00:00Z', '2026-09-20T18:30:00Z');
        INSERT INTO prescribedWorkout (id, name, containerType, createdAt, updatedAt)
        VALUES (1, 'Push Day', 'straight_sets', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
        """)
        let before = try snapshot(at48)

        try MigrationRunner(migrations: [Migration049_TrainingProgram.self]).migrate(at48)
        let after = try snapshot(at48)

        // The test that matters. A migration described as additive is a claim,
        // and the claim is worth nothing unless the rows are compared.
        #expect(after == before)

        // And the claim's other half: the five new columns exist and say nothing
        // about a session that predates them. A backfilled `programDayId` would
        // put this user's squat in a program they never wrote.
        let session = try at48.query("SELECT * FROM workoutSession WHERE id = 1;").first
        #expect(session?.int("programDayId") == nil)
        #expect(session?.int("rotationIndex") == nil)
        #expect(session?.int("readinessAdjusted") == 0)
        let bout = try at48.query("SELECT * FROM workoutBout WHERE id = 1;").first
        #expect(bout?.string("equipmentVariant") == nil)
        #expect(bout?.int("wasSkippedForSession") == 0)
    }

    @Test("An install that has never opened the program screen reads as empty, not guessed")
    func defaultsForAnUntouchedProgram() throws {
        let db = try migrated()
        let programStore = ProgramStore(db: db)
        #expect(try programStore.programs().isEmpty)
        // Nothing is seeded. A default "Push / Pull / Legs" program would be the
        // app inventing a training split nobody chose — the same rule the macro
        // targets recorded in CONTEXT.md.
        #expect(try ProgramDayStore(db: db).days(programId: 1).isEmpty)

        // A session that predates the program layer stays exactly as it was: no
        // program, no rotation, readiness not factored in.
        let sessionId = try WorkoutSessionStore(db: db).log(WorkoutSessionDraft(date: "2026-09-20"))
        let session = try WorkoutSessionStore(db: db).session(id: sessionId)
        #expect(session?.programDayId == nil)
        #expect(session?.rotationIndex == nil)
        #expect(session?.readinessAdjusted == false)
    }

    // MARK: - Helper

    private func seedExercise(_ db: Database, name: String) throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "workout-guide", exerciseId: name, name: name,
                                 prescriptionType: "reps_load", licenseGroup: "cc-by-sa-4.0"))
    }

    /// Every column of the four tables a training history lives in, as a
    /// comparable string.
    ///
    /// Column names come from `PRAGMA table_info` rather than a hardcoded list,
    /// which is the whole point: a rewritten value shows up as a changed line, and
    /// a backfilled one as a line that used to say `NULL`. A hand-written list
    /// would be checked against the schema I expected rather than the one I have.
    ///
    /// The five columns this migration adds are excluded, because "additive" is
    /// the claim being tested and the new columns *are* the addition — comparing
    /// them before and after would only prove they are nullable. What has to hold
    /// is that nothing which existed was rewritten, and `upgradeIsAdditive` states
    /// the new columns' own values separately.
    private func snapshot(_ db: Database) throws -> [String] {
        let addedByThisMigration: Set<String> = [
            "programDayId", "rotationIndex", "readinessAdjusted",
            "equipmentVariant", "wasSkippedForSession",
        ]
        var lines: [String] = []
        for table in ["exerciseCatalog", "workoutSession", "workoutBout", "prescribedWorkout"] {
            let names = try db.query("PRAGMA table_info(\(table));").compactMap { $0.string("name") }
                .filter { !addedByThisMigration.contains($0) }
            for row in try db.query("SELECT * FROM \(table);") {
                for name in names {
                    let value: String
                    switch row[name] {
                    case .some(.null), .none: value = "NULL"
                    case .some(.text(let t)): value = t
                    case .some(.integer(let i)): value = String(i)
                    case .some(.real(let d)): value = String(d)
                    case .some(.blob(let b)): value = "blob(\(b.count))"
                    }
                    lines.append("\(table).\(name)=\(value)")
                }
            }
        }
        return lines.sorted()
    }
}
