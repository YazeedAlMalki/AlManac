import Foundation

/// Migration 026 — `workoutSession.sessionType` (Ticket 4, 2026-09-18 handoff).
///
/// The user-selected sport/activity a session is ("CrossFit", "football",
/// "running", "weightlifting", ...) — orthogonal to `workoutBout.prescriptionType`/
/// `.containerType` (Migration016), which describe *how a bout of work is
/// structured*, not *what sport it belongs to*. Deliberately a plain nullable
/// `TEXT` with no `CHECK` constraint: unlike the twelve prescription types
/// (`docs/features/training.md` §2, closed and enumerable by design), the set
/// of sports/activities a session can be is open-ended — the ticket's own
/// examples end in "etc." A future picklist can curate this at the UI layer
/// without the schema needing to know the full list up front.
public enum Migration026_WorkoutSessionType: Migration {
    public static let version = 26
    public static let name = "workout_session_type"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE workoutSession ADD COLUMN sessionType TEXT;")
    }
}
