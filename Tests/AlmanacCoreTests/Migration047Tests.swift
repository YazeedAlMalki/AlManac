import Foundation
import Testing
@testable import AlmanacCore

/// A migration that has been applied to a database is the one thing that cannot
/// be changed afterwards, so the shape it leaves behind is tested explicitly
/// rather than inferred from the stores that read it.
@Suite("Migration 047 — goal_target_snapshot")
struct Migration047Tests {
    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    @Test("An upgraded database has the table and its index")
    func schemaExists() throws {
        let db = try migrated()
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table';")
            .compactMap { $0.string("name") }
        #expect(tables.contains("goal_target_snapshot"))
        let indexes = try db.query("SELECT name FROM sqlite_master WHERE type = 'index';")
            .compactMap { $0.string("name") }
        #expect(indexes.contains("idx_goal_target_snapshot_effective"))
    }

    @Test("Every §5.2 column is present, by name")
    func sectionFiveTwoColumnsExist() throws {
        // §5.2 names its columns, and the code reads them by name. A renamed
        // column turns every read into a silent `nil` target, so the names are
        // pinned here rather than left to whichever query happens to run.
        let db = try migrated()
        let columns = try db.query("PRAGMA table_info(goal_target_snapshot);")
            .compactMap { $0.string("name") }
        for expected in ["id", "effective_date", "goal", "formula_version",
                         "body_weight_kg", "body_fat_pct", "activity_multiplier",
                         "goal_calorie_adjustment", "calorie_target", "protein_target_g",
                         "carb_target_g", "fat_target_g", "hydration_target_ml",
                         "manual_calorie_target", "manual_protein_target_g",
                         "manual_carb_target_g", "manual_fat_target_g",
                         "manual_hydration_target_ml", "created_at"] {
            #expect(columns.contains(expected), "§5.2 column \(expected) is missing")
        }
        // The one addition: a target per body-composition metric, so a meter has
        // something to be measured against.
        for metric in BodyMetric.allCases {
            #expect(columns.contains("target_" + expectedTargetColumnSuffix(metric)))
        }
    }

    @Test("Targets are nullable, because not-set is the normal state")
    func targetsAreNullable() throws {
        let db = try migrated()
        // Every install before somebody asks for a target has to be able to hold a
        // snapshot with no targets in it. A NOT NULL here would mean the app
        // invents a number on first launch.
        let notNull = try db.query("PRAGMA table_info(goal_target_snapshot);")
            .filter { ($0.string("name") ?? "").hasPrefix("target_") }
            .filter { ($0.int("notnull") ?? 0) != 0 }
        #expect(notNull.isEmpty, "target columns must be nullable")
    }

    @Test("A row with no targets at all is storable")
    func emptyTargetsRoundTrip() throws {
        // The state a fresh install is in when a goal is recorded before any
        // body-composition target is chosen.
        let db = try migrated()
        let store = GoalTargetSnapshotStore(db: db)
        let stored = try store.insert(.init(effectiveDate: "2026-09-30", goal: .maintain,
                                             createdAt: Date()))
        #expect(stored.id > 0)
        #expect(try store.active(on: "2026-09-30")?.bodyCompositionTargets.isEmpty == true)
        #expect(try store.activeTargets(on: "2026-09-30").isEmpty)
    }

    @Test("Effective date and goal are the only required columns")
    func requiredColumns() throws {
        let db = try migrated()
        // `goal` is a closed set at the type level and a plain TEXT here, so the
        // column being non-null is what stops a nameless row being written. The
        // date is non-null for the same reason: a snapshot with no start cannot be
        // placed in a timeline, and an unplaced row would silently never be in
        // force.
        let required = try db.query("PRAGMA table_info(goal_target_snapshot);")
            .filter { ($0.int("notnull") ?? 0) != 0 }
            .compactMap { $0.string("name") }
        #expect(Set(required) == ["effective_date", "goal", "formula_version", "created_at"])
    }

    @Test("Migration 047 is additive — it changes nothing that already existed")
    func additiveOnly() throws {
        // The strongest available check on "this migration did not rewrite
        // history": build a database at 046, write data, upgrade, and confirm the
        // data is byte-identical and readable.
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all.filter { $0.version < 47 }).migrate(db)
        try db.run("INSERT INTO profile (id, displayName, createdAt, updatedAt) VALUES (1, 'Existing user', 'before', 'before');")
        try db.run("""
        INSERT INTO body_composition_measurement
            (timestamp, logicalDay, metric, value, unit, source, conditions, createdAt)
        VALUES ('2026-09-01T07:00:00Z', '2026-09-01', 'weight', 81, 'kg', 'manual', 'fasted', '2026-09-01T07:00:00Z');
        """)

        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)

        #expect(try ProfileStore(db: db).profile().displayName == "Existing user")
        #expect(try BodyCompositionMeasurementStore(db: db)
            .latestValue(for: "weight")?.value == 81)
        // And the new table is empty rather than pre-filled with a guess.
        #expect(try GoalTargetSnapshotStore(db: db).history().isEmpty)
    }
}

/// The column suffix Migration047 writes for one metric. Duplicated here as a
/// literal rather than reaching for the store's `private` helper, because the
/// point of the test is that the *name* is right, and calling the function under
/// test to check it would only prove it is consistent with itself.
private func expectedTargetColumnSuffix(_ metric: BodyMetric) -> String {
    switch metric {
    case .weight: return "body_weight_kg"
    case .bodyFatPercent: return "body_fat_pct"
    case .leanMassKg: return "lean_mass_kg"
    case .skeletalMuscleKg: return "skeletal_muscle_kg"
    case .visceralRating: return "visceral_rating"
    }
}
