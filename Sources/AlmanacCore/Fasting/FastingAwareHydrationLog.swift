import Foundation

/// Every hydration write, with the fasting rules it carries applied in one
/// place:
///
/// - **A religious dry fast** is broken by any drink, water included (the
///   owner's rule, 2026-09-29). §11.1's "water never breaks a fast" is written
///   for intermittent fasting and deliberately does not apply: a *dry* fast
///   that was drunk from is not a fast that was kept.
/// - **An intermittent fast** is broken by a drink only when it carries
///   calories (§11.1: "calories > 0 → breaks fast immediately"). A juice is a
///   calorie entry whichever log it was written to.
/// - **The night window** (§7.2) claims a drink between Maghrib and Fajr.
///
/// Before this type was the one every write path went through, each of the
/// app's four hydration write paths applied the window rule by hand and none
/// applied either fasting rule — water logged during a dry fast never broke it.
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
    private let coordinator: FastingCoordinator
    private let assigner: NightNutritionWindowAssigner

    public init(db: Database, clock: any Clock = SystemClock(), zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.store = HydrationStore(db: db, clock: clock, zone: zone)
        self.sessions = FastingSessionStore(db: db, clock: clock)
        self.coordinator = FastingCoordinator(db: db, clock: clock,
                                              timeZone: zone.identifier.flatMap(TimeZone.init(identifier:)) ?? .current)
        self.assigner = NightNutritionWindowAssigner(db: db)
    }

    /// Records the drink, then applies the rules. The write happens first and
    /// unconditionally: a broken fast is still a real thing the user drank, and
    /// losing the entry to enforce a rule about the fast would be the wrong
    /// trade.
    @discardableResult
    public func log(_ draft: HydrationLogDraft) throws -> (hydrationLogID: String, fastingOutcome: FastingBreakOutcome) {
        let id = try store.log(draft)
        let outcome = try didLog(hydrationLogID: id)
        return (id, outcome)
    }

    /// The rules, for a drink some other service already wrote — the catalog
    /// drink path (`HydrationLoggingService.logDrink`), which owns its own
    /// warnings and scaling and should not be reimplemented here. Reads the
    /// stored row back, so the calories it judges by are the scaled figures
    /// that were actually recorded.
    @discardableResult
    public func didLog(hydrationLogID id: String) throws -> FastingBreakOutcome {
        guard let entry = try store.entry(id: id), let at = entry.loggedAt.span?.start else { return .noOp }
        var outcome = FastingBreakOutcome.noOp
        if let calories = entry.drink?.caloriesKcal, calories > 0 {
            outcome = try sessions.recordNutritionEntry(calories: calories, at: at)
        }
        let religious = try applyDryFastRule(at: at)
        if religious != .noOp { outcome = religious }
        try assigner.assign(hydrationLogID: id, loggedAt: at)
        return outcome
    }

    /// After an edit moved or resized a drink: both the day it left and the day
    /// it landed on are re-derived, and the window follows its new time.
    public func didEdit(hydrationLogID id: String, previousLoggedAt: Date?) throws {
        let current = try store.entry(id: id)?.loggedAt.span?.start
        for instant in [previousLoggedAt, current].compactMap({ $0 }) {
            try coordinator.reconcile(containing: instant)
        }
        if let current { try assigner.assign(hydrationLogID: id, loggedAt: current) }
    }

    /// Deletes a drink and re-derives the fast it may have broken — deleting
    /// the water logged by mistake at noon gives the day its fast back.
    public func delete(id: String) throws {
        let at = try store.entry(id: id)?.loggedAt.span?.start
        try store.delete(id: id)
        if let at { try coordinator.reconcile(containing: at) }
    }

    /// The religious session derived for the drink's day when its prayer times
    /// are known; the session-only rule when they are not.
    private func applyDryFastRule(at instant: Date) throws -> FastingBreakOutcome {
        guard let derived = try coordinator.reconcile(containing: instant) else {
            return try sessions.recordIntake(at: instant)
        }
        return try FastingBreakOutcome(derived, sessions: sessions)
    }
}

extension FastingBreakOutcome {
    /// A derived religious outcome, in the vocabulary the logging wrappers
    /// report: a break is `.ended` with the duration actually fasted; anything
    /// else did not break a fast on this write.
    init(_ outcome: ReligiousFastingOutcome, sessions: FastingSessionStore) throws {
        guard case .sessionBroken(let id, _) = outcome,
              let minutes = try sessions.session(id: id)?.finalDurationMinutes else {
            self = .noOp
            return
        }
        self = .ended(sessionId: id, durationMinutes: minutes)
    }
}
