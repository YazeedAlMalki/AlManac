import Foundation
import UserNotifications
import AlmanacCore

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var notificationsEnabled: Bool = false
    @Published var pendingNotifications: [UNNotificationRequest] = []

    private let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.notificationsEnabled = granted
                self.checkAuthorizationStatus()
            }
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
                self?.notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    func scheduleReminderNotification(
        for reminder: HydrationReminder,
        with recommendation: HydrationRecommendation,
        triggerDate: Date
    ) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "💧 Time to Hydrate"
        content.body = recommendation.reason
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        content.userInfo = [
            "recommendedVolume": recommendation.recommendedVolumeMilliliters,
            "suggestedLiquids": recommendation.suggestedLiquidTypes.map { String(describing: $0) },
            "reminderID": reminder.id
        ]

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "hydration_reminder_\(reminder.id)_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    func schedulePeriodicReminders(
        for reminder: HydrationReminder,
        with recommendation: HydrationRecommendation
    ) async {
        guard notificationsEnabled else { return }
        guard reminder.isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "💧 Stay Hydrated"
        content.body = recommendation.reason
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        content.userInfo = [
            "recommendedVolume": recommendation.recommendedVolumeMilliliters,
            "suggestedLiquids": recommendation.suggestedLiquidTypes.map { String(describing: $0) },
            "reminderID": reminder.id
        ]

        let intervalSeconds = reminder.intervalMinutes * 60
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(intervalSeconds),
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "hydration_periodic_\(reminder.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule periodic notification: \(error)")
        }
    }

    func cancelReminderNotifications(for reminderId: String) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["hydration_reminder_\(reminderId)", "hydration_periodic_\(reminderId)"]
        )
    }

    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    func getPendingNotifications() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        await MainActor.run {
            self.pendingNotifications = requests
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let recommendedVolume = userInfo["recommendedVolume"] as? Double {
            NotificationCenter.default.post(
                name: NSNotification.Name("HydrationReminderTapped"),
                object: nil,
                userInfo: ["recommendedVolume": recommendedVolume]
            )
        }

        completionHandler()
    }
}
