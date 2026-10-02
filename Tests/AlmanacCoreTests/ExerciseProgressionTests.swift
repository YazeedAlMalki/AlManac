import Foundation
import Testing
@testable import AlmanacCore

/// Decision 4 — per-exercise progression. Off by default, user-defined
/// increment, user-defined condition, **never a global rule**.
///
/// The property that matters is the last word of that sentence, and it is
/// asserted as a property over a whole day rather than case by case: a
/// progression rule that is checked one exercise at a time is one that eventually
/// grows a "and for the other four, +2.5 kg" clause, which is the thing Decision
/// 4 exists to prevent.
///
/// The second property is that progression is a **suggestion about a load**, not a
/// write. Nothing in this file changes the pool, and `suggestionsDoNotTouchThePool`
/// says so, because a rule that silently edited the user's own prescription would
/// be indistinguishable from a rule that trained them progressively.
@Suite("Exercise progression")
struct ExerciseProgressionTests {
    let db = try! TestDatabase()

    private var progression: ExerciseProgression { ExerciseProgression(db: db) }
    private var poolStore: ProgramDayExercisePoolStore { ProgramDayExercisePoolStore(db: db) }
    private var boutStore: WorkoutBoutStore { WorkoutBoutStore(db: db) }
    private var sessionStore: WorkoutSessionStore { WorkoutSessionStore(db: db) }

    // MARK: - Fixtures

    /// One program with one Push day. Passed explicitly to `makeItem` rather than
    /// memoised on the suite: several items have to share one day for Decision 4's
    /// "within a day" tests to mean anything, and a stored fixture on a `struct`
    /// suite cannot be filled in on first use.
    private func makeDay(name: String = "My PPL") throws -> Int64 {
        let programId = try ProgramStore(db: db).create(name: name)
        return try ProgramDayStore(db: db).create(programId: programId, label: "Push")
    }

