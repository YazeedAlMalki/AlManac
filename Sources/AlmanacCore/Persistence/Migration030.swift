import Foundation

/// Migration 030 — reminder columns on `supplement_plan`, storage for
/// §14.2's Supplement Reminders ("Default: OFF per supplement. User sets
/// time per supplement plan. One notification per active supplement at its
/// configured time.").
///
/// Added directly to `supplement_plan` (Migration018) rather than a new
/// table, unlike meal reminders: the spec ties this reminder to a specific
/// supplement plan one-to-one ("per supplement", "per supplement plan"),
/// so it is a property of the plan itself, not a separate schedule that
/// outlives or is shared across plans. `reminderMinuteOfDay` is minutes
/// since local midnight, same representation and same reason as
/// `meal_reminder_setting.reminderMinuteOfDay` (Migration029) — a repeating
/// daily time, not an instant.
public enum Migration030_SupplementPlanReminderColumns: Migration {
    public static let version = 30
    public static let name = "supplement_plan_reminder_columns"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE supplement_plan ADD COLUMN reminderEnabled INTEGER NOT NULL DEFAULT 0;")
        try db.execute("ALTER TABLE supplement_plan ADD COLUMN reminderMinuteOfDay INTEGER;")
    }
}
