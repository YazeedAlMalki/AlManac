import Testing
import Foundation
@testable import AlmanacCore

/// The training vocabularies, and the store methods the training UI needed.
///
/// The vocabulary tests are mostly about *drift*: `TrainingContainer` and
/// `PrescriptionKind` are Swift enums transcribing lists that also exist as
/// arrays on `Migration016_TrainingSchema` and as SQL CHECK constraints. Two
/// copies of the same ten and twelve can disagree silently, and a disagreement
/// shows up as a runtime constraint failure at the insert rather than as a
/// compile error.
@Suite("Training vocabulary and UI store gaps")
struct TrainingVocabularyTests {
    let db = try! TestDatabase()

    // MARK: - Vocabulary

    @Test("TrainingContainer is exactly the migration's ten container types")
    func containerTypesMatchTheMigration() {
        #expect(TrainingContainer.allCases.map(\.rawValue)
                == Migration016_TrainingSchema.containerTypes,
                "the enum and the schema's list have drifted; the CHECK constraint would reject a value the enum offers")
    }

    @Test("PrescriptionKind is exactly the migration's twelve prescription types")
    func prescriptionTypesMatchTheMigration() {
        #expect(PrescriptionKind.allCases.map(\.rawValue)
                == Migration016_TrainingSchema.prescriptionTypes)
    }

    @Test("Every type has a distinct display name")
    func displayNamesAreDistinct() {
        #expect(Set(TrainingContainer.allCases.map(\.displayName)).count
                == TrainingContainer.allCases.count)
        #expect(Set(PrescriptionKind.allCases.map(\.displayName)).count
                == PrescriptionKind.allCases.count)
    }

    /// The grouping decides which fields a bout editor offers, so getting it
    /// wrong means asking someone for a load they never lifted.
    @Test("Only the types that take a load are told to record one")
    func loadGrouping() {
        let withLoad = Set(PrescriptionKind.allCases.filter { $0.recordsLoad }.map(\.rawValue))
        #expect(withLoad == ["reps_load", "time_under_load", "duration", "distance"])
        // Both of these contain "reps" and neither takes a load — which is why
        // the grouping is stated rather than derived from the name.
        #expect(PrescriptionKind.repsBodyweight.recordsReps)
        #expect(PrescriptionKind.qualityReps.recordsReps)
        #expect(!PrescriptionKind.repsBodyweight.recordsLoad)
        #expect(!PrescriptionKind.qualityReps.recordsLoad)
    }

    @Test("A session-only prescription records no figures at all")
    func sessionOnlyRecordsNothing() {
        let none = PrescriptionKind.sessionOnly
        #expect(!none.recordsLoad && !none.recordsReps && !none.recordsDuration
                && !none.recordsDistance && !none.recordsRounds)
    }

    // MARK: - Templates

    @Test("A template can be created, listed, edited and discontinued")
    func templateLifecycle() throws {
        let store = PrescribedWorkoutStore(db: db)
        let id = try store.create(name: "Upper A", containerType: TrainingContainer.straightSets.rawValue,
                                  notes: "bench first")

        #expect(try store.templates().map { $0.id } == [id])
        #expect(try store.templates().first?.containerType == "straight_sets")

        try store.update(id: id, name: "Upper B", containerType: TrainingContainer.superset.rawValue, notes: nil)
        let edited = try store.workout(id: id)
        #expect(edited?.name == "Upper B")
        #expect(edited?.containerType == "superset")
        #expect(edited?.notes == nil, "clearing notes must clear them, not skip the column")

        try store.delete(id: id)
        #expect(try store.templates().isEmpty, "a discontinued template must not be listed as current")
    }

    @Test("A discontinued template is still readable by id, because history names it")
    func discontinuedTemplateIsStillReadable() throws {
        let store = PrescribedWorkoutStore(db: db)
        let id = try store.create(name: "Old circuit", containerType: TrainingContainer.circuit.rawValue)
        try store.delete(id: id)

        // Deliberate asymmetry: `templates()` hides it, `workout(id:)` does not.
        // A past session may still carry `prescribedWorkoutId`, and a review
        // screen that could not resolve it would show a blank where the plan
        // was.
        #expect(try store.workout(id: id)?.isDeleted == true)
    }

    @Test("create refuses a container type the model does not have")
    func createRejectsUnknownContainer() throws {
        // The column has a CHECK constraint, so without this the caller gets a
        // raw SQLite error at the insert instead of a typed mistake it can act
        // on. The message has to name the offending value.
        #expect(throws: PrescribedWorkoutStoreError.unknownContainerType("pyramids")) {
            try PrescribedWorkoutStore(db: db).create(name: "Odd", containerType: "pyramids")
        }
    }

    @Test("Editing a template that is already discontinued changes nothing")
    func updateOnDeletedTemplateReportsNoChange() throws {
        let store = PrescribedWorkoutStore(db: db)
        let id = try store.create(name: "Gone", containerType: TrainingContainer.flow.rawValue)
        try store.delete(id: id)

        #expect(try store.update(id: id, name: "Back?", containerType: TrainingContainer.ladder.rawValue,
                                 notes: nil) == false)
        #expect(try store.workout(id: id)?.name == "Gone")
    }

    // MARK: - Session range

    @Test("A session range is half-open over logical days and newest first")
    func sessionRange() throws {
        let store = WorkoutSessionStore(db: db)
        for day in ["2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28"] {
            _ = try store.log(WorkoutSessionDraft(date: day, durationMinutes: 45))
        }

        #expect(try store.sessions(from: "2026-09-25", to: "2026-09-27").map(\.date)
                == ["2026-09-26", "2026-09-25"])
        #expect(try store.sessions(from: "2026-09-26", to: "2026-09-29").count == 3)
        #expect(try store.sessions(from: "2026-09-28", to: "2026-09-25").isEmpty)
    }

    @Test("A session range skips discontinued sessions")
    func sessionRangeSkipsDeleted() throws {
        let store = WorkoutSessionStore(db: db)
        let keep = try store.log(WorkoutSessionDraft(date: "2026-09-26", durationMinutes: 30))
        let drop = try store.log(WorkoutSessionDraft(date: "2026-09-26", durationMinutes: 30))
        try store.delete(id: drop)

        #expect(try store.sessions(from: "2026-09-25", to: "2026-09-27").map(\.id) == [keep])
    }

    // MARK: - Bout editing

    private func makeBout(prescriptionType: String = "reps_load") throws -> Int64 {
        let session = try WorkoutSessionStore(db: db).log(
            WorkoutSessionDraft(date: "2026-09-26", durationMinutes: 45))
        // `workoutBout.exerciseCatalogId` is a foreign key, so one catalog row
        // has to exist. Inserted rather than seeding all 302 bundled exercises —
        // these tests are about the bout columns, not the catalog.
        let exercise = try ExerciseCatalogStore(db: db).insert(ExerciseCatalogDraft(
            sourceId: "test", exerciseId: "bench", name: "Bench Press",
            prescriptionType: prescriptionType, licenseGroup: "test"))
        return try WorkoutBoutStore(db: db).log(WorkoutBoutDraft(
            sessionId: session, exerciseCatalogId: exercise,
            prescriptionType: prescriptionType,
            prescribedSets: 4, prescribedReps: 8, prescribedLoadKg: 60,
            actualSets: 4, actualReps: 8, actualLoadKg: 60
        ))
    }

    @Test("A bout's actuals can be corrected without touching the prescription")
    func updateActualsLeavesPrescriptionAlone() throws {
        let id = try makeBout()
        let store = WorkoutBoutStore(db: db)
        let bout = try store.bout(id: id)

        let changed = try store.updateActuals(WorkoutBoutDraft(
            sessionId: bout!.sessionId, exerciseCatalogId: bout!.exerciseCatalogId,
            prescriptionType: bout!.prescriptionType,
            actualSets: 4, actualReps: 5, actualLoadKg: 60, rpe: 8,
            notes: "last two were hard"
        ), id: id)

        #expect(changed)
        let updated = try store.bout(id: id)
        #expect(updated?.actualReps == 5, "the correction was not written")
        #expect(updated?.rpe == 8)
        #expect(updated?.notes == "last two were hard")
        // The plan is what was intended and must not become what happened.
        #expect(updated?.prescribedReps == 8)
        #expect(updated?.prescribedLoadKg == 60)
    }

    @Test("A blanked actual is written as null, not as zero")
    func updateActualsWritesNullForBlank() throws {
        let id = try makeBout()
        let store = WorkoutBoutStore(db: db)
        let bout = try store.bout(id: id)

        _ = try store.updateActuals(WorkoutBoutDraft(
            sessionId: bout!.sessionId, exerciseCatalogId: bout!.exerciseCatalogId,
            prescriptionType: bout!.prescriptionType,
            actualSets: 4
        ), id: id)

        let updated = try store.bout(id: id)
        #expect(updated?.actualSets == 4)
        #expect(updated?.actualReps == nil, "a cleared reps must be null, not 0")
        #expect(updated?.actualLoadKg == nil, "a cleared load must be null, not 0")
    }

    @Test("Correcting a bout that has been deleted reports no change")
    func updateActualsOnDeletedBoutReportsNoChange() throws {
        let id = try makeBout()
        let store = WorkoutBoutStore(db: db)
        try store.delete(id: id)

        #expect(try store.updateActuals(WorkoutBoutDraft(
            sessionId: 1, exerciseCatalogId: 1, prescriptionType: "reps_load", actualReps: 3
        ), id: id) == false)
    }
}
