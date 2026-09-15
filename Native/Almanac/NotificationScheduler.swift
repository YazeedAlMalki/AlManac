import Foundation
import UserNotifications

/// Thin wrapper over `UNUserNotificationCenter` for fixed-time hydration
/// reminders. No Info.plist key is required for local notifications, only
/// runtime authorization — requested explicitly, not assumed.
@MainActor
struct NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let reminderIdentifierPrefix = "hydration-reminder-"

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Replaces any previously scheduled reminders with one repeating
    /// notification per time of day.
    func scheduleReminders(times: [DateComponents]) async {
        await cancelAll()
        for (index, time) in times.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time to hydrate"
            content.body = "Log a glass of water to stay on track."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            let request = UNNotificationRequest(identifier: "\(reminderIdentifierPrefix)\(index)",
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(reminderIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
