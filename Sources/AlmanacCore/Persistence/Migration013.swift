import Foundation

/// Migration 013 — drinks, calorie/sodium/sugar snapshots on the log, settings, profile.
///
/// Appended; 001-012 are untouched.
///
/// **Where this diverges from `claude/app-hydration-tracking-mpwsyv`, and why.**
/// That branch modelled calories/sodium/sugar as a separate
/// `hydration_calorie_entry` table joined back to the log by id, and kept a
/// mutable `double_track_warning` flag on each row. Here the same facts are
/// columns directly on `hydration_log`: nullable, populated only when a drink
/// was actually attached to the entry, and never requiring a second insert or
/// a join to read them back. Double-tracking is recomputed at read time from
/// existing rows (see `HydrationLoggingService.possibleDoubleTrack`) rather
/// than persisted and mutated — a derived fact, droppable and rebuildable,
/// same rule `docs/architecture/health-data-foundation.md` §5 already applies
/// to every other derived summary in this codebase.
///
/// **`value_qualifier` is mandatory whenever a drink is attached**, not
/// optional metadata. The built-in drink catalog (`DrinkCatalog.swift`) has
/// no cited source for its calorie/sodium/sugar figures — unlike every
/// USDA/CIQUAL/CoFID/AFCD value in the nutrition module, which carries
/// `source_value` and a licence group. Rather than let that distinction get
/// lost, every `hydration_log` row that carries nutrition figures snapshots
/// which kind they are: `catalog_unsourced_estimate` or `user_entered`. Never
/// `measured` — nothing in this table is a laboratory or publisher figure.
///
/// **Single user, on purpose.** The branch's `hydration_settings`,
/// `hydration_reminder` and `hydration_custom_drink` tables all carried a
/// `user_id` column and multi-user CRUD (a `migrate(from:to:)` for "merging
/// accounts"). `Native/README.md` already states this application has no
/// account boundary — "the existing local personal database model, not an
/// authenticated multi-user service." `hydration_settings` and
/// `hydration_profile` are therefore singleton tables (`id` fixed to
/// `'local'`, enforced by a CHECK), and `hydration_drink` holds only
/// user-authored custom drinks with no owner column at all.
///
/// **No separate reminder table.** The branch persisted `HydrationReminder`
/// as its own row, supporting several configured reminders per user. A
/// single-user app has exactly one active reminder schedule; it is modelled
/// as columns on `hydration_settings`, and a `HydrationReminder` value is
/// constructed from those columns on demand (`HydrationReminderService`), not
/// stored as a separate mutable entity.
public enum Migration013_HydrationFeatures: Migration {
    public static let version = 13
    public static let name = "hydration_drinks_settings_profile"

    public static func up(_ db: Database) throws {
        // Nullable snapshot columns. NULL on every pre-existing row and on
        // any future plain water/manual-amount log that never had a drink
        // attached — a hydration entry with no drink is still a complete,
        // valid entry (Migration012 already established that an entry needs
        // nothing but an amount and a time).
        try db.execute("ALTER TABLE hydration_log ADD COLUMN drink_id TEXT;")
        try db.execute("ALTER TABLE hydration_log ADD COLUMN drink_name TEXT;")
        try db.execute("ALTER TABLE hydration_log ADD COLUMN calories_kcal REAL;")
        try db.execute("ALTER TABLE hydration_log ADD COLUMN sodium_mg REAL;")
        try db.execute("ALTER TABLE hydration_log ADD COLUMN sugar_g REAL;")
        try db.execute("ALTER TABLE hydration_log ADD COLUMN value_qualifier TEXT;")

        // User-authored custom drinks only. The built-in catalog lives in
        // Swift (`DrinkCatalog.swift`), not here — it ships with the app and
        // has no per-installation state.
        try db.execute("""
        CREATE TABLE hydration_drink (
            id              TEXT PRIMARY KEY,
            name            TEXT NOT NULL,
            liquid_type     TEXT NOT NULL,
            volume_ml       REAL NOT NULL CHECK (volume_ml > 0),
            calories_kcal   REAL NOT NULL CHECK (calories_kcal >= 0),
            sodium_mg       REAL NOT NULL CHECK (sodium_mg >= 0),
            sugar_g         REAL,
            created_at      TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE hydration_settings (
            id                              TEXT PRIMARY KEY CHECK (id = 'local'),
            calorie_tracking_enabled        INTEGER NOT NULL,
            double_track_warning_enabled    INTEGER NOT NULL,
            reminders_enabled               INTEGER NOT NULL,
            reminder_interval_minutes       INTEGER NOT NULL,
            reminder_start_hour             INTEGER NOT NULL,
            reminder_end_hour               INTEGER NOT NULL,
            daily_goal_ml                   REAL,
            track_sodium                    INTEGER NOT NULL,
            track_sugar                     INTEGER NOT NULL,
            updated_at                      TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE hydration_profile (
            id                       TEXT PRIMARY KEY CHECK (id = 'local'),
            baseline_intake_ml       REAL NOT NULL,
            body_weight_kg           REAL,
            activity_level           TEXT NOT NULL,
            updated_at               TEXT NOT NULL
        );
        """)
    }
}
