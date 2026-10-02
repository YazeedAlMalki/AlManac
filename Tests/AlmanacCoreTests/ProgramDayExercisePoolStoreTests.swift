import Testing
import Foundation
@testable import AlmanacCore

/// `programDayExercisePool` — the table that **is** the prescription.
///
/// Two rules run through this file, and neither is about plumbing:
///
/// - **The prescription never changes because of what was logged.** The handoff's
///   key rule. `loggingABoutDoesNotTouchThePrescription` asserts it by reading the
///   row back byte for byte, timestamps included — an `updatedAt` bump would be
///   the leak that shows up first.
/// - **`isActive = false` and `deletedAt` are different things.** One is kept and
///   reversible with its rule and its position intact; the other is gone. Every
///   read has to know which it means, so every read is tested against both.
@Suite("Program-day exercise pool store")
struct ProgramDayExercisePoolStoreTests {
    let db = try! TestDatabase()
    private var pool: ProgramDayExercisePoolStore { ProgramDayExercisePoolStore(db: db) }

    // MARK: - Fixtures

    private func makeDay(_ label: String = "Push") throws -> Int64 {
        let programId = try ProgramStore(db: db).create(name: "My PPL")
        return try ProgramDayStore(db: db).create(programId: programId, label: label)
    }

    private func makeExercise(_ name: String = "Barbell Squat") throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "workout-guide", exerciseId: name, name: name,
                                 prescriptionType: "reps_load", licenseGroup: "cc-by-sa-4.0"))
    }

    @discardableResult
    private func add(_ draft: PoolItemDraft) throws -> Int64 {
        try pool.add(draft)
    }

    private func basicDraft(dayId: Int64, exerciseName: String = "Barbell Squat",
                            rotationPosition: Int = 0, positionWithinSession: Int = 0) throws -> PoolItemDraft {
        PoolItemDraft(programDayId: dayId, exerciseCatalogId: try makeExercise(exerciseName),
                      rotationPosition: rotationPosition, positionWithinSession: positionWithinSession,
                      prescriptionType: "reps_load", prescribedSets: 4, prescribedReps: 6,
                      prescribedLoadKg: 100, prescribedRestSeconds: 90, notes: "belt on")
    }

    private func item(_ id: Int64) throws -> PoolItemEntry {
        let found = try pool.item(id: id)
        return try #require(found)
    }

    // MARK: - Write and read back

    @Test("An added item reads back with every field it was given")
    func addAndFetch() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId, rotationPosition: 2, positionWithinSession: 1))

        let entry = try item(id)
        #expect(entry.programDayId == dayId)
        #expect(entry.rotationPosition == 2)
        #expect(entry.positionWithinSession == 1)
        #expect(entry.prescriptionType == "reps_load")
        #expect(entry.prescribedSets == 4)
        #expect(entry.prescribedReps == 6)
        #expect(entry.prescribedLoadKg == 100)
        #expect(entry.prescribedRestSeconds == 90)
        #expect(entry.notes == "belt on")
        // Decision 4: off until the user says otherwise. Decision 3: active, and
        // present rather than soft-deleted.
        #expect(entry.progressionEnabled == false)
        #expect(entry.hasCompleteProgressionRule == false)
        #expect(entry.isActive == true)
        #expect(entry.isDeleted == false)
    }

    @Test("A prescription using only some of the five fields keeps the rest absent")
    func absentFieldsStayNull() throws {
        // A hold has no sets, reps or load. Null and zero are different answers and
        // the column has to be able to tell them apart.
        let dayId = try makeDay()
        let id = try add(PoolItemDraft(
            programDayId: dayId, exerciseCatalogId: try makeExercise("Hamstring Stretch"),
            rotationPosition: 0, prescriptionType: "hold_stretch",
            prescribedDurationSeconds: 45))

        let entry = try item(id)
        #expect(entry.prescribedDurationSeconds == 45)
        #expect(entry.prescribedSets == nil)
        #expect(entry.prescribedReps == nil)
        #expect(entry.prescribedLoadKg == nil)
        #expect(entry.prescribedRestSeconds == nil)
        #expect(entry.containerType == nil)
    }

    // MARK: - The closed sets

    @Test("A prescription type outside the twelve is refused, and names itself")
    func refusesUnknownPrescriptionType() throws {
        let dayId = try makeDay()
        var draft = try basicDraft(dayId: dayId)
        draft.prescriptionType = "push_ups"
        #expect(throws: ProgramDayExercisePoolStoreError.unknownPrescriptionType("push_ups")) {
            try add(draft)
        }
    }

    @Test("A container type outside the ten is refused")
    func refusesUnknownContainerType() throws {
        let dayId = try makeDay()
        var draft = try basicDraft(dayId: dayId)
        draft.containerType = "pyramid"
        #expect(throws: ProgramDayExercisePoolStoreError.unknownContainerType("pyramid")) {
            try add(draft)
        }
    }

    @Test("A progression condition outside the named set is refused")
    func refusesUnknownProgressionCondition() throws {
        let dayId = try makeDay()
        var draft = try basicDraft(dayId: dayId)
        draft.progressionEnabled = true
        draft.progressionIncrementKg = 2.5
        draft.progressionCondition = "felt_good"
        #expect(throws: ProgramDayExercisePoolStoreError.unknownProgressionCondition("felt_good")) {
            try add(draft)
        }
    }

    @Test("A progression rule with only half of itself is refused")
    func refusesHalfARule() throws {
        // `progressionEnabled = 1` on its own would read as a rule to anything above
        // this row, and a rule with an increment and no condition cannot say what
        // it would suggest.
        let dayId = try makeDay()
        let noCondition = try basicDraft(dayId: dayId)
        var a = noCondition
        a.exerciseCatalogId = try makeExercise("A")
        a.progressionEnabled = true
        a.progressionIncrementKg = 2.5
        #expect(throws: ProgramDayExercisePoolStoreError.incompleteProgressionRule) { try add(a) }

        var b = noCondition
        b.exerciseCatalogId = try makeExercise("B")
        b.progressionEnabled = true
        b.progressionCondition = "all_reps_completed"
        #expect(throws: ProgramDayExercisePoolStoreError.incompleteProgressionRule) { try add(b) }
    }

    @Test("A negative rotation position or slot is refused")
    func refusesNegativePositions() throws {
        // The rotation arithmetic is `rotationIndex mod count` and a slot count read
        // as `MAX + 1`; a negative in either column makes both nonsense rather than
        // merely odd.
        let dayId = try makeDay()
        var draft = try basicDraft(dayId: dayId)
        draft.rotationPosition = -1
        #expect(throws: ProgramDayExercisePoolStoreError.negativePosition) { try add(draft) }

        var other = try basicDraft(dayId: dayId, exerciseName: "Bench")
        other.positionWithinSession = -1
        #expect(throws: ProgramDayExercisePoolStoreError.negativePosition) { try add(other) }
    }

    // MARK: - Ordering and counts

    @Test("Items come back in cycle order, and ties break by insertion")
    func itemsAreInCycleOrder() throws {
        let dayId = try makeDay()
        for position in [3, 0, 2, 1] {
            _ = try add(try basicDraft(dayId: dayId, exerciseName: "E\(position)",
                                      rotationPosition: position))
        }
        #expect(try pool.items(programDayId: dayId).map(\.rotationPosition) == [0, 1, 2, 3])

        // Two items authored at the same position: the second is offered second,
        // rather than the order being left to SQLite to decide between runs.
        let tie = try basicDraft(dayId: dayId, exerciseName: "Tie A", rotationPosition: 9)
        let first = try add(tie)
        var second = tie
        second.exerciseCatalogId = try makeExercise("Tie B")
        let secondId = try add(second)
        let tied = try pool.items(programDayId: dayId).filter { $0.rotationPosition == 9 }
        #expect(tied.map(\.id) == [first, secondId])
    }

    @Test("The item list shows removed exercises; the rotation read does not")
    func authoringAndRotationReadsDiffer() throws {
        // "Why is this exercise not being offered" is answered by seeing it greyed
        // out, and by an empty session otherwise.
        let dayId = try makeDay()
        let kept = try add(try basicDraft(dayId: dayId, exerciseName: "Kept", rotationPosition: 0))
        let removed = try add(try basicDraft(dayId: dayId, exerciseName: "Removed", rotationPosition: 1))
        _ = try pool.setActive(id: removed, to: false)

        #expect(try pool.items(programDayId: dayId).count == 2)
        #expect(try pool.activeItems(programDayId: dayId).map(\.id) == [kept])
    }

    @Test("A deleted item leaves both reads")
    func deletedItemLeavesBothReads() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))
        #expect(try pool.delete(id: id) == true)

        #expect(try pool.items(programDayId: dayId).isEmpty)
        #expect(try pool.activeItems(programDayId: dayId).isEmpty)
        // Still readable, because a past session's prescription has to be
        // explainable after the fact.
        #expect(try pool.item(id: id)?.isDeleted == true)
        #expect(try pool.delete(id: id) == false)
    }

    @Test("A day with no items has no session shape at all")
    func emptyDayHasNoSlots() throws {
        // Zero rather than one: a stored slot count would also be a second thing
        // that has to be kept true every time an exercise is added.
        let dayId = try makeDay()
        #expect(try pool.sessionSlotCount(programDayId: dayId) == 0)
        #expect(try pool.nextRotationPosition(programDayId: dayId) == 0)
    }

    @Test("A session's size is the highest slot plus one")
    func slotCountIsMaxPlusOne() throws {
        let dayId = try makeDay()
        for slot in [0, 1, 2] {
            _ = try add(try basicDraft(dayId: dayId, exerciseName: "S\(slot)",
                                       rotationPosition: slot, positionWithinSession: slot))
        }
        #expect(try pool.sessionSlotCount(programDayId: dayId) == 3)
    }

    @Test("A permanently removed exercise does not shorten the day")
    func slotCountIgnoresNothingButDeletes() throws {
        // The distinction that makes Decision 3 reversible: an exercise the gym does
        // not have is still part of the day's shape, so the window refills from the
        // next active item instead of the session quietly getting shorter.
        let dayId = try makeDay()
        for slot in [0, 1, 2] {
            _ = try add(try basicDraft(dayId: dayId, exerciseName: "S\(slot)",
                                       rotationPosition: slot, positionWithinSession: slot))
        }
        let items = try pool.items(programDayId: dayId)
        _ = try pool.setActive(id: items[2].id, to: false)
        #expect(try pool.sessionSlotCount(programDayId: dayId) == 3)

        _ = try pool.delete(id: items[2].id)
        #expect(try pool.sessionSlotCount(programDayId: dayId) == 2)
    }

    @Test("The next free rotation position is one past the highest")
    func nextRotationPosition() throws {
        let dayId = try makeDay()
        #expect(try pool.nextRotationPosition(programDayId: dayId) == 0)
        _ = try add(try basicDraft(dayId: dayId, exerciseName: "A", rotationPosition: 5))
        _ = try add(try basicDraft(dayId: dayId, exerciseName: "B", rotationPosition: 2))
        #expect(try pool.nextRotationPosition(programDayId: dayId) == 6)
    }

    // MARK: - Editing

    @Test("Editing a prescription leaves the position and the progression rule alone")
    func updatePrescriptionTouchesOnlyThePrescription() throws {
        // Two writers for one job is how "progression is on but has no rule" becomes
        // storable, so the prescription edit and the rule edit are separate methods
        // and each writes only its own columns.
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId, rotationPosition: 4, positionWithinSession: 2))
        _ = try pool.setProgression(id: id, incrementKg: 2.5, condition: "all_reps_completed")

        #expect(try pool.updatePrescription(
            id: id, prescriptionType: "reps_bodyweight", containerType: "superset",
            prescribedSets: 3, prescribedReps: 12, prescribedLoadKg: nil,
            prescribedDurationSeconds: nil, prescribedRestSeconds: 60, notes: nil) == true)

        let entry = try item(id)
        #expect(entry.prescriptionType == "reps_bodyweight")
        #expect(entry.containerType == "superset")
        #expect(entry.prescribedSets == 3)
        #expect(entry.prescribedReps == 12)
        #expect(entry.prescribedLoadKg == nil)
        #expect(entry.prescribedRestSeconds == 60)
        #expect(entry.notes == nil)
        #expect(entry.rotationPosition == 4)
        #expect(entry.positionWithinSession == 2)
        #expect(entry.hasCompleteProgressionRule == true)
        #expect(entry.progressionIncrementKg == 2.5)
    }

    @Test("Editing a prescription validates its closed sets and reports a miss")
    func updatePrescriptionValidates() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))

        #expect(throws: ProgramDayExercisePoolStoreError.unknownPrescriptionType("nope")) {
            try pool.updatePrescription(id: id, prescriptionType: "nope", containerType: nil,
                                        prescribedSets: nil, prescribedReps: nil, prescribedLoadKg: nil,
                                        prescribedDurationSeconds: nil, prescribedRestSeconds: nil,
                                        notes: nil)
        }
        #expect(throws: ProgramDayExercisePoolStoreError.unknownContainerType("pyramid")) {
            try pool.updatePrescription(id: id, prescriptionType: "reps_load", containerType: "pyramid",
                                        prescribedSets: nil, prescribedReps: nil, prescribedLoadKg: nil,
                                        prescribedDurationSeconds: nil, prescribedRestSeconds: nil,
                                        notes: nil)
        }
        #expect(try pool.updatePrescription(
            id: 9999, prescriptionType: "reps_load", containerType: nil, prescribedSets: nil,
            prescribedReps: nil, prescribedLoadKg: nil, prescribedDurationSeconds: nil,
            prescribedRestSeconds: nil, notes: nil) == false)
    }

    @Test("Moving an item needs both halves of its position, and both must be real")
    func setPositions() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId, rotationPosition: 0))

        #expect(try pool.setPositions(id: id, rotationPosition: 7, positionWithinSession: 3) == true)
        let entry = try item(id)
        #expect(entry.rotationPosition == 7)
        #expect(entry.positionWithinSession == 3)

        #expect(throws: ProgramDayExercisePoolStoreError.negativePosition) {
            try pool.setPositions(id: id, rotationPosition: -1, positionWithinSession: 0)
        }
        #expect(throws: ProgramDayExercisePoolStoreError.negativePosition) {
            try pool.setPositions(id: id, rotationPosition: 0, positionWithinSession: -1)
        }
        #expect(try pool.setPositions(id: 9999, rotationPosition: 0, positionWithinSession: 0) == false)
    }

    // MARK: - Decision 3: the two mechanisms

    @Test("Permanent removal is reversible and keeps the prescription and the rule")
    func setActiveIsReversible() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId, rotationPosition: 3))
        _ = try pool.setProgression(id: id, incrementKg: 2.5, condition: "all_reps_completed")

        #expect(try pool.setActive(id: id, to: false) == true)
        #expect(try item(id).isActive == false)
        // Still in the authoring list, still fully configured.
        #expect(try pool.items(programDayId: dayId).count == 1)

        #expect(try pool.setActive(id: id, to: true) == true)
        let back = try item(id)
        #expect(back.isActive == true)
        #expect(back.rotationPosition == 3)
        #expect(back.prescribedLoadKg == 100)
        #expect(back.hasCompleteProgressionRule == true)
    }

    @Test("A deleted item cannot be deactivated, because it is already gone")
    func setActiveOnADeletedItem() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))
        _ = try pool.delete(id: id)

        #expect(try pool.setActive(id: id, to: false) == false)
        #expect(try pool.setProgression(id: id, incrementKg: 2.5,
                                        condition: "all_reps_completed") == false)
        #expect(try pool.setPositions(id: id, rotationPosition: 1,
                                      positionWithinSession: 1) == false)
    }

    @Test("A per-session skip writes nothing at all")
    func perSessionSkipIsNotAWrite() throws {
        // Not an oversight: holding its position *is* the absence of a write. The
        // only record of the skip is on the bout.
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))
        let before = try item(id)

        try pool.skipForSessionOnly(.perSession, item: id)

        let after = try item(id)
        #expect(after == before)
        #expect(after.updatedAt == before.updatedAt)
        #expect(after.isActive == true)
    }

    @Test("The permanent mechanism does write, through the same entry point")
    func permanentSkipWrites() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))
        try pool.skipForSessionOnly(.permanent, item: id)
        #expect(try item(id).isActive == false)
    }

    @Test("The two mechanisms are a type, not a convention")
    func availabilityIsTyped() {
        // `ExerciseAvailability.mutatesPool` states the asymmetry so a call site
        // cannot assume both are writes.
        #expect(ExerciseAvailability.permanent.mutatesPool)
        #expect(ExerciseAvailability.perSession.mutatesPool == false)
    }

    // MARK: - Decision 4: the rule

    @Test("Setting and clearing a progression rule both work")
    func setProgression() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))

        #expect(try pool.setProgression(id: id, incrementKg: 2.5,
                                        condition: "all_reps_completed") == true)
        let on = try item(id)
        #expect(on.progressionEnabled == true)
        #expect(on.progressionIncrementKg == 2.5)
        #expect(on.progressionCondition == "all_reps_completed")
        #expect(on.hasCompleteProgressionRule == true)

        // Clearing is `nil, nil` and nothing else, so "off" and "enabled with a
        // broken rule" cannot both be stored.
        #expect(try pool.setProgression(id: id, incrementKg: nil, condition: nil) == true)
        let off = try item(id)
        #expect(off.progressionEnabled == false)
        #expect(off.progressionIncrementKg == nil)
        #expect(off.progressionCondition == nil)
    }

    @Test("Half a rule cannot be stored, whichever half is missing")
    func setProgressionNeedsBothHalves() throws {
        let dayId = try makeDay()
        let id = try add(try basicDraft(dayId: dayId))

        #expect(throws: ProgramDayExercisePoolStoreError.incompleteProgressionRule) {
            try pool.setProgression(id: id, incrementKg: 2.5, condition: nil)
        }
        #expect(throws: ProgramDayExercisePoolStoreError.incompleteProgressionRule) {
            try pool.setProgression(id: id, incrementKg: nil, condition: "all_reps_completed")
        }
        #expect(throws: ProgramDayExercisePoolStoreError.unknownProgressionCondition("felt_good")) {
            try pool.setProgression(id: id, incrementKg: 2.5, condition: "felt_good")
        }
        #expect(try item(id).progressionEnabled == false)
    }

    // MARK: - The key rule

    @Test("Logging a bout does not change the prescription")
    func loggingABoutDoesNotTouchThePrescription() throws {
        // The handoff's key rule, and the reason `programDayExercisePool` exists as
        // a separate table: a pool item is only ever the plan. An `updatedAt` bump
        // here would be the first sign of the two becoming the same row.
        let dayId = try makeDay()
        let exerciseId = try makeExercise()
        let id = try add(PoolItemDraft(
            programDayId: dayId, exerciseCatalogId: exerciseId, rotationPosition: 0,
            prescriptionType: "reps_load", prescribedSets: 4, prescribedReps: 6,
            prescribedLoadKg: 100, prescribedRestSeconds: 90))
        let before = try item(id)

        let sessionId = try WorkoutSessionStore(db: db).log(WorkoutSessionDraft(date: "2026-10-01"))
        _ = try WorkoutBoutStore(db: db).log(WorkoutBoutDraft(
            sessionId: sessionId, exerciseCatalogId: exerciseId, prescriptionType: "reps_load",
            prescribedSets: 4, prescribedReps: 6, prescribedLoadKg: 100,
            actualSets: 4, actualReps: 6, actualLoadKg: 105))

        let after = try item(id)
        #expect(after.prescribedLoadKg == before.prescribedLoadKg)
        #expect(after.prescribedReps == before.prescribedReps)
        #expect(after.prescribedSets == before.prescribedSets)
        #expect(after.updatedAt == before.updatedAt)
        // The log is where the 105 lives.
        #expect(try WorkoutProgressProbe(db: db).load(sessionId: sessionId, exerciseId: exerciseId) == 105)
    }

    @Test("A movement's pool items are findable from the movement, across programs")
    func itemsByExerciseSpanPrograms() throws {
        // The read both progress graphs and `ExerciseProgression` need. An exercise
        // removed from a pool last month still has history, so inactive items are
        // included — hiding them empties the graph exactly when the user is
        // wondering why.
        let exerciseId = try makeExercise("Barbell Squat")
        let dayA = try makeDay("Push")
        let dayB = try makeDay("Legs")
        let live = try add(PoolItemDraft(programDayId: dayA, exerciseCatalogId: exerciseId,
                                         rotationPosition: 0, prescriptionType: "reps_load"))
        let removed = try add(PoolItemDraft(programDayId: dayB, exerciseCatalogId: exerciseId,
                                            rotationPosition: 0, prescriptionType: "reps_load"))
        _ = try pool.setActive(id: removed, to: false)

        let found = try pool.items(exerciseCatalogId: exerciseId)
        #expect(found.map(\.id) == [live, removed])
        #expect(found.allSatisfy { $0.exerciseCatalogId == exerciseId })
        #expect(try pool.items(exerciseCatalogId: 9999).isEmpty)
    }
}

/// Reads one actual back off a bout, so the test that a log cannot reach the pool
/// can also say where the logged number did go.
private struct WorkoutProgressProbe {
    let db: Database

    func load(sessionId: Int64, exerciseId: Int64) throws -> Double? {
        try db.query("SELECT actualLoadKg FROM workoutBout WHERE sessionId = ? AND exerciseCatalogId = ?;",
                     [.integer(sessionId), .integer(exerciseId)])
            .first?.double("actualLoadKg")
    }
}
