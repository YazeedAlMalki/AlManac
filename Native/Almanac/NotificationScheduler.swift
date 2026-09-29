import Foundation
import UserNotifications
import AlmanacCore

/// The `UNUserNotificationCenter` half of §14, and nothing else.
///
/// Every decision this app makes about *what* to schedule lives in
/// `NotificationPlanner` (AlmanacCore, tested on any platform). This type's
/// whole job is to make the OS agree with that plan: add what is missing,
/// remove what is no longer wanted, leave alone what already matches. That is
/// the reconciliation §14.1 describes as "cancel all pending… then schedule
/// new", done as a diff rather than a nuke-and-refill so a pass that changes
/// nothing costs nothing and cannot drop a notification the user is waiting on.
///
/// **Identifiers are the diff's key.** `NotificationPlanner` mints them
/// (`almanac.<type>.<discriminator>`) and they are stable across runs over
/// unchanged state, so "already correct" is decidable. Anything pending that
/// this app did not mint — a request left by an older build, or one belonging
/// to some other feature — is left strictly alone rather than swept up by a
/// prefix match, which is what `cancelAll`'s old prefix filter did.
///
/// No Info.plist key is required for local notifications, only runtime
/// authorization — requested explicitly, never assumed.
@MainActor
struct NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    /// The prefix `NotificationPlanner` gives every identifier. Used only to
    /// recognise *our own* stale requests, never to remove anything else.
    static let ownedPrefix = "almanac."

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Whether the user has granted notification permission. Read before every
    /// reconcile: `add` throws when unauthorized, and a scheduling pass that
    /// throws on a user who declined notifications would report a failure for
    /// something they chose.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Makes the OS's pending set match `plan`, adding and removing only what
    /// differs. Safe to call as often as the app likes: with unchanged state it
    /// adds and removes nothing.
    ///
    /// Returns what changed, so a caller can log or surface it. Removal runs
    /// before addition so the pending-count ceiling is never briefly exceeded
    /// by a plan that both replaces and grows.
    @discardableResult
    func reconcile(_ plan: NotificationPlan) async -> NotificationReconcileResult {
        let pending = await center.pendingNotificationRequests()
        let pendingByID = Dictionary(pending.map { ($0.identifier, $0) },
                                     uniquingKeysWith: { first, _ in first })

        let plannedIDs = Set(plan.notifications.map(\.identifier))
        let stale = pending
            .map(\.identifier)
            .filter { Self.ownedPrefix.hasPrefix($0) && !plannedIDs.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        var added: [String] = []
        var failed: [String] = []
        for notification in plan.notifications {
            if let existing = pendingByID[notification.identifier],
               Self.matches(existing, notification) {
                continue
            }
            do {
                try await center.add(request(for: notification))
                added.append(notification.identifier)
            } catch {
                failed.append(notification.identifier)
            }
        }

        return NotificationReconcileResult(added: added, removed: stale, failed: failed)
    }

    /// Delivers a notification immediately rather than at a future instant —
    /// §14.2's pre-workout snack suggestion, which has no lead time and is
    /// computed at log time and app launch.
    @discardableResult
    func deliverNow(_ notification: PlannedNotification) async -> Bool {
        guard await isAuthorized() else { return false }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // A nil trigger delivers immediately, which is the point.
        do {
            try await center.add(UNNotificationRequest(identifier: notification.identifier,
                                                       content: content, trigger: nil))
            return true
        } catch {
            return false
        }
    }

    /// Cancels every notification this app scheduled. Used by the settings
    /// screen's "turn everything off", and by nothing else — the reconcile path
    /// removes only what the plan no longer wants.
    func cancelAll() async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { Self.ownedPrefix.hasPrefix($0) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// The identifiers currently pending that this app owns — what a settings
    /// screen shows so "you have 9 reminders queued" is read from the OS rather
    /// than recomputed from a plan that may be stale.
    func pendingOwnedIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { Self.ownedPrefix.hasPrefix($0) }
            .sorted()
    }

    // MARK: - Private

    private func request(for notification: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // Grouped by type so a burst of water reminders collapses into one
        // stack in Notification Center rather than arriving as a flat wall.
        content.threadIdentifier = notification.type.rawValue
        return UNNotificationRequest(identifier: notification.identifier, content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(
                                        timeInterval: max(1, notification.fireAt.timeIntervalSinceNow),
                                        repeats: false))
    }

    /// Whether a pending request already says what the plan says. Both halves
    /// matter: a user who changed a reminder's wording, or whose trigger moved
    /// when a shift changed, must get the new one rather than the stale one.
    private static func matches(_ request: UNNotificationRequest,
                                _ planned: PlannedNotification) -> Bool {
        guard let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
              !trigger.repeats else { return false }
        let plannedInterval = max(1, planned.fireAt.timeIntervalSinceNow)
        // Within a second of each other: the pending trigger was resolved
        // against an earlier "now" than this pass is, and demanding equality
        // would re-add the same notification on every pass forever.
        return abs(trigger.timeInterval - plannedInterval) < 1
            && request.content.title == planned.title
            && request.content.body == planned.body
    }
}

/// What one reconcile pass changed. Returned rather than logged so a caller can
/// decide whether a failure is worth the user's attention.
struct NotificationReconcileResult: Sendable, Hashable {
    let added: [String]
    let removed: [String]
    /// Identifiers the OS refused. Non-empty means notifications are enabled in
    /// the app but not accepted by the system — worth saying out loud rather
    /// than swallowing.
    let failed: [String]

    var changedAnything: Bool { !added.isEmpty || !removed.isEmpty }
}
