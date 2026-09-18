import Foundation

/// A `meal_reminder_setting` row read from storage.
public struct MealReminderSetting: Sendable, Hashable {
    public let mealType: NutritionMealType
    public let enabled: Bool
    /// Minutes since local midnight (0-1439); nil when the user has enabled
    /// the reminder but not yet chosen a time, or hasn't touched this meal
    /// type's setting at all.
    public let reminderMinuteOfDay: Int?
    public let updatedAt: Date
}

/// Reading and writing the `meal_reminder_setting` rows (Migration029) —
/// storage for §14.2's Meal Logging Reminder. Self-healing per meal type,
/// same pattern as `SleepTrackingSettingsStore`'s single row: nothing seeds
/// these four rows at migration time, `setReminder` upserts one into
/// existence (or updates it) on first write for that `NutritionMealType`.
/// A meal type with no row yet reads back as "off, no time set" —
/// `setting(for:)` synthesizes that default rather than returning nil, so
/// callers never need a separate "not configured" case alongside "off".
public struct MealReminderSettingsStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Upserts `mealType`'s setting. `reminderMinuteOfDay` is validated to
    /// `0..<1440` when not nil — an out-of-range value is a caller bug, not
    /// a storage-layer decision to silently clamp or wrap.
    public func setReminder(for mealType: NutritionMealType, enabled: Bool,
                             reminderMinuteOfDay: Int? = nil) throws {
        if let minute = reminderMinuteOfDay {
            guard (0..<1440).contains(minute) else {
                throw MealReminderSettingsStoreError.invalidMinuteOfDay(minute)
            }
        }
        try db.run("""
        INSERT INTO meal_reminder_setting (mealType, enabled, reminderMinuteOfDay, updatedAt)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(mealType) DO UPDATE SET
            enabled = excluded.enabled,
            reminderMinuteOfDay = excluded.reminderMinuteOfDay,
            updatedAt = excluded.updatedAt;
        """, [
            .text(mealType.rawValue),
            .integer(enabled ? 1 : 0),
            reminderMinuteOfDay.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(nowText)
        ])
    }

    /// `mealType`'s setting, or the "off, no time set" default when nothing
    /// has ever been written for it.
    public func setting(for mealType: NutritionMealType) throws -> MealReminderSetting {
        guard let row = try db.query("""
            SELECT mealType, enabled, reminderMinuteOfDay, updatedAt
            FROM meal_reminder_setting WHERE mealType = ?;
            """, [.text(mealType.rawValue)]).first, let parsed = rowToSetting(row) else {
            return MealReminderSetting(mealType: mealType, enabled: false,
                                        reminderMinuteOfDay: nil, updatedAt: clock.now)
        }
        return parsed
    }

    /// Every meal type's setting, defaults synthesized for any that have no
    /// row yet — always four entries, one per `NutritionMealType` case.
    public func allSettings() throws -> [MealReminderSetting] {
        try NutritionMealType.allCases.map { try setting(for: $0) }
    }

    private func rowToSetting(_ row: Row) -> MealReminderSetting? {
        guard let mealTypeRaw = row.string("mealType"),
              let mealType = NutritionMealType(rawValue: mealTypeRaw),
              let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) else { return nil }
        return MealReminderSetting(
            mealType: mealType,
            enabled: (row.int("enabled") ?? 0) != 0,
            reminderMinuteOfDay: row.int("reminderMinuteOfDay").map(Int.init),
            updatedAt: updatedAt)
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum MealReminderSettingsStoreError: Error, Sendable, Equatable {
    case invalidMinuteOfDay(Int)
}
