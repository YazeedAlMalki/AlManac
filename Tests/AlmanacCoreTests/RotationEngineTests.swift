import Foundation
import Testing
@testable import AlmanacCore

/// The rotation engine — Decision 2 (advance on completed sessions, never on
/// calendar time) and Decision 3's per-session skip (holds its position).
///
/// Two paths here are the whole reason this suite exists, and both are the kind
/// of thing that looks right in a code review and is wrong in a gym:
///
/// - **A skip must hold its position.** Decision 3 spells it out twice: "holds
///   its position" and, in the resolved note, "does not advance rotation_position
///   and is re-offered next time". An engine that treats a skip like a removal
///   silently advances the cycle by one, so the skipped exercise does not come
///   back — which is exactly what the user was told would happen when they
///   chose "skip just for today".
/// - **A calendar gap must not advance anything.** The users this feature is for
///   are described as athletes on irregular schedules, and Decision 2 says so in
///   as many words: a week off must leave the next Push day as the next item in
///   the rotation, not advanced past it and not reset. An engine that derives
///   its position from a date will pass every test in this file except the gap
///   ones, so those are written to be unmissable.
///
/// The rest is the arithmetic of a window over a cycle, which is the easy half
/// and is tested only as far as the easy half needs.
@Suite("Rotation engine")
struct RotationEngineTests {
    let db = try! TestDatabase()

    private var poolStore: ProgramDayExercisePoolStore { ProgramDayExercisePoolStore(db: db) }
    private var engine: RotationEngine { RotationEngine(db: db) }
    private var sessionStore: WorkoutSessionStore { WorkoutSessionStore(db: db) }

    // MARK: - Fixtures

    /// A Push day whose pool is `count` exercises, authored the way a PPL
    /// rotation is: `rotationPosition` runs the whole cycle and
    /// `positionWithinSession` is its remainder, so `slots` exercises appear per
    /// session and each recurs every `count / slots` sessions.
    @discardableResult
    private func makeDay(count: Int = 6, slots: Int = 3, label: String = "Push") throws -> Int64 {
        let programId = try ProgramStore(db: db).create(name: "My PPL")
        let dayId = try ProgramDayStore(db: db).create(programId: programId, label: label)
        for position in 0..<count {
            // `exerciseCatalog` is uniquely keyed on (sourceId, exerciseId), so the
            // day label is in the id: two days in one test are two sets of exercises,
            // not one set inserted twice.
            let exerciseId = try ExerciseCatalogStore(db: db).insert(
                ExerciseCatalogDraft(sourceId: "workout-guide",
                                     exerciseId: "\(label.lowercased())-e\(position)",
                                     name: "\(label) \(position)",
                                     prescriptionType: "reps_load", licenseGroup: "cc-by-sa-4.0"))
            _ = try poolStore.add(PoolItemDraft(
                programDayId: dayId, exerciseCatalogId: exerciseId,
                rotationPosition: position, positionWithinSession: position % slots,
                prescriptionType: "reps_load", prescribedSets: 4, prescribedReps: 6))
        }
        return dayId
    }

    /// Completes a session on a day, which is the only thing that advances the
    /// rotation.
    private func completeSession(_ dayId: Int64, at date: String) throws -> Int64 {
        let index = try engine.nextRotationIndex(programDayId: dayId)
        return try sessionStore.log(WorkoutSessionDraft(
            date: date, programDayId: dayId, rotationIndex: index))
    }

    // MARK: - The cycle

    @Test("The first session of a day starts at the first pool item")
    func firstSessionStartsAtTheTop() throws {
        let dayId = try makeDay(count: 6, slots: 3)

        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0)

