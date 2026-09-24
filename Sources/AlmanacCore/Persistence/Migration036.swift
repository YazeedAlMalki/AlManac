import Foundation

/// Migration 036 — `workoutSession.source` and `workoutSession.healthKitUUID`.
///
/// `workoutSession` had no provenance columns at all, so there was nowhere to
/// do an idempotent upsert of a HealthKit workout: every sync would have
/// inserted another copy of the same session. `docs/features/training.md` §6
/// step 1(b) named this as the blocker, and it is the same shape the other
/// bridges already have — `vitals_record` and `body_composition_measurement`
/// both carry `source` + a `healthKitUUID` unique column.
///
/// `healthKitUUID` is nullable and uniquely indexed only where present, so
/// manually logged sessions (all of which have none) are unaffected and may
/// number as many per day as they always could. `source` is likewise nullable
/// so every existing row stays valid; the bridge writes `'healthkit'` and
/// nothing else does.
public enum Migration036_WorkoutSessionSource: Migration {
    public static let version = 36
    public static let name = "workout_session_source"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE workoutSession ADD COLUMN source TEXT;")
        try db.execute("ALTER TABLE workoutSession ADD COLUMN healthKitUUID TEXT;")
        // Partial index: SQLite treats NULLs as distinct in a unique index
        // anyway, but stating the predicate keeps the intent readable and lets
        // the bridge's `ON CONFLICT ... WHERE healthKitUUID IS NOT NULL` target
        // this index directly.
        try db.execute("""
        CREATE UNIQUE INDEX idx_workout_session_healthkit
        ON workoutSession(healthKitUUID) WHERE healthKitUUID IS NOT NULL;
        """)
    }
}
