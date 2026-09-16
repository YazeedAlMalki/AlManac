import Testing
import Foundation
@testable import AlmanacCore

@Suite("WorkoutBoutStore Tests")
struct WorkoutBoutStoreTests {
    let db = try! TestDatabase()
    var store: WorkoutBoutStore { WorkoutBoutStore(db: db) }

    private func makeSession() throws -> Int64 {
        try WorkoutSessionStore(db: db).log(WorkoutSessionDraft(date: "2026-09-16"))
    }

    private func makeExercise(prescriptionType: String = "reps_load") throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "wger", exerciseId: "1", name: "Barbell Squat",
                                  prescriptionType: prescriptionType, licenseGroup: "cc0"))
    }

    @Test("Log a reps_load bout with prescribed and actual values")
    func logRepsLoadBout() throws {
        let sessionId = try makeSession()
        let exerciseId = try makeExercise()

        let draft = WorkoutBoutDraft(sessionId: sessionId, exerciseCatalogId: exerciseId,
                                      prescriptionType: "reps_load",
                                      prescribedSets: 5, prescribedReps: 5, prescribedLoadKg: 100,
                                      actualSets: 5, actualReps: 5, actualLoadKg: 100, rpe: 8)
        let id = try store.log(draft)

        let bout = try store.bout(id: id)
        #expect(bout?.prescribedSets == 5)
        #expect(bout?.prescribedLoadKg == 100)
        #expect(bout?.actualReps == 5)
        #expect(bout?.rpe == 8)
    }

    @Test("Log a work_in_time (AMRAP) bout — time prescribed, rounds measured")
    func logAMRAPBout() throws {
        // The exact case prescription-model-v0.1.md §1 opens with: "20-minute
        // AMRAP, got 7 rounds" must record time as prescribed and rounds as
        // the outcome, not collapse both into one column.
        let sessionId = try makeSession()
        let exerciseId = try makeExercise(prescriptionType: "work_in_time")

        let draft = WorkoutBoutDraft(sessionId: sessionId, exerciseCatalogId: exerciseId,
                                      prescriptionType: "work_in_time", containerType: "amrap",
                                      prescribedWorkSeconds: 1200,
                                      actualReps: 3, actualRounds: 7)
        let id = try store.log(draft)

        let bout = try store.bout(id: id)
        #expect(bout?.prescribedWorkSeconds == 1200)
        #expect(bout?.prescribedReps == nil, "reps were never prescribed for an AMRAP")
        #expect(bout?.actualRounds == 7)
    }

    @Test("Bouts for a session come back ordered by sequenceIndex")
    func boutsOrderedBySequence() throws {
        let sessionId = try makeSession()
        let exerciseId = try makeExercise()

        let secondId = try store.log(WorkoutBoutDraft(sessionId: sessionId, exerciseCatalogId: exerciseId,
                                                        sequenceIndex: 1, prescriptionType: "reps_load"))
        let firstId = try store.log(WorkoutBoutDraft(sessionId: sessionId, exerciseCatalogId: exerciseId,
                                                       sequenceIndex: 0, prescriptionType: "reps_load"))

        let bouts = try store.bouts(sessionId: sessionId)
        #expect(bouts.map(\.id) == [firstId, secondId])
    }

    @Test("Bouts require a session and exercise that exist")
    func requiresValidForeignKeys() throws {
        #expect(throws: (any Error).self) {
            _ = try store.log(WorkoutBoutDraft(sessionId: 999, exerciseCatalogId: 999,
                                                prescriptionType: "reps_load"))
        }
    }

    @Test("Soft delete removes a bout from its session's listing")
    func softDelete() throws {
        let sessionId = try makeSession()
        let exerciseId = try makeExercise()
        let id = try store.log(WorkoutBoutDraft(sessionId: sessionId, exerciseCatalogId: exerciseId,
                                                  prescriptionType: "reps_load"))

        #expect(try store.bouts(sessionId: sessionId).count == 1)
        #expect(try store.delete(id: id) == true)
        #expect(try store.bouts(sessionId: sessionId).count == 0)
    }
}
