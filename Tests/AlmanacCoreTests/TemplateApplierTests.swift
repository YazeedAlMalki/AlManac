import Foundation
import Testing
@testable import AlmanacCore

/// Applying a workout template to a session (owner, 2026-10-06): the template's
/// exercises become the session's starting point, and the session stays his to
/// change.
@Suite("Template applier")
struct TemplateApplierTests {
    let db = try! TestDatabase()
    var templates: PrescribedWorkoutStore { PrescribedWorkoutStore(db: db) }
    var sessions: WorkoutSessionStore { WorkoutSessionStore(db: db) }
    var bouts: WorkoutBoutStore { WorkoutBoutStore(db: db) }
    var applier: TemplateApplier { TemplateApplier(db: db) }
    let day = "2026-10-06"

    func exercise(_ id: String, _ type: String = "reps_load") throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(ExerciseCatalogDraft(
            sourceId: "test", exerciseId: id, name: "Exercise \(id)",
            prescriptionType: type, licenseGroup: "cc0"))
    }

    /// Push day: bench 3×8 @ 60, a 30 s plank, and pull-ups with no numbers.
    func pushDay() throws -> (template: Int64, bench: Int64, plank: Int64, pullup: Int64) {
        let bench = try exercise("bench")
        let plank = try exercise("plank", "hold_stretch")
        let pullup = try exercise("pullup", "reps_bodyweight")
        let template = try templates.create(name: "Push day", containerType: "straight_sets")
        try templates.setItems([
            PrescribedWorkoutItemDraft(exerciseCatalogId: bench, prescriptionType: "reps_load",
                                       prescribedSets: 3, prescribedReps: 8, prescribedLoadKg: 60),
            PrescribedWorkoutItemDraft(exerciseCatalogId: plank, prescriptionType: "hold_stretch",
                                       prescribedDurationSeconds: 30),
            PrescribedWorkoutItemDraft(exerciseCatalogId: pullup, prescriptionType: "reps_bodyweight")
        ], for: template)
        return (template, bench, plank, pullup)
    }

    // MARK: The template holds exercises

    @Test("A template's exercises read back in order with their numbers")
    func itemsRoundTrip() throws {
        let push = try pushDay()
        let items = try templates.items(of: push.template)
        #expect(items.map(\.exerciseCatalogId) == [push.bench, push.plank, push.pullup])
        #expect(items.map(\.sequenceIndex) == [0, 1, 2])
        #expect(items[0].draft.prescribedSets == 3 && items[0].draft.prescribedLoadKg == 60)
        #expect(items[2].draft.prescribedSets == nil, "a blank is nil, not zero")
    }

    @Test("A zero, an unknown type, or a discontinued template is refused")
    func itemsAreValidated() throws {
        let push = try pushDay()
        #expect(throws: PrescribedWorkoutStoreError.invalidPrescription) {
            try templates.setItems([PrescribedWorkoutItemDraft(exerciseCatalogId: push.bench,
                                                               prescriptionType: "reps_load",
                                                               prescribedSets: 0)], for: push.template)
        }
        #expect(throws: PrescribedWorkoutStoreError.unknownPrescriptionType("lifting")) {
            try templates.setItems([PrescribedWorkoutItemDraft(exerciseCatalogId: push.bench,
                                                               prescriptionType: "lifting")], for: push.template)
        }
        #expect(try templates.items(of: push.template).count == 3, "a refused write changed the template")
        try templates.delete(id: push.template)
        #expect(throws: PrescribedWorkoutStoreError.templateNotFound(push.template)) {
            try templates.setItems([], for: push.template)
        }
    }

    // MARK: Applying

    @Test("Applying to an empty session copies every exercise as planned, with nothing done")
    func applyCopiesThePlan() throws {
        let push = try pushDay()
        let session = try sessions.log(WorkoutSessionDraft(date: day))
        let applied = try applier.apply(template: push.template, to: session)

        let logged = try bouts.bouts(sessionId: session)
        #expect(logged.map(\.id) == applied.boutIds)
        #expect(logged.map(\.exerciseCatalogId) == [push.bench, push.plank, push.pullup])
        #expect(logged.map(\.prescriptionType) == ["reps_load", "hold_stretch", "reps_bodyweight"])
        #expect(logged.allSatisfy { $0.containerType == "straight_sets" })
        #expect(logged[0].prescribedSets == 3 && logged[0].prescribedReps == 8 && logged[0].prescribedLoadKg == 60)
        #expect(logged[1].prescribedDurationSeconds == 30)
        for bout in logged {
            #expect(bout.actualSets == nil && bout.actualReps == nil && bout.actualLoadKg == nil
                    && bout.actualDurationSeconds == nil && bout.actualDistanceMeters == nil
                    && bout.actualRounds == nil, "applying recorded something as done")
        }
        #expect(try sessions.session(id: session)?.prescribedWorkoutId == push.template)
    }

    @Test("A session with logged bouts is not filled silently; appending goes after them")
    func nonEmptySessionAsksFirst() throws {
        let push = try pushDay()
        let other = try exercise("squat")
        let session = try sessions.log(WorkoutSessionDraft(date: day))
        let done = try bouts.log(WorkoutBoutDraft(sessionId: session, exerciseCatalogId: other,
                                                  sequenceIndex: 0, prescriptionType: "reps_load",
                                                  actualSets: 5, actualReps: 5, actualLoadKg: 100))

        #expect(throws: TemplateApplyError.sessionHasBouts(1)) {
            try applier.apply(template: push.template, to: session)
        }
        #expect(try bouts.bouts(sessionId: session).count == 1, "a refused apply wrote something")

        try applier.apply(template: push.template, to: session, appendingAfterExisting: true)
        let logged = try bouts.bouts(sessionId: session)
        #expect(logged.map(\.sequenceIndex) == [0, 1, 2, 3])
        #expect(logged.first?.id == done && logged.first?.actualLoadKg == 100, "the logged bout was touched")
    }

    @Test("Editing the template later changes no session it was applied to")
    func copiedNotReferenced() throws {
        let push = try pushDay()
        let session = try sessions.log(WorkoutSessionDraft(date: day))
        try applier.apply(template: push.template, to: session)

        try templates.setItems([PrescribedWorkoutItemDraft(exerciseCatalogId: push.bench,
                                                           prescriptionType: "reps_load",
                                                           prescribedSets: 5, prescribedReps: 5,
                                                           prescribedLoadKg: 80)], for: push.template)
        try templates.delete(id: push.template)

        let logged = try bouts.bouts(sessionId: session)
        #expect(logged.count == 3)
        #expect(logged[0].prescribedSets == 3 && logged[0].prescribedLoadKg == 60)
    }

    @Test("A discontinued or empty template, or a program day's session, is refused")
    func refusals() throws {
        let push = try pushDay()
        let empty = try templates.create(name: "Empty", containerType: "circuit")
        let session = try sessions.log(WorkoutSessionDraft(date: day))
        #expect(throws: TemplateApplyError.templateHasNoExercises(empty)) {
            try applier.apply(template: empty, to: session)
        }
        #expect(throws: TemplateApplyError.templateNotFound(9_999)) {
            try applier.apply(template: 9_999, to: session)
        }
        try templates.delete(id: push.template)
        #expect(throws: TemplateApplyError.templateDiscontinued(push.template)) {
            try applier.apply(template: push.template, to: session)
        }
        #expect(throws: TemplateApplyError.templateDiscontinued(push.template)) {
            try applier.applyToDay(template: push.template, date: "2026-10-07")
        }
        #expect(try sessions.sessions(date: "2026-10-07").isEmpty, "a refused apply left an empty session")
    }

    @Test("Applying to a day uses his own ad-hoc session, or creates one")
    func applyToDay() throws {
        let push = try pushDay()
        let created = try applier.applyToDay(template: push.template, date: day)
        #expect(try sessions.sessions(date: day).map(\.id) == [created.sessionId])
        #expect(try sessions.session(id: created.sessionId)?.prescribedWorkoutId == push.template)

        // Again on the same day: the same session, which now has bouts.
        #expect(throws: TemplateApplyError.sessionHasBouts(3)) {
            try applier.applyToDay(template: push.template, date: day)
        }
        let again = try applier.applyToDay(template: push.template, date: day, appendingAfterExisting: true)
        #expect(again.sessionId == created.sessionId)
        #expect(try bouts.bouts(sessionId: created.sessionId).count == 6)
    }

    // MARK: Editable afterwards

    @Test("An applied session stays editable: record what was done, drop what was not")
    func editableAfterwards() throws {
        let push = try pushDay()
        let applied = try applier.applyToDay(template: push.template, date: day)
        let bench = try #require(try bouts.bout(id: applied.boutIds[0]))

        var done = WorkoutBoutDraft(sessionId: bench.sessionId, exerciseCatalogId: bench.exerciseCatalogId,
                                    sequenceIndex: bench.sequenceIndex, prescriptionType: bench.prescriptionType)
        done.actualSets = 3
        done.actualReps = 6
        done.actualLoadKg = 62.5
        #expect(try bouts.updateActuals(done, id: bench.id))
        #expect(try bouts.delete(id: applied.boutIds[2]))

        let logged = try bouts.bouts(sessionId: applied.sessionId)
        #expect(logged.count == 2)
        #expect(logged[0].actualReps == 6 && logged[0].actualLoadKg == 62.5)
        #expect(logged[0].prescribedReps == 8, "recording what was done rewrote the plan")
    }
}
