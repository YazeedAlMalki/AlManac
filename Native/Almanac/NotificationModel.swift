import Foundation
import AlmanacCore

/// The app's entry point into §14's notification scheduling.
///
/// §14.1 says the scheduling pass runs on app launch, on any state-changing log
/// entry, on a shift change, and when prayer times recalculate. That is four
/// kinds of event spread across most of the app, and wiring a call into each is
/// exactly the manual multi-site pattern `docs/features/fasting.md` records as
/// this repo's known failure mode — six hydration write paths had to be wired
/// by hand, with the note that "the seventh path added later will be the one
/// that forgets".
///
/// So this does not try to catch every event. It exposes one
/// `reconcileNotifications()` that reads current state and is safe to call from
/// anywhere, and wires it to the two points every one of those events passes
/// through anyway: the app going to the foreground (`AlmanacApp`'s `scenePhase`
/// handler, already the home of `prayerModel.ensureCache`/`fastingModel.
/// ensureToday`), and the settings screen after a rule is changed. A missed
/// call site costs at most one pass of staleness rather than a permanently
/// wrong schedule, because the next foreground repairs it.
@MainActor
final class NotificationModel: ObservableObject {
    /// The last plan this app computed, for the settings screen to show what is
    /// queued. Nil until the first successful pass, and after a failed one —
    /// a screen that shows an empty list when it could not read is lying.
    @Published private(set) var lastPlan: NotificationPlan?
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isAuthorized: Bool = false
    /// Set when the pass itself failed. Separate from an empty plan, which is
    /// the ordinary "nothing to schedule" state.
    @Published private(set) var schedulingProblem: String?

    private var db: Database?
    private let scheduler = NotificationScheduler()
    private var isConfigured = false
    /// Guards against a second pass starting while one is in flight. Both the
    /// foreground handler and a settings toggle can fire close together, and
    /// two concurrent `pendingNotificationRequests` reads with interleaved
    /// removals would produce a plan that disagrees with what got scheduled.
    private var passInFlight = false

    func configure(db: Database?) {
        guard let db, !isConfigured else { return }
        isConfigured = true
        self.db = db
    }

    /// Runs §14.1's whole pass: plan, then make the OS match. Idempotent and
    /// cheap enough to call on every foreground.
    func reconcileNotifications() async {
        guard let db, !passInFlight else { return }
        passInFlight = true
        defer { passInFlight = false }

        do {
            let plan = try NotificationPlanner(db: db, timeModel: TimeModel(timeZone: .current)).plan()
            guard await scheduler.isAuthorized() else {
                // Declined, or never asked. Recording the plan is still honest —
                // it says what *would* be scheduled — but the pending count is
                // zero because nothing is.
                lastPlan = plan
                pendingCount = 0
                isAuthorized = false
                schedulingProblem = nil
                return
            }
            let result = await scheduler.reconcile(plan)
            lastPlan = plan
            isAuthorized = true
            pendingCount = await scheduler.pendingOwnedIdentifiers().count
            schedulingProblem = result.failed.isEmpty
                ? nil
                : "Almanac could not schedule \(result.failed.count) reminder\(result.failed.count == 1 ? "" : "s")."
        } catch {
            schedulingProblem = "Almanac could not work out which reminders to schedule."
        }
    }

    /// §14.2's pre-workout snack suggestion, which the spec computes at log time
    /// and at app launch and gives no lead time — so it is delivered now rather
    /// than planned ahead. False when there is nothing to suggest, which is the
    /// ordinary case.
    @discardableResult
    func deliverSnackSuggestionIfWarranted() async -> Bool {
        guard let db else { return false }
        do {
            guard let suggestion = try NotificationPlanner(db: db, timeModel: TimeModel(timeZone: .current))
                .immediateSnackSuggestion() else { return false }
            return await scheduler.deliverNow(suggestion)
        } catch {
            return false
        }
    }

    /// Asks for permission, then schedules. Split from `reconcileNotifications`
    /// because the system prompt must be the result of a deliberate tap, never a
    /// side effect of the app opening.
    @discardableResult
    func requestAuthorizationAndSchedule() async throws -> Bool {
        let granted = try await scheduler.requestAuthorization()
        isAuthorized = granted
        guard granted else {
            schedulingProblem = "Notifications were not authorized."
            return false
        }
        await reconcileNotifications()
        return true
    }

    /// Reads the per-type switches and writes one back, then reconciles. The
    /// settings screen's whole interaction with this feature.
    func setEnabled(_ enabled: Bool, for type: NotificationType) throws {
        guard let db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try NotificationRuleStore(db: db).setEnabled(enabled, for: type)
    }

    func rules() throws -> [NotificationRule] {
        guard let db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        return try NotificationRuleStore(db: db).allRules()
    }

    /// Turns every type off and clears what is already queued, for a user who
    /// wants Almanac to stop notifying them entirely.
    func cancelEverything() async {
        do {
            if let db {
                let store = NotificationRuleStore(db: db)
                for type in NotificationType.allCases where try store.isEnabled(type) {
                    try store.setEnabled(false, for: type)
                }
            }
            await scheduler.cancelAll()
            lastPlan = .empty(Date())
            pendingCount = 0
        } catch {
            schedulingProblem = "Almanac could not turn its reminders off."
        }
    }
}
