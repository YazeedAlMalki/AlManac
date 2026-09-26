import Foundation

/// Preserves the hydration goal that was in force for each logical day.
public enum Migration040_HydrationGoalSnapshots: Migration {
    public static let version = 40
    public static let name = "hydration_goal_snapshots"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE hydration_goal_snapshot (
            effective_day TEXT PRIMARY KEY,
            daily_goal_ml REAL NOT NULL CHECK (daily_goal_ml > 0),
            updated_at    TEXT NOT NULL
        );
        """)
    }
}
