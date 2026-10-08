import Foundation
import AlmanacCore

/// One line on a generated session, as the session screen holds it.
///
/// **The prescription and the log are different values here**, which is the whole
/// of `docs/features/training-program.md` §2: `prescription` is what this
/// session asked for — the pool's own numbers, possibly scaled by a readiness
/// band — and the `actual*` fields are what the user did. They are written to
/// `workoutBout.prescribed*` and `workoutBout.actual*` respectively, and nothing
/// in this type can turn one into the other.
struct ProgramSessionLog {
    let item: PoolItemEntry
    /// What this session prescribed. `ReadinessAdjustment.prescription` is pure,
    /// so this is a copy of the plan rather than an edit to it.
    let prescription: AdjustedPrescription
    /// Null is a real answer — a bodyweight movement, or a session the user has
    /// not chosen one for yet. It is never a fifth variant.
    var equipmentVariant: EquipmentVariant?
    /// Decision 3's per-session skip. The bout exists with this true and no
    /// actuals; the pool is not touched, so the item holds its rotation
    /// position and is offered again next time.
    var skippedForSession: Bool
    var actualSets: Int?
    var actualReps: Int?
    var actualLoadKg: Double?
    var actualDurationSeconds: Double?
    var actualRounds: Int?
    var rpe: Int?

    /// Everything past the prescription defaults to "the user has not said".
    /// There is no zero: §9.1's rule against standing in for absence with a
    /// number is the reason a bout's untouched fields stay null rather than 0.
    init(item: PoolItemEntry,
         prescription: AdjustedPrescription,
         equipmentVariant: EquipmentVariant? = nil,
         skippedForSession: Bool = false,
         actualSets: Int? = nil,
         actualReps: Int? = nil,
         actualLoadKg: Double? = nil,
         actualDurationSeconds: Double? = nil,
         actualRounds: Int? = nil,
         rpe: Int? = nil) {
        self.item = item
        self.prescription = prescription
        self.equipmentVariant = equipmentVariant
        self.skippedForSession = skippedForSession
        self.actualSets = actualSets
        self.actualReps = actualReps
        self.actualLoadKg = actualLoadKg
        self.actualDurationSeconds = actualDurationSeconds
        self.actualRounds = actualRounds
        self.rpe = rpe
    }
}

/// The program layer's screen state, the same one-`Database` shape as
/// `TrainingModel` and `ReadinessModel`: configured once from `AlmanacApp`, and
/// the only thing in the app that writes the three program tables.
///
/// **It holds no rules.** Rotation is `RotationEngine`, the readiness coupling is
/// `ReadinessAdjustment`, the progression suggestion is `ExerciseProgression`
/// and the two graphs are `EquipmentVariantGraph` — all in `AlmanacCore` and all
/// tested there. What is left here is the part SwiftUI needs: reading a day's
/// pool into `@Published` arrays, and turning a screen's edits into store calls.
@MainActor
final class ProgramModel: ObservableObject {
    /// Live programs, by name — `ProgramStore.programs()`, which excludes
    /// soft-deleted ones.
    @Published private(set) var programs: [TrainingProgramEntry] = []
    /// A program's days in authoring order (`ORDER BY id`), never alphabetical:
    /// "Push, Pull, Legs" is the order the user typed, and a picker that sorted
    /// it would make the split read as a set of unrelated labels.
    @Published private(set) var daysByProgram: [Int64: [ProgramDayEntry]] = [:]
    /// A day's pool, keyed by day. The **authoring** read (`items`), so inactive
    /// items are present and greyed out — "why isn't this being offered" has to
    /// be answerable.
    @Published private(set) var itemsByDay: [Int64: [PoolItemEntry]] = [:]
    /// Today's readiness score, or nil when there is not one.
    ///
    /// Nil is the ordinary case on a fresh install and it is the reason
    /// `ReadinessAdjustment.prescription(for:score:)` takes an `Int?`: no score
    /// means the prescription is shown exactly as written, and the UI says the
    /// adjustment is unavailable rather than pretending a score of zero.
    @Published private(set) var todayReadinessScore: Int?
    /// Set when a read failed, cleared the moment one succeeds. Never a
    /// substitute for an empty state — "no programs yet" and "the programs could
    /// not be read" are different claims.
    @Published private(set) var readProblem: String?

    private var db: Database?
    private var programStore: ProgramStore?
    private var dayStore: ProgramDayStore?
    private var poolStore: ProgramDayExercisePoolStore?
    private var sessionStore: WorkoutSessionStore?
    private var boutStore: WorkoutBoutStore?
    private var rotation: RotationEngine?
    private let timeModel = TimeModel(timeZone: .current)

    /// The shared connection, for the screens that read their own tables.
    /// Nil until `configure(db:)` has run.
    var database: Database? { db }

    func configure(db: Database?) {
        guard let db, self.db == nil else { return }
        self.db = db
        programStore = ProgramStore(db: db)
        dayStore = ProgramDayStore(db: db)
        poolStore = ProgramDayExercisePoolStore(db: db)
        sessionStore = WorkoutSessionStore(db: db)
        boutStore = WorkoutBoutStore(db: db)
        rotation = RotationEngine(db: db)
        refresh()
    }

