import Foundation

/// Wires `NutritionLogStore.record` to `FastingSessionStore.recordNutritionEntry`
/// — spec §11.1's "a calorie entry breaks a fast" applied automatically the
/// moment a meal is logged, rather than left to a caller to remember.
///
/// Kept out of `NutritionLogStore` itself, not folded in: Nutrition is a
/// foundational module that "holds nothing, stores nothing" beyond the food
/// log and must not know about a higher-level feature built on top of it —
/// the same dependency direction `IFSuggestionService` already documents
/// (Fasting depends on Nutrition, never the reverse).
///
/// Uses the entry's actual computed energy (`NutritionCatalog`/
/// `EnergyEstimate`), unlike `IFSuggestionService`'s coarser "stated amount"
/// approximation — that one only drives a prompt; this one changes stored
/// fasting state, so it earns the real number.
public struct FastingAwareNutritionLog: Sendable {
    private let log: NutritionLogStore
    private let catalog: NutritionCatalog
    private let sessions: FastingSessionStore
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock(), zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.log = NutritionLogStore(db: db, clock: clock, zone: zone)
        self.catalog = NutritionCatalog(db: db)
        self.sessions = FastingSessionStore(db: db, clock: clock)
        self.clock = clock
    }

    /// Records the meal, then applies the break rule using the entry's own
    /// `eatenAt` — backdating a meal is exactly what
    /// `FastingSessionStore.recordNutritionEntry` exists to reconcile, so the
    /// timestamp must be when it was eaten, not when this call happened.
    /// Falls back to "now" when `eatenAt` isn't known, matching
    /// `NutritionLogStore`'s own placement fallback.
    @discardableResult
    public func record(_ draft: NutritionLogDraft) throws -> (outcome: NutritionLogOutcome, fastingOutcome: FastingBreakOutcome) {
        let outcome = try log.record(draft)
        let calories = try energyKilocalories(foodRef: draft.foodRef, grams: draft.grams)
        let timestamp = draft.eatenAt.isKnown ? (draft.eatenAt.span?.start ?? clock.now) : clock.now
        let fastingOutcome = try sessions.recordNutritionEntry(calories: calories, at: timestamp)
        return (outcome, fastingOutcome)
    }

    /// Applies a correction and re-runs the same fasting decision against the
    /// edited entry's current food, amount and occurrence time. The stored
    /// revision remains owned by `NutritionLogStore`; this layer only keeps the
    /// dependent fasting state in sync.
    @discardableResult
    public func update(id logID: String, _ edit: NutritionLogEdit) throws -> (outcome: NutritionLogOutcome, fastingOutcome: FastingBreakOutcome) {
        guard let previous = try log.entry(id: logID) else {
            return (try log.update(id: logID, edit), .noOp)
        }
        let previousCalories = try energyKilocalories(foodRef: previous.foodRef, grams: previous.grams)
        let previousTimestamp = previous.eatenAt.isKnown ? (previous.eatenAt.span?.start ?? clock.now) : clock.now
        let outcome = try log.update(id: logID, edit)
        if case .unchanged = outcome {
            return (outcome, .noOp)
        }
        guard let entry = try log.entry(id: logID) else {
            return (outcome, .noOp)
        }
        let calories = try energyKilocalories(foodRef: entry.foodRef, grams: entry.grams)
        let timestamp = entry.eatenAt.isKnown ? (entry.eatenAt.span?.start ?? clock.now) : clock.now
        let fastingOutcome = try sessions.reconcileNutritionEdit(
            previousCalories: previousCalories,
            previousTimestamp: previousTimestamp,
            currentCalories: calories,
            currentTimestamp: timestamp
        )
        return (outcome, fastingOutcome)
    }

    /// No amount stated, or an unrecognised food, contributes zero — the same
    /// "no amount stated contributes nothing" rule `NutritionTotals` already
    /// applies. Never a guess: an uncomputable entry never breaks a fast.
    private func energyKilocalories(foodRef: SourceIdentifier, grams: Double?) throws -> Double {
        guard let grams, try catalog.food(foodRef) != nil else { return 0 }
        let values = try catalog.values(for: foodRef, basis: .per100g)
        guard let energy = EnergyEstimate.preferred(from: values, basis: .per100g)?.scaled(toGrams: grams) else {
            return 0
        }
        return energy.kilocalories
    }
}
