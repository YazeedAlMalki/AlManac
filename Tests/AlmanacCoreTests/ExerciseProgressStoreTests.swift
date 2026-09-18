import Testing
import Foundation
@testable import AlmanacCore

@Suite("ExerciseProgressStore Tests")
struct ExerciseProgressStoreTests {
    let db = try! TestDatabase()
    var progressStore: ExerciseProgressStore { ExerciseProgressStore(db: db) }
    var sessionStore: WorkoutSessionStore { WorkoutSessionStore(db: db) }
    var boutStore: WorkoutBoutStore { WorkoutBoutStore(db: db) }

    private func makeSession(date: String) throws -> Int64 {
        try sessionStore.log(WorkoutSessionDraft(date: date))
    }

    private func makeExercise(exerciseId: String = "1", name: String = "Barbell Squat") throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "wger", exerciseId: exerciseId, name: name,
                                  prescriptionType: "reps_load", licenseGroup: "cc0"))
    }

    @Test("History for an exercise with no logged bouts is empty")
    func emptyHistory() throws {
        let exerciseId = try makeExercise()
        #expect(try progressStore.history(exerciseCatalogId: exerciseId).isEmpty)
    }

    @Test("History returns each session's actual load/reps/sets, oldest first")
    func historyAcrossSessions() throws {
        let exerciseId = try makeExercise()
        let session1 = try makeSession(date: "2026-09-10")
        let session2 = try makeSession(date: "2026-09-17")

        // Logged out of chronological order to prove the store sorts by date, not insertion order.
        try boutStore.log(WorkoutBoutDraft(sessionId: session2, exerciseCatalogId: exerciseId,
                                            prescriptionType: "reps_load",
                                            actualSets: 5, actualReps: 5, actualLoadKg: 105))
        try boutStore.log(WorkoutBoutDraft(sessionId: session1, exerciseCatalogId: exerciseId,
                                            prescriptionType: "reps_load",
                                            actualSets: 5, actualReps: 5, actualLoadKg: 100))

        let history = try progressStore.history(exerciseCatalogId: exerciseId)

        #expect(history.map { $0.date } == ["2026-09-10", "2026-09-17"])
        #expect(history.map { $0.actualLoadKg } == [100, 105])
    }

    @Test("History excludes a different exercise's bouts")
    func historyExcludesOtherExercises() throws {
        let squat = try makeExercise(exerciseId: "1", name: "Barbell Squat")
        let deadlift = try makeExercise(exerciseId: "2", name: "Deadlift")
        let session = try makeSession(date: "2026-09-17")

        try boutStore.log(WorkoutBoutDraft(sessionId: session, exerciseCatalogId: squat,
                                            prescriptionType: "reps_load", actualLoadKg: 100))
        try boutStore.log(WorkoutBoutDraft(sessionId: session, exerciseCatalogId: deadlift,
                                            prescriptionType: "reps_load", actualLoadKg: 140))

        let squatHistory = try progressStore.history(exerciseCatalogId: squat)
        #expect(squatHistory.count == 1)
        #expect(squatHistory.first?.actualLoadKg == 100)
    }

    @Test("History excludes soft-deleted bouts")
    func historyExcludesDeletedBouts() throws {
        let exerciseId = try makeExercise()
        let session = try makeSession(date: "2026-09-17")
        let boutId = try boutStore.log(WorkoutBoutDraft(sessionId: session, exerciseCatalogId: exerciseId,
                                                          prescriptionType: "reps_load", actualLoadKg: 100))
        try boutStore.delete(id: boutId)

        #expect(try progressStore.history(exerciseCatalogId: exerciseId).isEmpty)
    }
}