    func refresh() {
        guard let programStore, let dayStore else { return }
        do {
            programs = try programStore.programs()
            var days: [Int64: [ProgramDayEntry]] = [:]
            for program in programs {
                days[program.id] = try dayStore.days(programId: program.id)
            }
            daysByProgram = days
            todayReadinessScore = readTodaysReadiness()
            readProblem = nil
        } catch {
            readProblem = String(localized: "Could not read your training programs.")
        }
    }

    /// Today's readiness score, or nil.
    ///
    /// Read from the stored record rather than recomputed: `ReadinessModel` owns
    /// evaluating the score and has already written it, and a second evaluation
    /// here would be a second answer to §9.1's question. Nil when the newest
    /// record is not today's — a score from yesterday is not today's readiness,
    /// and offering it would scale a prescription against a stale day.
    private func readTodaysReadiness() -> Int? {
        guard let db else { return nil }
        let today = timeModel.logicalDay(Date()).value
        guard let latest = try? ReadinessRecordStore(db: db).records(limit: 1).last,
              latest.anchorDate == today else { return nil }
        return latest.score
    }

    // MARK: - Reads

    func days(of programId: Int64) -> [ProgramDayEntry] { daysByProgram[programId] ?? [] }

    /// A day's pool, loaded on demand and then held. Rotation reads
    /// `activeItems` separately inside `RotationEngine` — this is the authoring
    /// view, and the two answers are meant to disagree.
    func loadItems(programDayId: Int64) {
        guard let poolStore else { return }
        do {
            itemsByDay[programDayId] = try poolStore.items(programDayId: programDayId)
            readProblem = nil
        } catch {
            readProblem = String(localized: "Could not read this day's exercises.")
        }
    }

    func items(programDayId: Int64) -> [PoolItemEntry] { itemsByDay[programDayId] ?? [] }

    func exerciseName(for exerciseCatalogId: Int64, in catalog: [ExerciseCatalogEntry]) -> String {
        catalog.first { $0.id == exerciseCatalogId }?.name ?? String(localized: "Unknown exercise")
    }

    // MARK: - Authoring

    @discardableResult
    func createProgram(name: String, notes: String?) throws -> Int64 {
        guard let programStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let id = try programStore.create(name: name, notes: notes)
        refresh()
        return id
    }

    func updateProgram(id: Int64, name: String, notes: String?) throws {
        guard let programStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        guard try programStore.update(id: id, name: name, notes: notes) else {
            throw EditorFailure(message: String(localized: "That program no longer exists — it may have been deleted on another screen."))
        }
        refresh()
    }

    /// Soft delete, so a past session can still name the program it came from.
    func deleteProgram(id: Int64) throws {
        guard let programStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try programStore.delete(id: id)
        refresh()
    }

    @discardableResult
    func createDay(programId: Int64, label: String) throws -> Int64 {
        guard let dayStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let id = try dayStore.create(programId: programId, label: label)
        refresh()
        return id
    }

    func updateDay(id: Int64, label: String) throws {
        guard let dayStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        guard try dayStore.update(id: id, label: label) else {
            throw EditorFailure(message: String(localized: "That day no longer exists — it may have been deleted on another screen."))
        }
        refresh()
    }

    func deleteDay(id: Int64) throws {
        guard let dayStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try dayStore.delete(id: id)
        refresh()
    }

    @discardableResult
    func addPoolItem(_ draft: PoolItemDraft) throws -> Int64 {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let id = try poolStore.add(draft)
        loadItems(programDayId: draft.programDayId)
        return id
    }

    func updatePrescription(id: Int64, _ draft: PoolItemDraft) throws {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        guard try poolStore.updatePrescription(
            id: id, prescriptionType: draft.prescriptionType, containerType: draft.containerType,
            prescribedSets: draft.prescribedSets, prescribedReps: draft.prescribedReps,
            prescribedLoadKg: draft.prescribedLoadKg,
            prescribedDurationSeconds: draft.prescribedDurationSeconds,
            prescribedRestSeconds: draft.prescribedRestSeconds, notes: draft.notes) else {
            throw EditorFailure(message: String(localized: "That exercise no longer exists in this day."))
        }
        loadItems(programDayId: draft.programDayId)
    }

    /// Moves an item within the cycle and/or to another slot — the only way
    /// `rotationPosition` ever changes, and only at an explicit authoring act.
    func setPositions(id: Int64, programDayId: Int64, rotationPosition: Int, positionWithinSession: Int) throws {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try poolStore.setPositions(id: id, rotationPosition: rotationPosition,
                                   positionWithinSession: positionWithinSession)
        loadItems(programDayId: programDayId)
    }

    /// Decision 3's two mechanisms, from the one typed entry point. A per-session
    /// skip writes nothing at all — holding its rotation position *is* the absence
    /// of a write — so only `.permanent` re-reads the day behind it.
    func setAvailability(_ availability: ExerciseAvailability, item id: Int64, programDayId: Int64) throws {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try poolStore.skipForSessionOnly(availability, item: id)
        if availability.mutatesPool { loadItems(programDayId: programDayId) }
    }

