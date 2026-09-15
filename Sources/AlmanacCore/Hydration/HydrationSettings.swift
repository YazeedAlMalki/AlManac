import Foundation

/// User preferences for hydration tracking features. Single row
/// (`hydration_settings`, `id = 'local'`) — see `Migration013`'s doc comment
/// for why this codebase has no per-user settings table.
public struct HydrationSettings: Sendable, Hashable {
    public let isCalorieTrackingEnabled: Bool
    public let isDoubleTrackWarningEnabled: Bool
    public let remindersEnabled: Bool
    public let reminderIntervalMinutes: Int
    public let reminderStartHour: Int
    public let reminderEndHour: Int
    public let dailyGoalMilliliters: Double?
    public let trackSodium: Bool
    public let trackSugar: Bool
    public let updatedAt: Date

    public init(
        isCalorieTrackingEnabled: Bool = false,  // Default OFF to prevent double-tracking
        isDoubleTrackWarningEnabled: Bool = true,
        remindersEnabled: Bool = true,
        reminderIntervalMinutes: Int = 60,
        reminderStartHour: Int = 7,
        reminderEndHour: Int = 22,
        dailyGoalMilliliters: Double? = nil,
        trackSodium: Bool = true,
        trackSugar: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.isCalorieTrackingEnabled = isCalorieTrackingEnabled
        self.isDoubleTrackWarningEnabled = isDoubleTrackWarningEnabled
        self.remindersEnabled = remindersEnabled
        self.reminderIntervalMinutes = reminderIntervalMinutes
        self.reminderStartHour = reminderStartHour
        self.reminderEndHour = reminderEndHour
        self.dailyGoalMilliliters = dailyGoalMilliliters
        self.trackSodium = trackSodium
        self.trackSugar = trackSugar
        self.updatedAt = updatedAt
    }

    /// The reminder schedule these settings describe, as a value the
    /// calculator/reminder service can consume without touching storage.
    public var reminder: HydrationReminder {
        HydrationReminder(intervalMinutes: reminderIntervalMinutes, startHour: reminderStartHour,
                           endHour: reminderEndHour, isEnabled: remindersEnabled)
    }
}

/// Persists the single `hydration_settings` row.
public struct HydrationSettingsStore: Sendable {
    private let db: Database
    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    public init(db: Database) {
        self.db = db
    }

    public func save(_ settings: HydrationSettings) throws {
        try db.run("""
        INSERT INTO hydration_settings (
            id, calorie_tracking_enabled, double_track_warning_enabled,
            reminders_enabled, reminder_interval_minutes, reminder_start_hour, reminder_end_hour,
            daily_goal_ml, track_sodium, track_sugar, updated_at
        ) VALUES ('local', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            calorie_tracking_enabled     = excluded.calorie_tracking_enabled,
            double_track_warning_enabled = excluded.double_track_warning_enabled,
            reminders_enabled            = excluded.reminders_enabled,
            reminder_interval_minutes    = excluded.reminder_interval_minutes,
            reminder_start_hour          = excluded.reminder_start_hour,
            reminder_end_hour            = excluded.reminder_end_hour,
            daily_goal_ml                = excluded.daily_goal_ml,
            track_sodium                 = excluded.track_sodium,
            track_sugar                  = excluded.track_sugar,
            updated_at                   = excluded.updated_at;
        """, [
            .integer(settings.isCalorieTrackingEnabled ? 1 : 0),
            .integer(settings.isDoubleTrackWarningEnabled ? 1 : 0),
            .integer(settings.remindersEnabled ? 1 : 0),
            .integer(Int64(settings.reminderIntervalMinutes)),
            .integer(Int64(settings.reminderStartHour)),
            .integer(Int64(settings.reminderEndHour)),
            settings.dailyGoalMilliliters.map { SQLValue.real($0) } ?? .null,
            .integer(settings.trackSodium ? 1 : 0),
            .integer(settings.trackSugar ? 1 : 0),
            .text(iso.string(from: settings.updatedAt))
        ])
    }

    public func fetch() throws -> HydrationSettings? {
        guard let row = try db.query("SELECT * FROM hydration_settings WHERE id = 'local';").first
        else { return nil }
        return parse(row)
    }

    public func getOrCreate() throws -> HydrationSettings {
        if let existing = try fetch() { return existing }
        let defaults = HydrationSettings()
        try save(defaults)
        return defaults
    }

    private func parse(_ row: Row) -> HydrationSettings? {
        guard let calorieTracking = row.int("calorie_tracking_enabled"),
              let doubleTrackWarning = row.int("double_track_warning_enabled"),
              let reminders = row.int("reminders_enabled"),
              let interval = row.int("reminder_interval_minutes"),
              let startHour = row.int("reminder_start_hour"),
              let endHour = row.int("reminder_end_hour"),
              let trackSodium = row.int("track_sodium"),
              let trackSugar = row.int("track_sugar"),
              let updatedAtText = row.string("updated_at"),
              let updatedAt = iso.date(from: updatedAtText)
        else { return nil }

        return HydrationSettings(
            isCalorieTrackingEnabled: calorieTracking != 0,
            isDoubleTrackWarningEnabled: doubleTrackWarning != 0,
            remindersEnabled: reminders != 0,
            reminderIntervalMinutes: Int(interval),
            reminderStartHour: Int(startHour),
            reminderEndHour: Int(endHour),
            dailyGoalMilliliters: row.double("daily_goal_ml"),
            trackSodium: trackSodium != 0,
            trackSugar: trackSugar != 0,
            updatedAt: updatedAt
        )
    }
}

/// Persists the single `hydration_profile` row.
public struct HydrationProfileStore: Sendable {
    private let db: Database
    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    public init(db: Database) {
        self.db = db
    }

    public func save(_ profile: HydrationProfile) throws {
        try db.run("""
        INSERT INTO hydration_profile (id, baseline_intake_ml, body_weight_kg, activity_level, updated_at)
        VALUES ('local', ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            baseline_intake_ml = excluded.baseline_intake_ml,
            body_weight_kg     = excluded.body_weight_kg,
            activity_level     = excluded.activity_level,
            updated_at         = excluded.updated_at;
        """, [
            .real(profile.baselineIntakeMilliliters),
            profile.bodyWeightKg.map { SQLValue.real($0) } ?? .null,
            .text(profile.activityLevel.rawValue),
            .text(iso.string(from: profile.updatedAt))
        ])
    }

    public func fetch() throws -> HydrationProfile? {
        guard let row = try db.query("SELECT * FROM hydration_profile WHERE id = 'local';").first
        else { return nil }
        guard let baseline = row.double("baseline_intake_ml"),
              let activityRaw = row.string("activity_level"),
              let activity = ActivityLevel(rawValue: activityRaw),
              let updatedAtText = row.string("updated_at"),
              let updatedAt = iso.date(from: updatedAtText)
        else { return nil }
        return HydrationProfile(baselineIntakeMilliliters: baseline, bodyWeightKg: row.double("body_weight_kg"),
                                 activityLevel: activity, updatedAt: updatedAt)
    }

    public func getOrCreate() throws -> HydrationProfile {
        if let existing = try fetch() { return existing }
        let defaults = HydrationProfile()
        try save(defaults)
        return defaults
    }
}
