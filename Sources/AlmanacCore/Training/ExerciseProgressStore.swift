import Foundation

/// One historical data point for an exercise: the sets/reps/load actually
/// logged in one bout, with the session it belongs to.
///
/// `prescribedReps` rides along because "did the user do all the reps" cannot be
/// answered from the actuals alone — a set of 6 against a prescription of 6 and a
/// set of 6 against a prescription of 10 are the same actual number and opposite
/// results, and `ExerciseProgression` is the one thing that has to tell them
/// apart. Same row, so it costs no extra query.
public struct ExerciseProgressPoint: Sendable, Hashable {
    public let sessionId: Int64
    public let date: String
    public let boutId: Int64
    public let actualSets: Int?
    public let actualReps: Int?
    public let actualLoadKg: Double?
    public let prescribedReps: Int?
}

/// The point of collecting per-exercise sets/reps/load (Ticket 4): making it
/// queryable across sessions, not just stored. `WorkloadComputer` aggregates
/// a single session's bouts into one summary; this instead follows one
/// exercise's `actual*` fields — what was actually measured, never the
/// prescribed plan (`docs/features/training.md` §2) — across every session
/// it appears in, oldest first, so a trend/progress view has something to draw.
public struct ExerciseProgressStore: @unchecked Sendable {
    let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// An exercise's logged history, oldest session first. Only live
    /// (not soft-deleted) bouts and sessions are included.
    public func history(exerciseCatalogId: Int64) throws -> [ExerciseProgressPoint] {
        try history(exerciseCatalogIds: [exerciseCatalogId])[exerciseCatalogId] ?? []
    }

    /// Several exercises' histories in **one** query, each oldest session first.
    ///
    /// The batch read a generated session needs. A day's sheet asks about three
    /// exercises at once, and three `history(exerciseCatalogId:)` calls in a `for`
    /// is the per-item query the handoff §8 rule is written about — it reads as
    /// one query per exercise and costs one per exercise every time the sheet is
    /// drawn. `suggestions(for:)` is the caller that needed this.
    ///
    /// Exercises with no history are absent from the dictionary rather than mapped
    /// to an empty array, so "not performed" and "performed with nothing logged" do
    /// not have to be told apart by a caller.
    public func history(exerciseCatalogIds: [Int64]) throws -> [Int64: [ExerciseProgressPoint]] {
        guard !exerciseCatalogIds.isEmpty else { return [:] }
        let unique = Array(Set(exerciseCatalogIds))
        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ", ")
        let rows = try db.query("""
        SELECT b.id as boutId, b.sessionId as sessionId, s.date as date,
               b.exerciseCatalogId as exerciseCatalogId,
               b.actualSets as actualSets, b.actualReps as actualReps,
               b.actualLoadKg as actualLoadKg, b.prescribedReps as prescribedReps
        FROM workoutBout b
        JOIN workoutSession s ON s.id = b.sessionId
        WHERE b.exerciseCatalogId IN (\(placeholders))
          AND b.deletedAt IS NULL AND s.deletedAt IS NULL
        ORDER BY s.date, b.id;
        """, unique.map { SQLValue.integer($0) })

        var history: [Int64: [ExerciseProgressPoint]] = [:]
        for row in rows {
            guard let point = Self.point(from: row),
                  let exerciseCatalogId = row.int("exerciseCatalogId") else { continue }
            history[exerciseCatalogId, default: []].append(point)
        }
        return history
    }

    private static func point(from row: Row) -> ExerciseProgressPoint? {
        guard let boutId = row.int("boutId"),
              let sessionId = row.int("sessionId"),
              let date = row.string("date") else { return nil }
        return ExerciseProgressPoint(
            sessionId: sessionId, date: date, boutId: boutId,
            actualSets: row.int("actualSets").map(Int.init),
            actualReps: row.int("actualReps").map(Int.init),
            actualLoadKg: row.double("actualLoadKg"),
            prescribedReps: row.int("prescribedReps").map(Int.init)
        )
    }
}
