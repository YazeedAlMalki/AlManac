import Testing
import Foundation
@testable import AlmanacCore

@Suite("MealReminderSettingsStore Tests")
struct MealReminderSettingsStoreTests {
    let db = try! TestDatabase()
    var store: MealReminderSettingsStore { MealReminderSettingsStore(db: db) }

    @Test("A meal type with no row yet reads back as off, no time set")
    func defaultsToOff() throws {
        let setting = try store.setting(for: .breakfast)
        #expect(setting.enabled == false)
        #expect(setting.reminderMinuteOfDay == nil)
    }

    @Test("setReminder turns a meal type's reminder on with a time and reads it back")
    func setReminderOnWithTime() throws {
        try store.setReminder(for: .lunch, enabled: true, reminderMinuteOfDay: 12 * 60)

        let setting = try store.setting(for: .lunch)
        #expect(setting.enabled == true)
        #expect(setting.reminderMinuteOfDay == 12 * 60)
    }

    @Test("Re-setting the same meal type updates the row rather than duplicating it")
    func setReminderIsIdempotentPerMealType() throws {
        try store.setReminder(for: .dinner, enabled: true, reminderMinuteOfDay: 18 * 60)
        try store.setReminder(for: .dinner, enabled: true, reminderMinuteOfDay: 19 * 60)

        let setting = try store.setting(for: .dinner)
        #expect(setting.reminderMinuteOfDay == 19 * 60)

        let count = try db.query("SELECT COUNT(*) as n FROM meal_reminder_setting WHERE mealType = 'dinner';")
            .first?.int("n")
        #expect(count == 1)
    }

    @Test("Settings for different meal types don't collide")
    func settingsAreIndependentPerMealType() throws {
        try store.setReminder(for: .breakfast, enabled: true, reminderMinuteOfDay: 7 * 60)
        try store.setReminder(for: .snack, enabled: false, reminderMinuteOfDay: nil)

        #expect(try store.setting(for: .breakfast).enabled == true)
        #expect(try store.setting(for: .snack).enabled == false)
        // Untouched meal types still default rather than inheriting anything.
        #expect(try store.setting(for: .lunch).enabled == false)
    }

    @Test("setReminder rejects a minute-of-day outside 0..<1440")
    func setReminderRejectsInvalidMinute() throws {
        #expect(throws: MealReminderSettingsStoreError.invalidMinuteOfDay(-1)) {
            try store.setReminder(for: .breakfast, enabled: true, reminderMinuteOfDay: -1)
        }
    }

    @Test("allSettings always returns exactly the four meal types, defaults synthesized")
    func allSettingsReturnsEveryMealType() throws {
        try store.setReminder(for: .breakfast, enabled: true, reminderMinuteOfDay: 420)

        let all = try store.allSettings()
        #expect(Set(all.map { $0.mealType }) == Set(NutritionMealType.allCases))
        #expect(all.first { $0.mealType == .breakfast }?.enabled == true)
        #expect(all.first { $0.mealType == .lunch }?.enabled == false)
    }
}