    /// Decision 3's permanent-removal reversal: puts the item back in the
    /// rotation, keeping its cycle position, prescription and progression rule
    /// (the store's `setActive` is reversible by design — deletion is not).
    func restore(item id: Int64, programDayId: Int64) throws {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try poolStore.setActive(id: id, to: true)
        loadItems(programDayId: programDayId)
    }

    func setProgression(id: Int64, programDayId: Int64, incrementKg: Double?, condition: ProgressionCondition?) throws {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try poolStore.setProgression(id: id, incrementKg: incrementKg, condition: condition?.rawValue)
        loadItems(programDayId: programDayId)
    }

    func deletePoolItem(id: Int64, programDayId: Int64) throws {
        guard let poolStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try poolStore.delete(id: id)
        loadItems(programDayId: programDayId)
    }

    // MARK: - Starting a session

    /// Which pass through the pool the next session of this day is.
    ///
    /// Counts live sessions and never consults a date (Decision 2), so a week off
    /// costs nothing.
    func nextRotationIndex(programDayId: Int64) -> Int? {
        guard let rotation else { return nil }
        return try? rotation.nextRotationIndex(programDayId: programDayId)
    }

    /// Generates the day's exercise list for one pass, honouring the slots the
    /// user has already skipped for this session.
    func plan(programDayId: Int64, skipping: Set<Int>) -> RotationPlan? {
        guard let rotation, let index = nextRotationIndex(programDayId: programDayId) else { return nil }
        return try? rotation.plan(programDayId: programDayId, rotationIndex: index, skipping: skipping)
    }

    /// The prescription for one pool item on this session, scaled when the user
    /// said yes to folding in their readiness.
    ///
    /// A no score or a "no" is the same answer — the plan as written — because
    /// `prescription(for:score:)` takes `nil` for exactly that and there is no
    /// third possibility worth a third code path.
    func prescription(for item: PoolItemEntry, readinessAdjusted: Bool) -> AdjustedPrescription {
        ReadinessAdjustment.prescription(for: item, score: readinessAdjusted ? todayReadinessScore : nil)
    }

    /// Per-exercise progression suggestions for a generated sheet, in one query.
    func suggestions(for items: [PoolItemEntry]) -> [Int64: ProgressionSuggestion] {
        guard let db else { return [:] }
        return (try? ExerciseProgression(db: db).suggestions(for: items)) ?? [:]
    }

    /// Writes the finished session: one `workoutSession` row carrying the day and
    /// the pass, then one `workoutBout` per line — actuals where the user entered
    /// them, `wasSkippedForSession` for a held slot.
    ///
    /// **The session row is written here, at Finish, not when the screen opened.**
    /// `RotationEngine.nextRotationIndex` counts live session rows, so a row
    /// created at start would consume a rotation pass for a session the user then
    /// abandoned — Decision 2 counts *completed* sessions, and an abandoned sheet
    /// is not one. Holding the sheet in memory until Finish is what makes that
    /// true in the database rather than only in the copy.
    func finishSession(programDayId: Int64,
                       readinessAdjusted: Bool,
                       logs: [ProgramSessionLog],
                       durationMinutes: Int?,
                       rpe: Int?,
                       notes: String?) throws {
        guard let sessionStore, let boutStore, let rotation else {
            throw EditorFailure(message: String(localized: "The database is unavailable."))
        }
        let now = Date()
        let today = timeModel.logicalDay(now).value
        let rotationIndex = try rotation.nextRotationIndex(programDayId: programDayId)

        let sessionId = try sessionStore.log(WorkoutSessionDraft(
            date: today, startTimestamp: now, endTimestamp: now,
            durationMinutes: durationMinutes, rpe: rpe, notes: notes,
            programDayId: programDayId, rotationIndex: rotationIndex,
            readinessAdjusted: readinessAdjusted))

        for (index, entry) in logs.enumerated() {
            try boutStore.log(WorkoutBoutDraft(
                sessionId: sessionId,
                exerciseCatalogId: entry.item.exerciseCatalogId,
                sequenceIndex: index,
                prescriptionType: entry.item.prescriptionType,
                containerType: entry.item.containerType,
                // Prescribed is what this session asked for, adjustment included.
                prescribedSets: entry.prescription.sets,
                prescribedReps: entry.prescription.reps,
                prescribedLoadKg: entry.prescription.loadKg,
                prescribedDurationSeconds: entry.prescription.durationSeconds,
                prescribedRestSeconds: entry.prescription.restSeconds,
                actualSets: entry.skippedForSession ? nil : entry.actualSets,
                actualReps: entry.skippedForSession ? nil : entry.actualReps,
                actualLoadKg: entry.skippedForSession ? nil : entry.actualLoadKg,
                actualDurationSeconds: entry.skippedForSession ? nil : entry.actualDurationSeconds,
                actualRounds: entry.skippedForSession ? nil : entry.actualRounds,
                rpe: entry.skippedForSession ? nil : entry.rpe,
                equipmentVariant: entry.equipmentVariant?.rawValue,
                wasSkippedForSession: entry.skippedForSession))
        }
    }
}