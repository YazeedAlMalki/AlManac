import Testing
import Foundation
@testable import AlmanacCore

@Suite("Migration016 (Training Schema) Tests")
struct Migration016Tests {
    let db = try! TestDatabase()

    @Test("Migration applies and is recorded")
    func migrationApplies() throws {
        let runner = try MigrationRunner(migrations: AlmanacMigrations.all)
        let applied = try runner.applied(in: db).map(\.version)
        #expect(applied.contains(16))
    }

    @Test("All four Slice 4 tables exist")
    func tablesExist() throws {
        let expected = ["exerciseCatalog", "prescribedWorkout", "workoutSession", "workoutBout"]
        for table in expected {
            let rows = try db.query("SELECT name FROM sqlite_master WHERE type='table' AND name = ?;", [.text(table)])
            #expect(rows.count == 1, "\(table) should exist")
        }
    }

    @Test("exerciseCatalog rejects a prescriptionType outside the twelve")
    func rejectsInvalidPrescriptionType() throws {
        #expect(throws: (any Error).self) {
            try db.run("""
            INSERT INTO exerciseCatalog (sourceId, exerciseId, name, prescriptionType, licenseGroup, createdAt, updatedAt)
            VALUES ('wger', '1', 'Test', 'not_a_real_type', 'cc0', '2026-09-16T00:00:00Z', '2026-09-16T00:00:00Z');
            """)
        }
    }

    @Test("prescribedWorkout rejects a containerType outside the ten")
    func rejectsInvalidContainerType() throws {
        #expect(throws: (any Error).self) {
            try db.run("""
            INSERT INTO prescribedWorkout (name, containerType, createdAt, updatedAt)
            VALUES ('Test', 'not_a_real_container', '2026-09-16T00:00:00Z', '2026-09-16T00:00:00Z');
            """)
        }
    }

    @Test("workoutBout requires a valid sessionId and exerciseCatalogId")
    func boutRequiresValidForeignKeys() throws {
        #expect(throws: (any Error).self) {
            try db.run("""
            INSERT INTO workoutBout (sessionId, exerciseCatalogId, prescriptionType, createdAt, updatedAt)
            VALUES (999, 999, 'reps_load', '2026-09-16T00:00:00Z', '2026-09-16T00:00:00Z');
            """)
        }
    }

    @Test("Exactly twelve prescription types and ten container types are declared")
    func enumCounts() {
        #expect(Migration016_TrainingSchema.prescriptionTypes.count == 12)
        #expect(Migration016_TrainingSchema.containerTypes.count == 10)
    }
}
