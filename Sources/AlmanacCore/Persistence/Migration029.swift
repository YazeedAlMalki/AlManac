import Foundation

/// Migration 029 — `meal_reminder_setting`, storage for §14.2's Meal Logging
/// Reminder ("Default: OFF. User sets preferred times.").
///
/// One row per `NutritionMealType` case (breakfast/lunch/dinner/snack) — the
/// plural "times" in the spec's own wording is read as one time per meal
/// type, not an arbitrary user-defined list, since every other place this
/// repo already partitions a day's eating is by `NutritionMealType`,
/// `NutritionLogStore`'s own enum. `reminderMinuteOfDay` stores a wall-clock
/// time of day as minutes since local midnight (0-1439) rather than a
/// `Date` — this is a *repeating daily* reminder ("preferred times", not
/// "a reminder on this date"), so there is no instant to store; resolving
/// it to a real `Date` for a given day is `NotificationTriggerAssembler`'s
/// job, same division as every other trigger type in that file.
///
/// Self-healing like `sleep_tracking_settings` (Migration025) and
/// `prayer_settings`: nothing seeds rows here.
/// `MealReminderSettingsStore.setReminder` upserts on first write for a
/// given meal type, via the unique index below as `ON CONFLICT`'s target.
public enum Migration029_MealReminderSetting: Migration {
    public static let version = 29
    public static let name = "meal_reminder_setting"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE meal_reminder_setting (
            id                   INTEGER PRIMARY KEY,
            mealType             TEXT NOT NULL,
            enabled              INTEGER NOT NULL DEFAULT 0,
            reminderMinuteOfDay  INTEGER,
            updatedAt            TEXT NOT NULL
        );
        """)
        try db.execute("CREATE UNIQUE INDEX idx_meal_reminder_setting_mealtype ON meal_reminder_setting(mealType);")
    }
}
