import Foundation

/// Migration 031 — `planned_workout`, the minimal "a workout is expected to
/// start at this instant" concept §14.2's Contextual Pre-workout Snack
/// Suggestion needs ("gap between last logged meal and planned workout
/// start") and that nothing in this repo represented before now —
/// `prescribedWorkout` is a reusable template with no time attached, and
/// `workoutSession`/`workoutBout` only record sessions that already
/// happened (both flagged, not built around, by
/// `NotificationTriggerTimeComputer`'s own doc comment before this
/// migration).
///
/// Deliberately thin: a scheduled instant plus an optional link back to
/// which template it's for, nothing else. No status/completion tracking,
/// no recurrence — this repo's notification trigger only ever needs "the
/// next planned workout after now", not a full workout-planning feature;
/// building more than that here would be guessing at a feature this
/// session was never asked for.
///
/// Named and cased like the rest of the Readiness/Sleep/Notifications
/// domain (snake_case table, camelCase columns) rather than Training's
/// camelCase tables (`prescribedWorkout`, `workoutBout`) — this table isn't
/// one of §5's original schema tables extending Training, it's new
/// notification-scheduling support, so it follows the newer convention
/// Migration014 onward uses.
public enum Migration031_PlannedWorkout: Migration {
    public static let version = 31
    public static let name = "planned_workout"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE planned_workout (
            id                  INTEGER PRIMARY KEY,
            scheduledAt         TEXT NOT NULL,
            prescribedWorkoutId INTEGER REFERENCES prescribedWorkout(id),
            notes               TEXT,
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_planned_workout_scheduled_at ON planned_workout(scheduledAt);")
    }
}
