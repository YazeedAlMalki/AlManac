import Foundation

/// Service for managing hydration reminders and notifications
public final class HydrationReminderService: Sendable {
    private let store: HydrationStore
    private let calculator: HydrationCalculator
    private let clock: Clock

    public init(
        store: HydrationStore,
        calculator: HydrationCalculator = HydrationCalculator(),
        clock: Clock = SystemClock()
    ) {
        self.store = store
        self.calculator = calculator
        self.clock = clock
    }

    /// Check if a reminder should be triggered now
    /// - Returns: Recommendation if reminder should trigger, nil otherwise
    public func checkReminder(
        profile: HydrationProfile,
        currentMetrics: HydrationMetrics
    ) throws -> HydrationRecommendation? {
        let reminders = try store.fetchReminders()
        guard let activeReminder = reminders.first(where: { $0.isEnabled }) else {
            return nil
        }

        let now = clock.now
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Check if we're in the reminder window
        guard currentHour >= activeReminder.startHour && currentHour < activeReminder.endHour else {
            return nil
        }

        // Get the last hydration sample
        let today = calendar.startOfDay(for: now)
        let samples = try store.fetchSamples(from: today, to: now)
        let lastSample = samples.first

        let timeSinceLastDrink: Int
        if let lastSample = lastSample {
            timeSinceLastDrink = Int(now.timeIntervalSince(lastSample.timestamp) / 60)
        } else {
            // No samples today, use hours since midnight
            timeSinceLastDrink = Int(now.timeIntervalSince(today) / 60)
        }

        // Only trigger if enough time has passed
        guard timeSinceLastDrink >= activeReminder.intervalMinutes else {
            return nil
        }

        // Generate recommendation
        return calculator.currentRecommendation(
            timeSinceLastDrinkMinutes: timeSinceLastDrink,
            exerciseActive: false,  // Would be updated from Health module
            metrics: currentMetrics,
            profile: profile
        )
    }

    /// Get next scheduled reminder time
    /// - Returns: Date of next scheduled reminder
    public func nextReminderTime(
        reminder: HydrationReminder
    ) -> Date? {
        guard reminder.isEnabled else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = reminder.startHour
        components.minute = 0
        components.second = 0

        guard let startOfReminders = calendar.date(from: components) else {
            return nil
        }

        let now = Date()
        if now < startOfReminders {
            return startOfReminders
        }

        // Find next reminder time
        let intervalSeconds = reminder.intervalMinutes * 60
        var nextTime = now.addingTimeInterval(TimeInterval(intervalSeconds))

        // Check if next time is still within reminder window
        let nextHour = calendar.component(.hour, from: nextTime)
        if nextHour >= reminder.endHour {
            // Move to start of reminders tomorrow
            var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: nextTime)
            tomorrowComponents.day = (tomorrowComponents.day ?? 0) + 1
            tomorrowComponents.hour = reminder.startHour
            tomorrowComponents.minute = 0
            tomorrowComponents.second = 0
            nextTime = calendar.date(from: tomorrowComponents) ?? nextTime
        }

        return nextTime
    }

    /// Create a default reminder
    /// - Returns: Default hydration reminder
    public func createDefaultReminder() throws -> HydrationReminder {
        let reminder = HydrationReminder(
            id: UUID().uuidString,
            intervalMinutes: 60,
            startHour: 7,
            endHour: 22,
            isEnabled: true,
            createdAt: Date()
        )
        try store.save(reminder)
        return reminder
    }

    /// Update reminder configuration
    /// - Parameters:
    ///   - id: Reminder ID
    ///   - intervalMinutes: New interval between reminders
    ///   - startHour: New start hour
    ///   - endHour: New end hour
    ///   - isEnabled: Whether reminder is enabled
    public func updateReminder(
        id: String,
        intervalMinutes: Int? = nil,
        startHour: Int? = nil,
        endHour: Int? = nil,
        isEnabled: Bool? = nil
    ) throws {
        let reminders = try store.fetchReminders()
        guard let existing = reminders.first(where: { $0.id == id }) else {
            throw HydrationError.reminderNotFound
        }

        let updated = HydrationReminder(
            id: existing.id,
            intervalMinutes: intervalMinutes ?? existing.intervalMinutes,
            startHour: startHour ?? existing.startHour,
            endHour: endHour ?? existing.endHour,
            isEnabled: isEnabled ?? existing.isEnabled,
            createdAt: existing.createdAt
        )

        try store.save(updated)
    }

    /// Enable or disable all reminders
    /// - Parameter enabled: Whether reminders should be enabled
    public func setRemindersEnabled(_ enabled: Bool) throws {
        let reminders = try store.fetchReminders()
        for reminder in reminders {
            try updateReminder(id: reminder.id, isEnabled: enabled)
        }
    }

    /// Get smart reminder message based on current context
    /// - Parameters:
    ///   - recommendation: Current hydration recommendation
    ///   - profile: User's hydration profile
    /// - Returns: User-friendly reminder message
    public func getReminderMessage(
        recommendation: HydrationRecommendation,
        profile: HydrationProfile
    ) -> String {
        var message = ""

        // Emoji based on urgency
        let emoji: String
        switch recommendation.urgency {
        case .critical:
            emoji = "🚨"
        case .high:
            emoji = "⚠️"
        case .moderate:
            emoji = "💧"
        case .low:
            emoji = "✨"
        }

        message += "\(emoji) \(recommendation.reason)\n\n"
        message += "💧 Drink \(Int(recommendation.recommendedVolumeMilliliters))ml\n"

        // Suggest drink types
        if !recommendation.suggestedLiquidTypes.isEmpty {
            message += "Suggested: \(recommendation.suggestedLiquidTypes.map { formatLiquidType($0) }.joined(separator: ", "))\n"
        }

        // Time-based tip
        if let timeSince = recommendation.timeSinceLastDrinkMinutes {
            if timeSince > 120 {
                message += "\n⏰ You haven't had anything to drink in \(formatTime(minutes: timeSince))"
            }
        }

        return message
    }

    // MARK: - Private Helpers

    private func formatLiquidType(_ type: LiquidType) -> String {
        switch type {
        case .water:
            return "💧 Water"
        case .sportsDrink:
            return "⚡ Sports Drink"
        case .electrolyteSolution:
            return "🧂 Electrolyte Solution"
        case .coconutWater:
            return "🥥 Coconut Water"
        case .juice:
            return "🧃 Juice"
        case .tea:
            return "🍵 Tea"
        case .coffee:
            return "☕ Coffee"
        case .milk:
            return "🥛 Milk"
        case .other:
            return "🥤 Other"
        }
    }

    private func formatTime(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hour\(hours > 1 ? "s" : "")"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
}

// MARK: - Error Types

public enum HydrationError: Error, Sendable {
    case reminderNotFound
    case invalidConfiguration
    case databaseError(String)
}
