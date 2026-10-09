import Foundation

/// Every intake — food or drink — in a span, as the religious dry fast sees it.
///
/// A dry fast is broken by **any** intake (the owner's rule, 2026-09-29): food
/// whatever its calories, water, black coffee. So this reads both logs and
/// does not compute energy at all. That is what makes a religious session
/// derivable from the logs alone: its end is the first instant in
/// `[Fajr, Maghrib)` that this finds, and it does not matter which screen,
/// widget, editor or Health import wrote the row.
///
/// Read-only over two other modules' tables, through their own stores, for the
/// reason `NightNutritionWindowAssigner` gives: Fasting depends on Nutrition and
/// Hydration, never the reverse.
public struct FastingIntakeLog: @unchecked Sendable {
    private let nutrition: NutritionLogStore
    private let hydration: HydrationStore

    public init(db: Database) {
        self.nutrition = NutritionLogStore(db: db)
        self.hydration = HydrationStore(db: db)
    }

    /// One logged intake.
    public struct Intake: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable { case food, drink }
        public let kind: Kind
        public let id: String
        public let at: Date
        /// The food's or drink's name as logged, or nil for plain water.
        public let label: String?
        /// Millilitres for a drink; grams for food when stated.
        public let amount: Double?
    }

    /// Every intake with an instant in `[start, end)`, oldest first.
    ///
    /// Only an instant-precise food time counts. A meal recorded as "this
    /// morning" or "March 2019" spans the fast on paper and says nothing about
    /// whether it was eaten during it, so it neither breaks a fast nor is
    /// claimed by the night window (`NightNutritionWindowAssigner` makes the same
    /// call for the same reason).
    public func intakes(from start: Date, to end: Date) throws -> [Intake] {
        guard end > start else { return [] }
        let bounds = DateRange(start: start, end: end).utcTextBounds
        var found: [Intake] = []
        for placed in try nutrition.logged(from: bounds.start, to: bounds.end) {
            guard placed.occurrence.precision == .instant,
                  let at = placed.occurrence.span?.start, at >= start, at < end else { continue }
            found.append(Intake(kind: .food, id: placed.entry.id, at: at,
                                label: placed.entry.foodNameText, amount: placed.entry.grams))
        }
        for entry in try hydration.logs(from: bounds.start, to: bounds.end) {
            guard let at = entry.loggedAt.span?.start, at >= start, at < end else { continue }
            found.append(Intake(kind: .drink, id: entry.id, at: at,
                                label: entry.drink?.displayName, amount: entry.amount.value))
        }
        return found.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
    }

    /// The first intake in `[start, end)`, or nil when there was none.
    public func earliestIntake(from start: Date, to end: Date) throws -> Intake? {
        try intakes(from: start, to: end).first
    }
}
