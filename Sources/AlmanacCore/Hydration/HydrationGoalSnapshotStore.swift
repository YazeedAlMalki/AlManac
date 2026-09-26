import Foundation

/// The hydration goal in force for one Almanac logical day.
///
/// This is deliberately hydration-specific. The broader §6.10 target
/// snapshot model is not built yet, but ring history must not change merely
/// because the user edits today's goal.
public struct HydrationGoalSnapshot: Sendable, Hashable {
    public let effectiveDay: LogicalDay
    public let dailyGoal: Milliliters
    public let updatedAt: Date

    public init(effectiveDay: LogicalDay, dailyGoal: Milliliters, updatedAt: Date) {
        self.effectiveDay = effectiveDay
        self.dailyGoal = dailyGoal
        self.updatedAt = updatedAt
    }
}

public struct HydrationGoalSnapshotStore: Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func save(_ dailyGoal: Milliliters,
                     effectiveOn day: LogicalDay,
                     at date: Date = Date()) throws {
        try db.run("""
        INSERT INTO hydration_goal_snapshot (effective_day, daily_goal_ml, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(effective_day) DO UPDATE SET
            daily_goal_ml = excluded.daily_goal_ml,
            updated_at = excluded.updated_at;
        """, [
            .text(day.value),
            .real(dailyGoal.value),
            .text(ISO8601DateFormatter().string(from: date))
        ])
    }

    public func snapshots(from start: LogicalDay, to end: LogicalDay) throws -> [HydrationGoalSnapshot] {
        try db.query("""
        SELECT effective_day, daily_goal_ml, updated_at
        FROM hydration_goal_snapshot
        WHERE effective_day >= ? AND effective_day < ?
        ORDER BY effective_day;
        """, [.text(start.value), .text(end.value)]).compactMap(Self.snapshot(from:))
    }

    public func goal(on day: LogicalDay, fallback: Milliliters) throws -> Milliliters {
        guard let row = try db.query("""
        SELECT daily_goal_ml FROM hydration_goal_snapshot WHERE effective_day = ?;
        """, [.text(day.value)]).first,
              let value = row.double("daily_goal_ml") else { return fallback }
        return Milliliters(value)
    }

    private static func snapshot(from row: Row) -> HydrationGoalSnapshot? {
        guard let effectiveDay = row.string("effective_day"),
              let value = row.double("daily_goal_ml"),
              let updatedText = row.string("updated_at"),
              let updatedAt = ISO8601DateFormatter().date(from: updatedText)
        else { return nil }
        return HydrationGoalSnapshot(
            effectiveDay: LogicalDay(effectiveDay),
            dailyGoal: Milliliters(value),
            updatedAt: updatedAt
        )
    }
}