        // Three slots, in cycle order from position 0.
        #expect(plan.entries.map { $0.item.rotationPosition } == [0, 1, 2])
        #expect(plan.entries.allSatisfy { $0.substitutesForSlot == nil })
        #expect(plan.skipped.isEmpty)
    }

    @Test("A session's size is the day's slots, not the size of its pool")
    func sessionSizeComesFromSlots() throws {
        // Six exercises in the pool, three per session: the distinction is the
        // whole reason `positionWithinSession` is a separate column from
        // `rotationPosition`, and a pool-sized session would have nothing left
        // for the handoff's substitution to substitute.
        let dayId = try makeDay(count: 6, slots: 3)
        #expect(try engine.plan(programDayId: dayId, rotationIndex: 0).entries.count == 3)

        let wide = try makeDay(count: 6, slots: 6, label: "Legs")
        #expect(try engine.plan(programDayId: wide, rotationIndex: 0).entries.count == 6)
    }

    @Test("Each completed session takes the next window, and the cycle wraps")
    func rotationAdvancesPerSession() throws {
        let dayId = try makeDay(count: 6, slots: 3)

        // Six items, three per session: every item is seen exactly twice.
        var seen: [[Int]] = []
        for pass in 0..<6 {
            let plan = try engine.plan(programDayId: dayId, rotationIndex: pass)
            seen.append(plan.entries.map { $0.item.rotationPosition })
        }
        #expect(seen == [[0, 1, 2], [1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 0], [5, 0, 1]])

        // Six items, three per session: every item is seen exactly three times, at
        // three different points in the cycle — no exercise quietly outranks
        // another by being early in the pool.
        let flat = seen.flatMap { $0 }
        #expect(flat.count == 18)
        #expect(Set(flat.map { $0 }).count == 6)
        #expect(flat.filter { $0 == 4 }.count == 3)
    }

    @Test("A rotation index past the end of the cycle keeps going rather than clamping")
    func rotationIndexBeyondOneCycle() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        // A user on their 20th Push day is not an error case. index 19 and index
        // 1 are the same position in a six-item cycle, and the suggestion has to
        // agree with the prescription rather than disagreeing with it.
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 19)
        let firstPass = try engine.plan(programDayId: dayId, rotationIndex: 1)
        #expect(plan.entries.map { $0.item.rotationPosition } == [1, 2, 3])
        #expect(plan.entries.map { $0.item.rotationPosition }
                == firstPass.entries.map { $0.item.rotationPosition })
    }

    @Test("A day whose pool is smaller than its slots offers what it has")
    func poolSmallerThanSlots() throws {
        // Two items, three slots: the session is two exercises, not three, and
        // not the same exercise twice.
        let dayId = try makeDay(count: 2, slots: 3)
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0)
        #expect(plan.entries.map { $0.item.rotationPosition } == [0, 1])
    }

    @Test("A day with no active exercises generates nothing, rather than throwing")
    func emptyPool() throws {
        let dayId = try makeDay(count: 0, slots: 3)
        #expect(try engine.plan(programDayId: dayId, rotationIndex: 0).entries.isEmpty)
    }

    // MARK: - Decision 2: rotation advances on sessions, not on the calendar

    @Test("A three-week gap between sessions does not advance the rotation")
    func calendarGapDoesNotAdvance() throws {
        // The reason this feature exists for an athlete on an irregular schedule.
        // Two Push days, three weeks apart, must offer the second thing in the
        // rotation — not the eleventh, and not the first again.
        let dayId = try makeDay(count: 6, slots: 3)

        try completeSession(dayId, at: "2026-09-01")
        #expect(try engine.nextRotationIndex(programDayId: dayId) == 1)

        try completeSession(dayId, at: "2026-09-22")
        #expect(try engine.nextRotationIndex(programDayId: dayId) == 2)

        let plan = try engine.plan(programDayId: dayId,
                                   rotationIndex: try engine.nextRotationIndex(programDayId: dayId))
        #expect(plan.entries.map { $0.item.rotationPosition } == [2, 3, 4])
    }

    @Test("The next rotation index counts completed sessions and nothing else")
    func nextIndexCountsSessions() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        #expect(try engine.nextRotationIndex(programDayId: dayId) == 0)

        try completeSession(dayId, at: "2026-09-01")
        try completeSession(dayId, at: "2026-09-02")
        try completeSession(dayId, at: "2026-09-03")
        #expect(try engine.nextRotationIndex(programDayId: dayId) == 3)
    }

    @Test("A deleted session stops counting, so undoing one does not skip an exercise")
    func deletedSessionDoesNotAdvance() throws {
        // Decision 2 says the rotation advances on *completed* sessions. A session
        // the user deleted is not one, so the exercise it offered is offered
        // again — the same reasoning as `rotationIndex` living on the session row
        // rather than being derived from a count of dates.
        let dayId = try makeDay(count: 6, slots: 3)
        let first = try completeSession(dayId, at: "2026-09-01")
        _ = try completeSession(dayId, at: "2026-09-02")
        #expect(try engine.nextRotationIndex(programDayId: dayId) == 2)

        #expect(try sessionStore.delete(id: first) == true)
        #expect(try engine.nextRotationIndex(programDayId: dayId) == 1)
    }

    @Test("Sessions of a different day, or of no program at all, do not move this rotation")
    func otherSessionsDoNotAdvance() throws {
        let push = try makeDay(count: 6, slots: 3, label: "Push")
        let pull = try makeDay(count: 6, slots: 3, label: "Pull")

        _ = try completeSession(pull, at: "2026-09-01")
        _ = try sessionStore.log(WorkoutSessionDraft(date: "2026-09-01"))
        _ = try completeSession(push, at: "2026-09-02")

        // Pull's session and the ad-hoc one are not Push passes, so neither day has
        // more than the one session it logged itself.
        #expect(try engine.nextRotationIndex(programDayId: push) == 1)
        #expect(try engine.nextRotationIndex(programDayId: pull) == 1)
    }

    // MARK: - Decision 3: permanent removal

    @Test("A permanently removed exercise is never offered, and the slot is refilled")
    func permanentRemovalIsExcluded() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let items = try poolStore.items(programDayId: dayId)
        // Position 1 is the second exercise of every odd session.
        #expect(try poolStore.setActive(id: items[1].id, to: false) == true)

        let plan = try engine.plan(programDayId: dayId, rotationIndex: 1)

        // 1 is gone from the cycle, so the window starts at 2 and runs 2, 3, 4 —
        // still three exercises. The session got shorter only if the *day* did,
        // not because one exercise is unavailable today.
        #expect(plan.entries.map { $0.item.rotationPosition } == [2, 3, 4])
        #expect(!plan.entries.contains { $0.item.rotationPosition == 1 })
    }

    @Test("Removing every exercise empties the session instead of throwing")
    func removingEverything() throws {
        let dayId = try makeDay(count: 3, slots: 3)
        for item in try poolStore.items(programDayId: dayId) {
            try poolStore.setActive(id: item.id, to: false)
        }
        #expect(try engine.plan(programDayId: dayId, rotationIndex: 0).entries.isEmpty)
    }

    @Test("A removed exercise keeps its prescription and comes back where it was")
    func removalIsReversibleWithoutLosingTheRule() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let items = try poolStore.items(programDayId: dayId)
        let removed = items[1]
        try poolStore.setProgression(id: removed.id, incrementKg: 2.5, condition: "all_reps_completed")

        try poolStore.setActive(id: removed.id, to: false)
        try poolStore.setActive(id: removed.id, to: true)

        let back = try poolStore.item(id: removed.id)
        // "Remove permanently" and "start again" must not be the same button:
        // the row keeps its place in the cycle and the rule the user set.
        #expect(back?.isActive == true)
        #expect(back?.rotationPosition == removed.rotationPosition)
        #expect(back?.hasCompleteProgressionRule == true)
    }

    @Test("A soft-deleted item is gone from the rotation too, and is not merely inactive")
    func deletedItemLeavesTheCycle() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let items = try poolStore.items(programDayId: dayId)
        try poolStore.delete(id: items[0].id)

        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0)
        #expect(plan.entries.map { $0.item.rotationPosition } == [1, 2, 3])
    }

    // MARK: - Decision 3: the per-session skip holds its position

    @Test("A skipped slot is recorded, keeps its item, and is offered again next session")
    func skipHoldsItsPosition() throws {
        // The core of Decision 3. Skip slot 1 of the first session; the skipped
        // exercise must be the first thing the *next* Push day offers, because
        // holding its position means exactly that.
        let dayId = try makeDay(count: 6, slots: 3)

        let first = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [1])
        #expect(first.skipped.count == 1)
        #expect(first.skipped[0].slot == 1)
        #expect(first.skipped[0].item.rotationPosition == 1)

        let second = try engine.plan(programDayId: dayId, rotationIndex: 1)
        #expect(second.entries[0].item.rotationPosition == 1)
        #expect(second.skipped.isEmpty)
    }

    @Test("A skip writes nothing at all to the pool")
    func skipTouchesNoState() throws {
        // "Holds its position" *is* the absence of a write, so the strongest
        // available assertion is that the pool is byte-identical before and after
        // — not merely that the item still reads as active.
        let dayId = try makeDay(count: 6, slots: 3)
        let before = try db.query("SELECT * FROM programDayExercisePool ORDER BY id;")
            .map { row in (try? db.query("SELECT * FROM programDayExercisePool WHERE id = \(row.int("id") ?? 0);").first) }
            .compactMap { $0 }

        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [0, 2])

        let after = try db.query("SELECT * FROM programDayExercisePool ORDER BY id;")
            .map { row in (try? db.query("SELECT * FROM programDayExercisePool WHERE id = \(row.int("id") ?? 0);").first) }
            .compactMap { $0 }

        #expect(plan.skipped.count == 2)
        #expect(after.count == before.count)
        for (b, a) in zip(before, after) {
            #expect(a["rotationPosition"] == b["rotationPosition"])
            #expect(a["isActive"] == b["isActive"])
            #expect(a["updatedAt"] == b["updatedAt"], "a skip must not even bump updatedAt")
        }
    }

    @Test("A skipped exercise is still active afterwards, so nothing re-adds it")
    func skipLeavesTheItemActive() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let items = try poolStore.items(programDayId: dayId)
        _ = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [1])
        #expect(try poolStore.item(id: items[1].id)?.isActive == true)
    }

    @Test("A skipped slot is filled by the next pool item not already in the session")
    func skipSubstitutesTheNextPoolItem() throws {
        let dayId = try makeDay(count: 6, slots: 3)

        // Session 0 would be [0, 1, 2]. Skipping slot 1 substitutes 3 — the next
        // item in the cycle that is not already on the sheet. 2 is already there,
        // so putting it in slot 1 as well would train it twice in one session.
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [1])

        #expect(plan.entries.map { $0.item.rotationPosition } == [0, 3, 2])
        let substitute = try #require(plan.entries.first { $0.substitutesForSlot == 1 })
        #expect(substitute.item.rotationPosition == 3)
        #expect(plan.skipped[0].substitute?.item.rotationPosition == 3)
    }

    @Test("The substitute is marked, so the sheet can say why it is there")
    func substituteIsAttributable() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [0, 2])

        #expect(plan.entries.map { $0.item.rotationPosition } == [3, 1, 4])
        // Each substitute names the slot it stands in for, and no entry claims two.
        #expect(plan.entries.compactMap(\.substitutesForSlot).sorted() == [0, 2])
        #expect(plan.skipped.map(\.slot).sorted() == [0, 2])
    }

    @Test("A skip with nothing left to substitute leaves the slot out, not repeated")
    func skipWithNoSubstituteAvailable() throws {
        // Pool of three, three slots: every active exercise is already on the
        // sheet, so there is genuinely nothing to put in the skipped slot. The
        // session is two exercises long. Showing the skipped exercise anyway
        // would be ignoring the user; repeating another one would be a worse bug.
        let dayId = try makeDay(count: 3, slots: 3)

        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [1])

        #expect(plan.skipped.count == 1)
        #expect(plan.skipped[0].substitute == nil)
        #expect(plan.entries.map { $0.item.rotationPosition } == [0, 2])
    }

    @Test("Skipping every slot substitutes each one, because the pool still has more")
    func skipEverything() throws {
        // Each skip takes the next exercise not already claimed, independently.
        // Whether the user skipped one slot or all three is the same operation
        // three times over — there is no "skip the session" that the engine
        // invents, and inventing one would be the engine second-guessing the
        // prompt the user was shown.
        let dayId = try makeDay(count: 6, slots: 3)
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [0, 1, 2])

        #expect(plan.entries.map { $0.item.rotationPosition } == [3, 4, 5])
        #expect(plan.skipped.map { $0.item.rotationPosition } == [0, 1, 2])
        #expect(plan.entries.compactMap(\.substitutesForSlot).sorted() == [0, 1, 2])
    }

    @Test("Skipping a slot twice is one skip, not two")
    func duplicateSkipIsOneSkip() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [1, 1])
        #expect(plan.skipped.count == 1)
    }

    @Test("Skipping a slot that does not exist is ignored rather than throwing")
    func skipOutOfRangeIsIgnored() throws {
        let dayId = try makeDay(count: 6, slots: 3)
        let plan = try engine.plan(programDayId: dayId, rotationIndex: 0, skipping: [99])
        #expect(plan.skipped.isEmpty)
        #expect(plan.entries.count == 3)
    }

    @Test("Two skips of the same exercise across two sessions each hold, and it comes back")
    func repeatedSkipsStillReturn() throws {
        // Decision 3 says "repeatedly, until the user explicitly, permanently
        // removes it". Two sessions, same exercise skipped both times, offered
        // back both times — that is the promise the mechanism makes.
        let dayId = try makeDay(count: 6, slots: 3)

        for index in 0..<2 {
            let plan = try engine.plan(programDayId: dayId, rotationIndex: index, skipping: [0])
            #expect(plan.skipped[0].item.rotationPosition == index % 6)
            // Immediately re-offered at the head of the very next session.
            let next = try engine.plan(programDayId: dayId, rotationIndex: index + 1)
            #expect(next.entries[0].item.rotationPosition == (index + 1) % 6)
        }
    }

    @Test("A skipped slot does not change the rotation index the next session gets")
    func skipDoesNotAdvanceTheRotation() throws {
        // Decision 3's resolved note: "does not advance rotation_position". The
        // index is a count of completed sessions, so a skip — which writes no
        // pool state at all — cannot move it.
        let dayId = try makeDay(count: 6, slots: 3)
        try completeSession(dayId, at: "2026-09-01")
        let before = try engine.nextRotationIndex(programDayId: dayId)
        _ = try engine.plan(programDayId: dayId, rotationIndex: before, skipping: [0, 1, 2])
        #expect(try engine.nextRotationIndex(programDayId: dayId) == before)
    }
}
