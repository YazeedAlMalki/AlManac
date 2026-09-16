import Foundation

/// Wires `IFSuggestion`'s threshold rule to the food log — spec §11.1's
/// "No calories have been logged for [N] hours. Are you currently fasting?"
///
/// ponytail: "a calorie entry" is approximated here as *a food log entry
/// with a stated amount*, not a computed kcal figure. Getting a real number
/// means joining through `NutritionCatalog`/`EnergyEstimate`
/// (`NutritionSummary` already does this, at real fixture cost — every
/// reference food needs seeded nutrient values). This is only a prompt: a
/// zero-calorie food logged as a false positive delays a suggestion by one
/// cycle, not a state change like `FastingSessionStore.recordNutritionEntry`,
/// which does take a real `calories` figure because breaking a session is a
/// real state change. Upgrade to a real kcal check if the coarse signal
/// proves wrong in practice.
public struct IFSuggestionService: Sendable {
    private let log: NutritionLogStore
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock(), zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.log = NutritionLogStore(db: db, clock: clock, zone: zone)
        self.clock = clock
    }

    /// Hours since the most recent stated-amount food entry within
    /// `lookbackHours` (default 72 — comfortably past any threshold anyone
    /// would configure). Nil when nothing in that window qualifies; the
    /// caller treats that as "definitely past the threshold", matching the
    /// spec's literal rule (no logged food at all trivially satisfies "no
    /// calories for N hours").
    public func hoursSinceLastCalorieEntry(before now: Date, lookbackHours: Double = 72) throws -> Double? {
        let bounds = DateRange(start: now.addingTimeInterval(-lookbackHours * 3600), end: now).utcTextBounds
        let lastInstant = try log.logged(from: bounds.start, to: bounds.end)
            .compactMap { placed -> Date? in
                guard placed.entry.grams != nil else { return nil }
                return placed.occurrence.span?.start
            }
            .max()
        guard let lastInstant else { return nil }
        return now.timeIntervalSince(lastInstant) / 3600
    }

    /// Spec §11.1's suggestion trigger, end to end.
    public func shouldSuggestFast(at now: Date? = nil, thresholdHours: Double = 14) throws -> Bool {
        let now = now ?? clock.now
        let hours = try hoursSinceLastCalorieEntry(before: now) ?? .infinity
        return IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: hours, thresholdHours: thresholdHours)
    }
}
