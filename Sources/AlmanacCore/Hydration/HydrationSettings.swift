import Foundation

/// User preferences for hydration tracking features
public struct HydrationSettings: Sendable, Hashable {
    public let userId: String
    public let isCalorieTrackingEnabled: Bool
    public let isDoubleTrackWarningEnabled: Bool
    public let autoLogDrinksFromHealth: Bool
    public let showHydrationReminders: Bool
    public let preferredReminderInterval: Int  // Minutes
    public let dailyGoalMilliliters: Double?
    public let trackSodium: Bool
    public let trackSugar: Bool
    public let updatedAt: Date

    public init(
        userId: String,
        isCalorieTrackingEnabled: Bool = false,  // Default OFF to prevent double-tracking
        isDoubleTrackWarningEnabled: Bool = true,
        autoLogDrinksFromHealth: Bool = false,
        showHydrationReminders: Bool = true,
        preferredReminderInterval: Int = 60,
        dailyGoalMilliliters: Double? = nil,
        trackSodium: Bool = true,
        trackSugar: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.isCalorieTrackingEnabled = isCalorieTrackingEnabled
        self.isDoubleTrackWarningEnabled = isDoubleTrackWarningEnabled
        self.autoLogDrinksFromHealth = autoLogDrinksFromHealth
        self.showHydrationReminders = showHydrationReminders
        self.preferredReminderInterval = preferredReminderInterval
        self.dailyGoalMilliliters = dailyGoalMilliliters
        self.trackSodium = trackSodium
        self.trackSugar = trackSugar
        self.updatedAt = updatedAt
    }
}