    private func makeExercise(_ id: String) throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "workout-guide", exerciseId: id, name: "Exercise \(id)",
                                 prescriptionType: "reps_load", licenseGroup: "cc-by-sa-4.0"))
    }

    /// A pool item on a Push day.
    @discardableResult
    private func makeItem(in dayId: Int64,
                          exerciseId: String,
                          rotationPosition: Int = 0,
                          progressionEnabled: Bool = false,
                          incrementKg: Double? = nil,
                          condition: String? = nil,
                          prescribedLoadKg: Double? = 100) throws -> Int64 {
        let exerciseCatalogId = try makeExercise(exerciseId)
        return try poolStore.add(PoolItemDraft(
            programDayId: dayId, exerciseCatalogId: exerciseCatalogId,
            rotationPosition: rotationPosition, prescriptionType: "reps_load",
            prescribedSets: 4, prescribedReps: 6, prescribedLoadKg: prescribedLoadKg,
            progressionEnabled: progressionEnabled, progressionIncrementKg: incrementKg,
            progressionCondition: condition))
    }

    /// A logged performance of the exercise. This is the only thing a suggestion
    /// is ever based on — never the prescription.
    @discardableResult
    private func perform(exerciseCatalogId: Int64, date: String,
                         reps: Int? = 6, loadKg: Double? = 100,
                         prescribedReps: Int? = 6,
                         skipped: Bool = false) throws -> Int64 {
        let sessionId = try sessionStore.log(WorkoutSessionDraft(date: date))
        return try boutStore.log(WorkoutBoutDraft(
            sessionId: sessionId, exerciseCatalogId: exerciseCatalogId,
            prescriptionType: "reps_load", prescribedReps: prescribedReps,
            actualReps: reps, actualLoadKg: loadKg, wasSkippedForSession: skipped))
    }

    private func item(_ id: Int64) throws -> PoolItemEntry {
        let found = try poolStore.item(id: id)
        return try #require(found)
    }

    /// The suggestion for an item, requiring one. Hoisted out of the `#require`
    /// because a throwing call inside that macro loses its `try`.
    private func suggestion(_ item: PoolItemEntry) throws -> ProgressionSuggestion {
        let found = try progression.suggestion(for: item)
        return try #require(found)
    }

    // MARK: - Off by default

    @Test("Progression is off by default, and an exercise with no rule has no suggestion")
    func offByDefault() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 100)

        // A perfect session, a log full of them, and still nothing: the rule has to
        // be the user's.
        #expect(try progression.suggestion(for: item(itemId)) == nil)
    }

    @Test("An enabled rule with only half of itself produces no suggestion")
    func incompleteRuleProducesNothing() throws {
        // `ProgramDayExercisePoolStore` refuses to store this, but an entry can be
        // built by hand and a suggestion that read half a rule would be inventing
        // the other half.
        let handBuilt = PoolItemEntry(
            id: 1, programDayId: 1, exerciseCatalogId: 1, rotationPosition: 0,
            positionWithinSession: 0, isActive: true, prescriptionType: "reps_load",
            containerType: nil, prescribedSets: 4, prescribedReps: 6, prescribedLoadKg: 100,
            prescribedDurationSeconds: nil, prescribedRestSeconds: 90,
            progressionEnabled: true, progressionIncrementKg: 2.5, progressionCondition: nil,
            notes: nil, deletedAt: nil, createdAt: "", updatedAt: "")
        #expect(try progression.suggestion(for: handBuilt) == nil)

        let noIncrement = PoolItemEntry(
            id: 1, programDayId: 1, exerciseCatalogId: 1, rotationPosition: 0,
            positionWithinSession: 0, isActive: true, prescriptionType: "reps_load",
            containerType: nil, prescribedSets: 4, prescribedReps: 6, prescribedLoadKg: 100,
            prescribedDurationSeconds: nil, prescribedRestSeconds: 90,
            progressionEnabled: true, progressionIncrementKg: nil,
            progressionCondition: "all_reps_completed", notes: nil, deletedAt: nil,
            createdAt: "", updatedAt: "")
        #expect(try progression.suggestion(for: noIncrement) == nil)
    }

    @Test("A condition this build has never heard of produces no suggestion")
    func unknownConditionProducesNothing() throws {
        // The column has a CHECK, so this cannot be written — but an unrecognised
        // rule must not be treated as a satisfied one either, which is the failure
        // that would quietly add weight every session.
        let handBuilt = PoolItemEntry(
            id: 1, programDayId: 1, exerciseCatalogId: 1, rotationPosition: 0,
            positionWithinSession: 0, isActive: true, prescriptionType: "reps_load",
            containerType: nil, prescribedSets: 4, prescribedReps: 6, prescribedLoadKg: 100,
            prescribedDurationSeconds: nil, prescribedRestSeconds: 90,
            progressionEnabled: true, progressionIncrementKg: 2.5,
            progressionCondition: "felt_good", notes: nil, deletedAt: nil,
            createdAt: "", updatedAt: "")
        #expect(try progression.suggestion(for: handBuilt) == nil)
    }

    // MARK: - The suggestion

    @Test("With nothing logged, there is nothing to progress from")
    func noHistory() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .nothingLogged)
    }

    @Test("Every prescribed rep hit means the user's own increment, once")
    func allRepsCompletedIncreases() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 100)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .increase(toKg: 102.5))
        #expect(suggestion.currentLoadKg == 100)
        #expect(suggestion.incrementKg == 2.5)
        #expect(suggestion.condition == .allRepsCompleted)
    }

    @Test("Missing a rep holds the load rather than increasing it")
    func missedRepsHolds() throws {
        let dayId = try makeDay()
        // The whole point of the condition. An engine that increments on "the user
        // trained this exercise" would add 2.5kg a session to someone who has been
        // failing reps for a fortnight.
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 4, loadKg: 100)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .hold(atKg: 100))
        #expect(suggestion.currentLoadKg == 100)
    }

    @Test("Only the most recent performance decides")
    func onlyTheLatestCounts() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 2, loadKg: 80)
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-08", reps: 6, loadKg: 100)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .increase(toKg: 102.5))
        #expect(suggestion.currentLoadKg == 100)
    }

    @Test("Extra reps beyond the prescription still satisfy the condition")
    func extraRepsStillCount() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 8, loadKg: 100)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .increase(toKg: 102.5))
    }

    @Test("A session with no prescribed reps to compare against holds rather than increases")
    func noPrescribedRepsHolds() throws {
        let dayId = try makeDay()
        // "Every prescribed set was completed" cannot be evaluated against nothing.
        // Guessing yes is the expensive direction to guess in.
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01",
                    reps: 6, loadKg: 100, prescribedReps: nil)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .hold(atKg: 100))
    }

    @Test("A bout skipped for the session is not an attempt at the exercise")
    func skippedBoutIsNotAnAttempt() throws {
        let dayId = try makeDay()
        // Decision 3's per-session skip writes a bout with no actuals. Counting it
        // as the latest performance would either hold the load forever or, worse,
        // suggest an increase from a session the user never did.
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 100)
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-08", reps: nil, loadKg: nil, skipped: true)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.currentLoadKg == 100)
        #expect(suggestion.outcome == .increase(toKg: 102.5))
    }

    @Test("The suggestion is built from what was lifted, not from what was written")
    func builtFromActuals() throws {
        let dayId = try makeDay()
        // The pool says 100; the user actually lifted 102.5 last time. Progressing
        // from the prescription would under-read the user by 2.5kg every session
        // and never catch up.
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed",
                                  prescribedLoadKg: 100)
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 102.5)

        let suggestion = try suggestion(item(itemId))
        #expect(suggestion.outcome == .increase(toKg: 105))
    }

    // MARK: - Per exercise, never global

    @Test("Two exercises with different increments each get their own suggestion")
    func progressionIsPerExercise() throws {
        let dayId = try makeDay()
        // Decision 4's sentence, made executable. A global "+2.5 kg" would give
        // both of these the same number.
        let squatId = try makeItem(in: dayId, exerciseId: "squat", rotationPosition: 0,
                                   progressionEnabled: true, incrementKg: 5,
                                   condition: "all_reps_completed", prescribedLoadKg: 100)
        let curlId = try makeItem(in: dayId, exerciseId: "curl", rotationPosition: 1,
                                  progressionEnabled: true, incrementKg: 1,
                                  condition: "all_reps_completed", prescribedLoadKg: 20)
        let squat = try item(squatId)
        let curl = try item(curlId)
        try perform(exerciseCatalogId: squat.exerciseCatalogId, date: "2026-09-01",
                    reps: 6, loadKg: 100)
        try perform(exerciseCatalogId: curl.exerciseCatalogId, date: "2026-09-01",
                    reps: 6, loadKg: 20)

        let squatSuggestion = try suggestion(squat)
        let curlSuggestion = try suggestion(curl)
        #expect(squatSuggestion.outcome == .increase(toKg: 105))
        #expect(curlSuggestion.outcome == .increase(toKg: 21))
    }

    @Test("A rule on one exercise says nothing about another's history")
    func aRuleDoesNotLeak() throws {
        let dayId = try makeDay()
        // The exercise *with* a rule has no history; the one *without* has plenty.
        // Without a rule, the exercise with plenty gets nothing — a global default
        // is exactly what this forbids.
        let ruledId = try makeItem(in: dayId, exerciseId: "squat", rotationPosition: 0,
                                   progressionEnabled: true, incrementKg: 2.5,
                                   condition: "all_reps_completed")
        let unruledId = try makeItem(in: dayId, exerciseId: "curl", rotationPosition: 1)
        let ruled = try item(ruledId)
        let unruled = try item(unruledId)
        try perform(exerciseCatalogId: unruled.exerciseCatalogId, date: "2026-09-01",
                    reps: 6, loadKg: 30)
        _ = try perform(exerciseCatalogId: ruled.exerciseCatalogId, date: "2026-09-01",
                        reps: 6, loadKg: 100)

        #expect(try progression.suggestion(for: ruled) != nil)
        #expect(try progression.suggestion(for: unruled) == nil)
    }

    @Test("One exercise logged in two programs is still one history")
    func historySpansPrograms() throws {
        // Progress belongs to the movement, not to the template it was prescribed
        // from. A user who trains the squat in a program and again on its own has
        // one squat, and a suggestion based on one program only would propose a
        // weight they have already passed.
        let programId = try ProgramStore(db: db).create(name: "My PPL")
        let dayId = try ProgramDayStore(db: db).create(programId: programId, label: "Push")
        let exerciseId = try makeExercise("squat")

        // First pass, prescribed with no rule and performed.
        let first = try poolStore.add(PoolItemDraft(
            programDayId: dayId, exerciseCatalogId: exerciseId, rotationPosition: 0,
            prescriptionType: "reps_load", prescribedLoadKg: 80))
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 80)

        // The rule is added afterwards — the user decides they want to progress
        // after a few sessions, which is the ordinary way this happens.
        _ = try poolStore.setProgression(id: first, incrementKg: 2.5,
                                         condition: "all_reps_completed")
        let second = try poolStore.add(PoolItemDraft(
            programDayId: dayId, exerciseCatalogId: exerciseId, rotationPosition: 1,
            prescriptionType: "reps_load", prescribedLoadKg: 100,
            progressionEnabled: true, progressionIncrementKg: 2.5,
            progressionCondition: "all_reps_completed"))

        let suggestion = try suggestion(item(second))
        #expect(suggestion.outcome == .increase(toKg: 82.5))
    }

    // MARK: - One read for a whole day

    @Test("A day's suggestions come back together, keyed by pool item")
    func bulkSuggestions() throws {
        let dayId = try makeDay()
        let ruledId = try makeItem(in: dayId, exerciseId: "squat", rotationPosition: 0,
                                   progressionEnabled: true, incrementKg: 2.5,
                                   condition: "all_reps_completed")
        let unruledId = try makeItem(in: dayId, exerciseId: "curl", rotationPosition: 1)

        let items = try poolStore.items(programDayId: dayId)
        #expect(items.count == 2)
        let before = try progression.suggestions(for: items)

        // Two items, one suggestion: the item with no rule is absent rather than
        // present-and-nil, so a caller iterating the result cannot accidentally
        // render a suggestion of nothing.
        #expect(before.count == 1)
        #expect(before[unruledId] == nil)
        #expect(before[ruledId]?.outcome == .nothingLogged)

        let squat = try item(ruledId)
        try perform(exerciseCatalogId: squat.exerciseCatalogId, date: "2026-09-01",
                    reps: 6, loadKg: 100)
        let after = try progression.suggestions(for: items)
        #expect(after[ruledId]?.outcome == .increase(toKg: 102.5))
        #expect(after[unruledId] == nil)
    }

    @Test("An empty day produces no suggestions rather than throwing")
    func bulkOverNoItems() throws {
        #expect(try progression.suggestions(for: []).isEmpty)
    }

    // MARK: - A suggestion is not a write

    @Test("Producing suggestions writes nothing to the pool")
    func suggestionsDoNotTouchThePool() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed",
                                  prescribedLoadKg: 100)
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 100)

        let before = try item(itemId)
        _ = try progression.suggestion(for: before)
        _ = try progression.suggestions(for: [before])
        let after = try item(itemId)

        // The user's prescription is theirs. Accepting a suggestion is a separate,
        // explicit act — and until it happens, every session shows the same
        // suggestion rather than quietly moving the plan.
        #expect(after.prescribedLoadKg == before.prescribedLoadKg)
        #expect(after.updatedAt == before.updatedAt)
    }

    @Test("The same history always gives the same suggestion")
    func suggestionIsDeterministic() throws {
        let dayId = try makeDay()
        let itemId = try makeItem(in: dayId, exerciseId: "squat", progressionEnabled: true,
                                  incrementKg: 2.5, condition: "all_reps_completed")
        let exerciseId = try item(itemId).exerciseCatalogId
        try perform(exerciseCatalogId: exerciseId, date: "2026-09-01", reps: 6, loadKg: 100)

        let first = try progression.suggestion(for: item(itemId))
        let second = try progression.suggestion(for: item(itemId))
        #expect(first == second)
    }
}
