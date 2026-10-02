import Foundation

/// The prescription for one exercise in one program's day, not yet written.
///
/// This is the draft `workoutBout` did not have. `WorkoutBoutDraft` mixes what
/// was planned with what was done, because a bout is a log of one session's
/// event; a pool item is only ever the plan, so the two never share a shape.
public struct PoolItemDraft: Sendable {
    public var programDayId: Int64
    public var exerciseCatalogId: Int64
    /// Where the item sits in the rotation cycle. See `RotationEngine`.
    public var rotationPosition: Int
    /// Which slot of a generated session this item occupies — this, and not the
    /// count of active items, is what says how many exercises a session of this
    /// day has.
    public var positionWithinSession: Int
    public var prescriptionType: String
    public var containerType: String?
    public var prescribedSets: Int?
    public var prescribedReps: Int?
    public var prescribedLoadKg: Double?
    public var prescribedDurationSeconds: Double?
    public var prescribedRestSeconds: Double?
    /// Decision 4: per exercise, off by default, with a user-defined increment
    /// and condition. Never a global rule.
    public var progressionEnabled: Bool
    public var progressionIncrementKg: Double?
    public var progressionCondition: String?
    public var notes: String?

    public init(programDayId: Int64, exerciseCatalogId: Int64,
                rotationPosition: Int, positionWithinSession: Int = 0,
                prescriptionType: String, containerType: String? = nil,
                prescribedSets: Int? = nil, prescribedReps: Int? = nil, prescribedLoadKg: Double? = nil,
                prescribedDurationSeconds: Double? = nil, prescribedRestSeconds: Double? = nil,
                progressionEnabled: Bool = false,
                progressionIncrementKg: Double? = nil, progressionCondition: String? = nil,
                notes: String? = nil) {
        self.programDayId = programDayId
        self.exerciseCatalogId = exerciseCatalogId
        self.rotationPosition = rotationPosition
        self.positionWithinSession = positionWithinSession
        self.prescriptionType = prescriptionType
        self.containerType = containerType
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.prescribedLoadKg = prescribedLoadKg
        self.prescribedDurationSeconds = prescribedDurationSeconds
        self.prescribedRestSeconds = prescribedRestSeconds
        self.progressionEnabled = progressionEnabled
        self.progressionIncrementKg = progressionIncrementKg
        self.progressionCondition = progressionCondition
        self.notes = notes
    }
}

/// One pool item read from storage — the prescription, never the log.
public struct PoolItemEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let programDayId: Int64
    public let exerciseCatalogId: Int64
    public let rotationPosition: Int
    public let positionWithinSession: Int
    /// Decision 3's permanent removal. Distinct from `isDeleted`: this row is
    /// kept and can come back.
    public let isActive: Bool
    public let prescriptionType: String
    public let containerType: String?
    public let prescribedSets: Int?
    public let prescribedReps: Int?
    public let prescribedLoadKg: Double?
    public let prescribedDurationSeconds: Double?
    public let prescribedRestSeconds: Double?
    public let progressionEnabled: Bool
    public let progressionIncrementKg: Double?
    public let progressionCondition: String?
    public let notes: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }

    /// True when progression is on *and* has both halves of a rule.
    ///
    /// `progressionEnabled` alone is not enough, and the reason is in
    /// `ExerciseProgression`: a rule with an increment but no condition, or a
    /// condition with no increment, cannot say what to suggest, so it must not
    /// read as "progression is on" to anything above this row.
    public var hasCompleteProgressionRule: Bool {
        progressionEnabled && progressionIncrementKg != nil && progressionCondition != nil
    }
}