/// Manages hydration settings persistence
public final class HydrationSettingsStore: Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    /// Save or update settings
    public func save(_ settings: HydrationSettings) throws {
        try db.execute("""
        INSERT OR REPLACE INTO hydration_settings (
            user_id, calorie_tracking_enabled, double_track_warning_enabled,
            auto_log_from_health, reminders_enabled, reminder_interval_minutes,
            daily_goal_ml, track_sodium, track_sugar, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            settings.userId,
            settings.isCalorieTrackingEnabled ? 1 : 0,
            settings.isDoubleTrackWarningEnabled ? 1 : 0,
            settings.autoLogDrinksFromHealth ? 1 : 0,
            settings.showHydrationReminders ? 1 : 0,
            settings.preferredReminderInterval,
            settings.dailyGoalMilliliters as Any,
            settings.trackSodium ? 1 : 0,
            settings.trackSugar ? 1 : 0,
            ISO8601DateFormatter().string(from: settings.updatedAt)
        ])
    }

    /// Fetch settings for a user
    public func fetch(for userId: String) throws -> HydrationSettings? {
        let rows = try db.query("""
        SELECT * FROM hydration_settings WHERE user_id = ?
        """, [userId])

        guard let row = rows.first else {
            return nil
        }

        return parseSettings(from: row, userId: userId)
    }

    /// Get or create default settings
    public func getOrCreate(for userId: String) throws -> HydrationSettings {
        if let existing = try fetch(for: userId) {
            return existing
        }

        let defaults = HydrationSettings(userId: userId)
        try save(defaults)
        return defaults
    }

    /// Update a single setting
    public func updateSetting(
        userId: String,
        calorieTrackingEnabled: Bool? = nil,
        doubleTrackWarningEnabled: Bool? = nil,
        autoLogDrinksFromHealth: Bool? = nil,
        showReminders: Bool? = nil,
        reminderInterval: Int? = nil,
        dailyGoal: Double? = nil,
        trackSodium: Bool? = nil,
        trackSugar: Bool? = nil
    ) throws {
        let current = try getOrCreate(for: userId)

        let updated = HydrationSettings(
            userId: userId,
            isCalorieTrackingEnabled: calorieTrackingEnabled ?? current.isCalorieTrackingEnabled,
            isDoubleTrackWarningEnabled: doubleTrackWarningEnabled ?? current.isDoubleTrackWarningEnabled,
            autoLogDrinksFromHealth: autoLogDrinksFromHealth ?? current.autoLogDrinksFromHealth,
            showHydrationReminders: showReminders ?? current.showHydrationReminders,
            preferredReminderInterval: reminderInterval ?? current.preferredReminderInterval,
            dailyGoalMilliliters: dailyGoal ?? current.dailyGoalMilliliters,
            trackSodium: trackSodium ?? current.trackSodium,
            trackSugar: trackSugar ?? current.trackSugar,
            updatedAt: Date()
        )

        try save(updated)
    }

    /// Toggle calorie tracking on/off
    /// - Parameter enabled: Whether to enable calorie tracking
    /// - Returns: Updated settings
    public func setCalorieTracking(for userId: String, enabled: Bool) throws -> HydrationSettings {
        try updateSetting(userId: userId, calorieTrackingEnabled: enabled)
        return try getOrCreate(for: userId)
    }

    /// Toggle double-tracking warnings
    public func setDoubleTrackWarning(for userId: String, enabled: Bool) throws -> HydrationSettings {
        try updateSetting(userId: userId, doubleTrackWarningEnabled: enabled)
        return try getOrCreate(for: userId)
    }

    /// Migrate settings from an old user (when merging accounts, etc.)
    public func migrate(from oldUserId: String, to newUserId: String) throws {
        guard let oldSettings = try fetch(for: oldUserId) else {
            return
        }

        let newSettings = HydrationSettings(
            userId: newUserId,
            isCalorieTrackingEnabled: oldSettings.isCalorieTrackingEnabled,
            isDoubleTrackWarningEnabled: oldSettings.isDoubleTrackWarningEnabled,
            autoLogDrinksFromHealth: oldSettings.autoLogDrinksFromHealth,
            showHydrationReminders: oldSettings.showHydrationReminders,
            preferredReminderInterval: oldSettings.preferredReminderInterval,
            dailyGoalMilliliters: oldSettings.dailyGoalMilliliters,
            trackSodium: oldSettings.trackSodium,
            trackSugar: oldSettings.trackSugar,
            updatedAt: Date()
        )

        try save(newSettings)
    }

    // MARK: - Private Helpers

    private func parseSettings(from row: [String: Any], userId: String) -> HydrationSettings? {
        guard let calorieTrackingInt = row["calorie_tracking_enabled"] as? Int,
              let doubleTrackWarningInt = row["double_track_warning_enabled"] as? Int,
              let autoLogInt = row["auto_log_from_health"] as? Int,
              let remindersInt = row["reminders_enabled"] as? Int,
              let reminderInterval = row["reminder_interval_minutes"] as? Int,
              let trackSodiumInt = row["track_sodium"] as? Int,
              let trackSugarInt = row["track_sugar"] as? Int,
              let updatedAtStr = row["updated_at"] as? String,
              let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr)
        else { return nil }

        return HydrationSettings(
            userId: userId,
            isCalorieTrackingEnabled: calorieTrackingInt != 0,
            isDoubleTrackWarningEnabled: doubleTrackWarningInt != 0,
            autoLogDrinksFromHealth: autoLogInt != 0,
            showHydrationReminders: remindersInt != 0,
            preferredReminderInterval: reminderInterval,
            dailyGoalMilliliters: row["daily_goal_ml"] as? Double,
            trackSodium: trackSodiumInt != 0,
            trackSugar: trackSugarInt != 0,
            updatedAt: updatedAt
        )
    }
}

/// Settings presets for common use cases
public enum HydrationSettingsPreset {
    case minimal  // Hydration only, no extra tracking
    case standard  // Hydration + reminders
    case comprehensive  // Everything enabled with warnings
    case calorieCounter  // Focused on calorie tracking
    case athlete  // High hydration goals with exercise focus

    public func toSettings(userId: String) -> HydrationSettings {
        switch self {
        case .minimal:
            return HydrationSettings(
                userId: userId,
                isCalorieTrackingEnabled: false,
                isDoubleTrackWarningEnabled: false,
                autoLogDrinksFromHealth: false,
                showHydrationReminders: false,
                trackSodium: false,
                trackSugar: false
            )

        case .standard:
            return HydrationSettings(
                userId: userId,
                isCalorieTrackingEnabled: false,
                isDoubleTrackWarningEnabled: true,
                autoLogDrinksFromHealth: false,
                showHydrationReminders: true,
                preferredReminderInterval: 60,
                trackSodium: true,
                trackSugar: false
            )

        case .comprehensive:
            return HydrationSettings(
                userId: userId,
                isCalorieTrackingEnabled: true,
                isDoubleTrackWarningEnabled: true,
                autoLogDrinksFromHealth: true,
                showHydrationReminders: true,
                preferredReminderInterval: 45,
                trackSodium: true,
                trackSugar: true
            )

        case .calorieCounter:
            return HydrationSettings(
                userId: userId,
                isCalorieTrackingEnabled: true,
                isDoubleTrackWarningEnabled: true,
                autoLogDrinksFromHealth: false,
                showHydrationReminders: true,
                preferredReminderInterval: 120,
                trackSodium: true,
                trackSugar: true
            )

        case .athlete:
            return HydrationSettings(
                userId: userId,
                isCalorieTrackingEnabled: true,
                isDoubleTrackWarningEnabled: true,
                autoLogDrinksFromHealth: true,
                showHydrationReminders: true,
                preferredReminderInterval: 30,
                trackSodium: true,
                trackSugar: true
            )
        }
    }
}
