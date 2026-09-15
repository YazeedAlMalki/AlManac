import Foundation

/// Decides when a hydration reminder should fire and what it should say.
///
/// Single-user rewrite of `claude/app-hydration-tracking-mpwsyv`'s service:
/// the reminder schedule comes from `HydrationSettings.reminder` (see
/// `Migration013`) rather than a separate persisted `HydrationReminder`
/// entity, and every method drops the `userId` parameter the branch threaded
/// through. `checkReminder`'s trigger logic and `nextReminderTime`'s
/// scheduling arithmetic are otherwise unchanged.
public struct HydrationReminderService: Sendable {
    private let store: HydrationStore
    private let settingsStore: HydrationSettingsStore
    private let calculator: HydrationCalculator
    private let clock: any Clock
    private let healthBridge: HydrationHealthBridge?
    private let calendar: Calendar

    public init(store: HydrationStore, settingsStore: HydrationSettingsStore,
                calculator: HydrationCalculator = HydrationCalculator(), clock: any Clock = SystemClock(),
                healthBridge: HydrationHealthBridge? = nil, calendar: Calendar = .current) {
        self.store = store
        self.settingsStore = settingsStore
        self.calculator = calculator
        self.clock = clock
        self.healthBridge = healthBridge
        self.calendar = calendar
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// A recommendation to surface right now, or `nil` if no reminder should
    /// fire (disabled, outside the configured window, or not enough time
    /// since the last drink).
    public func checkReminder(profile: HydrationProfile, metrics: HydrationMetrics) throws -> HydrationRecommendation? {
        let reminder = try settingsStore.getOrCreate().reminder
        guard reminder.isEnabled else { return nil }

        let now = clock.now
        let currentHour = calendar.component(.hour, from: now)
        guard currentHour >= reminder.startHour && currentHour < reminder.endHour else { return nil }

        let today = calendar.startOfDay(for: now)
        let todaysEntries = try store.logs(from: iso(today), to: iso(now))

        let timeSinceLastDrink: Int
        if let lastSpanStart = todaysEntries.last?.loggedAt.span?.start {
            timeSinceLastDrink = Int(now.timeIntervalSince(lastSpanStart) / 60)
        } else {
            timeSinceLastDrink = Int(now.timeIntervalSince(today) / 60)
        }

        guard timeSinceLastDrink >= reminder.intervalMinutes else { return nil }

        let exerciseActive: Bool
        if let healthBridge {
            exerciseActive = (try? healthBridge.isExerciseActive(at: now)) ?? false
        } else {
            exerciseActive = false
        }

        return calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: timeSinceLastDrink, exerciseActive: exerciseActive,
            metrics: metrics, profile: profile)
    }

    /// The next moment a reminder would be due, given the schedule alone
    /// (not whether a drink has since been logged).
    public func nextReminderTime(reminder: HydrationReminder, from now: Date = Date()) -> Date? {
        guard reminder.isEnabled else { return nil }

        let currentHour = calendar.component(.hour, from: now)

        if currentHour >= reminder.endHour || currentHour < reminder.startHour {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            if currentHour >= reminder.endHour {
                components.day = (components.day ?? 0) + 1
            }
            components.hour = reminder.startHour
            components.minute = 0
            components.second = 0
            return calendar.date(from: components)
        }

        let intervalSeconds = reminder.intervalMinutes * 60
        var nextTime = now.addingTimeInterval(TimeInterval(intervalSeconds))

        let nextHour = calendar.component(.hour, from: nextTime)
        if nextHour >= reminder.endHour {
            var tomorrow = calendar.dateComponents([.year, .month, .day], from: nextTime)
            tomorrow.day = (tomorrow.day ?? 0) + 1
            tomorrow.hour = reminder.startHour
            tomorrow.minute = 0
            tomorrow.second = 0
            nextTime = calendar.date(from: tomorrow) ?? nextTime
        }

        return nextTime
    }

    /// User-friendly reminder text for `recommendation`.
    public func reminderMessage(for recommendation: HydrationRecommendation) -> String {
        var message = "\(recommendation.reason)\n\n"
        message += "Drink \(Int(recommendation.recommendedVolumeMilliliters))ml\n"

        if !recommendation.suggestedLiquidTypes.isEmpty {
            message += "Suggested: \(recommendation.suggestedLiquidTypes.map(label).joined(separator: ", "))\n"
        }

        if let timeSince = recommendation.timeSinceLastDrinkMinutes, timeSince > 120 {
            message += "\nYou haven't had anything to drink in \(formatted(minutes: timeSince))"
        }

        return message
    }

    private func label(_ type: LiquidType) -> String {
        switch type {
        case .water: return "Water"
        case .sportsDrink: return "Sports Drink"
        case .electrolyteSolution: return "Electrolyte Solution"
        case .coconutWater: return "Coconut Water"
        case .juice: return "Juice"
        case .tea: return "Tea"
        case .coffee: return "Coffee"
        case .milk: return "Milk"
        case .other: return "Other"
        }
    }

    private func formatted(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours) hour\(hours > 1 ? "s" : "")" }
        return "\(hours)h \(mins)m"
    }
}