/// Storage for `programDayExercisePool`.
///
/// **This table is the prescription.** The handoff's key rule: it never changes
/// because of what was logged — only because the user edited it, skipped it for
/// one session, or set `isActive = false`. Nothing in this store writes a pool
/// row from a bout, and no engine below writes one at all; that is what keeps
/// "what I planned" and "what I did" from becoming the same column.
public struct ProgramDayExercisePoolStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    @discardableResult
    public func add(_ draft: PoolItemDraft) throws -> Int64 {
        // Validated in Swift rather than left to the CHECK constraints, so a
        // bad value is a typed error naming it — the same reasoning
        // `PrescribedWorkoutStore.create` states for `containerType`. The
        // constraints stay as the backstop for a write that bypasses this.
        guard PrescriptionKind(rawValue: draft.prescriptionType) != nil else {
            throw ProgramDayExercisePoolStoreError.unknownPrescriptionType(draft.prescriptionType)
        }
        if let containerType = draft.containerType, TrainingContainer(rawValue: containerType) == nil {
            throw ProgramDayExercisePoolStoreError.unknownContainerType(containerType)
        }
        if let condition = draft.progressionCondition, ProgressionCondition(rawValue: condition) == nil {
            throw ProgramDayExercisePoolStoreError.unknownProgressionCondition(condition)
        }
        // A progression rule with only half of itself is not a rule, and
        // `progressionEnabled = 1` on its own would read as one.
        if draft.progressionEnabled, draft.progressionIncrementKg == nil || draft.progressionCondition == nil {
            throw ProgramDayExercisePoolStoreError.incompleteProgressionRule
        }
        guard draft.rotationPosition >= 0, draft.positionWithinSession >= 0 else {
            throw ProgramDayExercisePoolStoreError.negativePosition
        }

        let now = nowText
        try db.run("""
        INSERT INTO programDayExercisePool
            (programDayId, exerciseCatalogId, rotationPosition, positionWithinSession,
             prescriptionType, containerType, prescribedSets, prescribedReps, prescribedLoadKg,
             prescribedDurationSeconds, prescribedRestSeconds,
             progressionEnabled, progressionIncrementKg, progressionCondition, notes,
             createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .integer(draft.programDayId), .integer(draft.exerciseCatalogId),
            .integer(Int64(draft.rotationPosition)), .integer(Int64(draft.positionWithinSession)),
            .text(draft.prescriptionType),
            draft.containerType.map { SQLValue.text($0) } ?? .null,
            draft.prescribedSets.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.prescribedReps.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.prescribedLoadKg.map { SQLValue.real($0) } ?? .null,
            draft.prescribedDurationSeconds.map { SQLValue.real($0) } ?? .null,
            draft.prescribedRestSeconds.map { SQLValue.real($0) } ?? .null,
            .integer(draft.progressionEnabled ? 1 : 0),
            draft.progressionIncrementKg.map { SQLValue.real($0) } ?? .null,
            draft.progressionCondition.map { SQLValue.text($0) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(now), .text(now)
        ])
        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    /// Edits a prescription. Rotation position and slot are **not** editable
    /// here.
    ///
    /// Deliberate, and it is the 2026-10-01 handoff's open question answered by
    /// omission: rotation order is strict-cycle by `rotationPosition`, so there
    /// is no reorder operation to get wrong. `setPositions` moves an item
    /// explicitly when a template is authored, which is authoring; reordering by
    /// dragging is a product decision nobody has made.
    ///
    /// Progression columns are not editable here either — `setProgression` is the
    /// only writer, so "turn progression on" and "give it a rule" cannot drift
    /// apart into two ways of doing one thing.
    @discardableResult
    public func updatePrescription(id: Int64,
                                   prescriptionType: String,
                                   containerType: String?,
                                   prescribedSets: Int?,
                                   prescribedReps: Int?,
                                   prescribedLoadKg: Double?,
                                   prescribedDurationSeconds: Double?,
                                   prescribedRestSeconds: Double?,
                                   notes: String?) throws -> Bool {
        guard PrescriptionKind(rawValue: prescriptionType) != nil else {
            throw ProgramDayExercisePoolStoreError.unknownPrescriptionType(prescriptionType)
        }
        if let containerType = containerType, TrainingContainer(rawValue: containerType) == nil {
            throw ProgramDayExercisePoolStoreError.unknownContainerType(containerType)
        }
        return try db.run("""
        UPDATE programDayExercisePool SET
            prescriptionType = ?, containerType = ?, prescribedSets = ?, prescribedReps = ?,
            prescribedLoadKg = ?, prescribedDurationSeconds = ?, prescribedRestSeconds = ?,
            notes = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [
            .text(prescriptionType),
            containerType.map { SQLValue.text($0) } ?? .null,
            prescribedSets.map { SQLValue.integer(Int64($0)) } ?? .null,
            prescribedReps.map { SQLValue.integer(Int64($0)) } ?? .null,
            prescribedLoadKg.map { SQLValue.real($0) } ?? .null,
            prescribedDurationSeconds.map { SQLValue.real($0) } ?? .null,
            prescribedRestSeconds.map { SQLValue.real($0) } ?? .null,
            notes.map { SQLValue.text($0) } ?? .null,
            .text(nowText), .integer(id)
        ]) > 0
    }

    /// Moves an item within the cycle and/or to another slot.
    ///
    /// The only way `rotationPosition` changes — and it changes **here**, at an
    /// explicit authoring act, never as a side effect of training. A session
    /// cannot move it, a skip cannot move it, and time passing cannot move it.
    @discardableResult
    public func setPositions(id: Int64, rotationPosition: Int, positionWithinSession: Int) throws -> Bool {
        guard rotationPosition >= 0, positionWithinSession >= 0 else {
            throw ProgramDayExercisePoolStoreError.negativePosition
        }
        return try db.run("""
        UPDATE programDayExercisePool
        SET rotationPosition = ?, positionWithinSession = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [.integer(Int64(rotationPosition)), .integer(Int64(positionWithinSession)),
              .text(nowText), .integer(id)]) > 0
    }

    // MARK: - Decision 3: two mechanisms, one prompt

    /// Decision 3's **permanent** removal: `is_active = false`.
    ///
    /// The row is kept. Everything the user configured for it — the
    /// prescription, the progression rule, the rotation position — survives, so
    /// `setActive(id:to: true)` puts it back **where it was in the cycle** rather
    /// than at the end. That is what makes the handoff's "never offered again
    /// until the user manually re-adds it" reversible without the user
    /// re-entering the prescription from memory.
    ///
    /// "Re-add" deliberately means this, not delete-then-insert. An item deleted
    /// and re-inserted would land at a new rotation position and lose its
    /// progression rule, so "remove permanently" and "start again" would be the
    /// same button.
    @discardableResult
    public func setActive(id: Int64, to isActive: Bool) throws -> Bool {
        try db.run("""
        UPDATE programDayExercisePool SET isActive = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [.integer(isActive ? 1 : 0), .text(nowText), .integer(id)]) > 0
    }

    /// Decision 3's **per-session** skip, and it has no implementation.
    ///
    /// Not an oversight — the point of the skip is that it writes *nothing*. A
    /// skip holds its position (Decision 3, "Resolved this session") and is
    /// re-offered next time, so there is no row to write and no state to change.
    /// The only record of the skip is `workoutBout.wasSkippedForSession`, which
    /// is the log side.
    ///
    /// Declared so the asymmetry is a compile-time fact: a caller holding a
    /// `ExerciseAvailability` has exactly one method to reach for on `.permanent`
    /// and this one on `.perSession`, and cannot accidentally call the other.
    public func skipForSessionOnly(_ availability: ExerciseAvailability, item id: Int64) throws {
        switch availability {
        case .permanent: try setActive(id: id, to: false)
        case .perSession: break  // Nothing to write. That is the whole behaviour.
        }
    }

    // MARK: - Decision 4: per-exercise progression

    /// Sets or clears an exercise's progression rule.
    ///
    /// `incrementKg` and `condition` move together, and both are required for a
    /// rule to exist — Decision 4 makes the rule user-defined, so a rule with
    /// half of itself cannot say what it would suggest. Passing `nil, nil` turns
    /// progression off; that is the only way to turn it off, so "off" and
    /// "enabled with a broken rule" cannot both be stored.
    @discardableResult
    public func setProgression(id: Int64, incrementKg: Double?, condition: String?) throws -> Bool {
        if let condition, ProgressionCondition(rawValue: condition) == nil {
            throw ProgramDayExercisePoolStoreError.unknownProgressionCondition(condition)
        }
        if (incrementKg == nil) != (condition == nil) {
            throw ProgramDayExercisePoolStoreError.incompleteProgressionRule
        }
        let enabled = incrementKg != nil ? 1 : 0
        return try db.run("""
        UPDATE programDayExercisePool
        SET progressionEnabled = ?, progressionIncrementKg = ?, progressionCondition = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [.integer(Int64(enabled)),
              incrementKg.map { SQLValue.real($0) } ?? .null,
              condition.map { SQLValue.text($0) } ?? .null,
              .text(nowText), .integer(id)]) > 0
    }

    /// Soft delete — the item leaves the pool entirely, as against
    /// `setActive(id:to: false)` which keeps it. Distinct because a deleted item
    /// loses its progression rule and its rotation position, and a permanently
    /// removed one keeps both.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        try db.run("""
        UPDATE programDayExercisePool SET deletedAt = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)]) > 0
    }

    // MARK: - Read

    public func item(id: Int64) throws -> PoolItemEntry? {
        try db.query("SELECT * FROM programDayExercisePool WHERE id = ?;", [.integer(id)])
            .first.flatMap(Self.entry(from:))
    }

    /// Every live item of a day, active and inactive, in cycle order.
    ///
    /// The authoring view: it has to show the removed ones, because "why is
    /// this exercise not being offered" is answered by seeing it greyed out
    /// rather than by its absence.
    public func items(programDayId: Int64) throws -> [PoolItemEntry] {
        try db.query("""
        SELECT * FROM programDayExercisePool
        WHERE programDayId = ? AND deletedAt IS NULL
        ORDER BY rotationPosition, id;
        """, [.integer(programDayId)]).compactMap(Self.entry(from:))
    }

    /// The rotation read: live, active items of a day, in cycle order.
    ///
    /// `isActive = 1` and not merely `deletedAt IS NULL`, which is Decision 3's
    /// permanent removal and the distinction `Migration049`'s header makes. This
    /// is the one query a generated session is built from.
    public func activeItems(programDayId: Int64) throws -> [PoolItemEntry] {
        try db.query("""
        SELECT * FROM programDayExercisePool
        WHERE programDayId = ? AND isActive = 1 AND deletedAt IS NULL
        ORDER BY rotationPosition, id;
        """, [.integer(programDayId)]).compactMap(Self.entry(from:))
    }

    /// How many exercises a generated session of this day holds.
    ///
    /// The highest slot any item occupies, plus one. It is read from the data
    /// rather than stored as a column because the day is authored by adding
    /// items, and a stored slot count is a second thing that has to be kept true
    /// when one is added. A day with no items has no session shape at all, so
    /// this is zero rather than one.
    public func sessionSlotCount(programDayId: Int64) throws -> Int {
        let rows = try db.query("""
        SELECT MAX(positionWithinSession) AS top FROM programDayExercisePool
        WHERE programDayId = ? AND deletedAt IS NULL;
        """, [.integer(programDayId)])
        guard let top = rows.first?.int("top") else { return 0 }
        return Int(top) + 1
    }

    /// The next free rotation position for a day, so an editor does not have to
    /// ask "what is the highest" itself.
    public func nextRotationPosition(programDayId: Int64) throws -> Int {
        let rows = try db.query("""
        SELECT MAX(rotationPosition) AS top FROM programDayExercisePool
        WHERE programDayId = ? AND deletedAt IS NULL;
        """, [.integer(programDayId)])
        guard let top = rows.first?.int("top") else { return 0 }
        return Int(top) + 1
    }

    /// Live pool items across every day that use one exercise.
    ///
    /// The read both progress graphs and `ExerciseProgression` need — "how has
    /// this movement been loaded" — which starts from the exercise rather than
    /// from a program. Includes inactive items: an exercise removed from a pool
    /// last month still has history, and hiding it would make its graph empty
    /// exactly when the user is wondering why.
    public func items(exerciseCatalogId: Int64) throws -> [PoolItemEntry] {
        try db.query("""
        SELECT * FROM programDayExercisePool
        WHERE exerciseCatalogId = ? AND deletedAt IS NULL
        ORDER BY id;
        """, [.integer(exerciseCatalogId)]).compactMap(Self.entry(from:))
    }

    private static func entry(from row: Row) -> PoolItemEntry? {
        guard let id = row.int("id"),
              let programDayId = row.int("programDayId"),
              let exerciseCatalogId = row.int("exerciseCatalogId"),
              let rotationPosition = row.int("rotationPosition"),
              let positionWithinSession = row.int("positionWithinSession"),
              let prescriptionType = row.string("prescriptionType"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        return PoolItemEntry(
            id: id, programDayId: programDayId, exerciseCatalogId: exerciseCatalogId,
            rotationPosition: Int(rotationPosition), positionWithinSession: Int(positionWithinSession),
            isActive: row.int("isActive") == 1, prescriptionType: prescriptionType,
            containerType: row.string("containerType"),
            prescribedSets: row.int("prescribedSets").map(Int.init),
            prescribedReps: row.int("prescribedReps").map(Int.init),
            prescribedLoadKg: row.double("prescribedLoadKg"),
            prescribedDurationSeconds: row.double("prescribedDurationSeconds"),
            prescribedRestSeconds: row.double("prescribedRestSeconds"),
            progressionEnabled: row.int("progressionEnabled") == 1,
            progressionIncrementKg: row.double("progressionIncrementKg"),
            progressionCondition: row.string("progressionCondition"),
            notes: row.string("notes"), deletedAt: row.string("deletedAt"),
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

public enum ProgramDayExercisePoolStoreError: Error, Sendable, Equatable {
    case unknownPrescriptionType(String)
    case unknownContainerType(String)
    case unknownProgressionCondition(String)
    /// `progressionEnabled` without both halves of the rule. Decision 4's rule is
    /// user-defined, so a rule missing its increment or its condition cannot say
    /// what it would suggest, and storing it as enabled would read as though it
    /// could.
    case incompleteProgressionRule
    case negativePosition
}
