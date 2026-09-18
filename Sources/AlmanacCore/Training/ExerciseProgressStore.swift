import Foundation

/// One historical data point for an exercise: the sets/reps/load actually
/// logged in one bout, with the session it belongs to.
public struct ExerciseProgressPoint: Sendable, Hashable {
    public let sessionId: Int64
    public let date: String
    public let boutId: Int64
    public let actualSets: Int?
    public let actualReps: Int?
    public let actualLoadKg: Double?
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
        try db.query("""
        SELECT b.id as boutId, b.sessionId as sessionId, s.date as date,
               b.actualSets as actualSets, b.actualReps as actualReps, b.actualLoadKg as actualLoadKg
        FROM workoutBout b
        JOIN workoutSession s ON s.id = b.sessionId
        WHERE b.exerciseCatalogId = ? AND b.deletedAt IS NULL AND s.deletedAt IS NULL
        ORDER BY s.date, b.id;
        """, [.integer(exerciseCatalogId)]).compactMap(Self.point(from:))
    }

    private static func point(from row: Row) -> ExerciseProgressPoint? {
        guard let boutId = row.int("boutId"),
              let sessionId = row.int("sessionId"),
              let date = row.string("date") else { return nil }
        return ExerciseProgressPoint(
            sessionId: sessionId, date: date, boutId: boutId,
            actualSets: row.int("actualSets").map(Int.init),
            actualReps: row.int("actualReps").map(Int.init),
            actualLoadKg: row.double("actualLoadKg")
        )
    }
}
