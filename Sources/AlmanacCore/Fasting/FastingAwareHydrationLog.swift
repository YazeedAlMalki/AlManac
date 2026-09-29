import Foundation

/// Wires `HydrationStore.log` to `FastingSessionStore.recordIntake` — the
/// owner's rule (2026-09-29) that **any** intake ends a religious dry fast,
/// water included. §11.1's "water never breaks a fast" is written for
/// intermittent fasting and deliberately does not apply here: a *dry* fast that
/// was drunk from is not a fast that was kept, and the app should not record it
/// as one.
///
/// Kept out of `HydrationStore` for the same reason `FastingAwareNutritionLog`
/// is kept out of `NutritionLogStore`: Hydration is a foundational module that
/// must not know a higher-level feature is built on it. Fasting depends on
/// Hydration, never the reverse.
///
/// Uses the entry's own `loggedAt`, not "now" — the same reasoning as the
/// nutrition wrapper: a backdated entry has to be reconciled against when it
/// actually happened.
public struct FastingAwareHydrationLog: Sendable {
    private let store: HydrationStore
    private let sessions: FastingSessionStore

    public init(db: Database, clock: any Clock = SystemClock(), zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.store = HydrationStore(db: db, clock: clock, zone: zone)
        self.sessions = FastingSessionStore(db: db, clock: clock)
    }

    /// Records the drink, then applies the dry-fast rule. The write happens
    /// first and unconditionally: an invalid fast is still a real thing the
    /// user drank, and losing the entry to enforce a rule about the fast would
    /// be the wrong trade.
    @discardableResult
    public func log(_ draft: HydrationLogDraft) throws -> (hydrationLogID: String, fastingOutcome: FastingBreakOutcome) {
        let id = try store.log(draft)
        let outcome = try sessions.recordIntake(at: draft.loggedAt)
        return (id, outcome)
    }
}
