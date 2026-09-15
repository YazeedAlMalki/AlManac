import Foundation

// MARK: - Values

/// One logged meal, joined to what the catalog knows about it.
public struct LoggedFood: Sendable, Hashable {
    public let entry: NutritionLogEntry
    public let occurrence: PartialDateTime
    public let basis: TimeBasis
    /// Nil when the reference row is gone — a source was removed, or the entry
    /// was logged against a food that never existed. `entry.foodNameText` is
    /// what the person saw at the time and is still readable.
    public let food: NutritionFood?
    /// Scaled to the logged mass. Nil when neither the macros nor a published
    /// energy figure were available, which is not the same as no calories.
    public let energy: EnergyEstimate?
}

/// What a range of the food log adds up to, and what it could not add up.
///
/// Every "could not" is a separate field rather than a silent omission. A
/// calorie total that quietly drops the meals it could not price is the single
/// most misleading number this module could produce.
public struct NutritionTotals: Sendable, Hashable {
    public let kcal: Double
    /// Which routes the energy came through. More than one entry means the
    /// total mixes computed and publisher-reported figures, which a UI should
    /// be able to say.
    public let energyBases: Set<EnergyEstimate.Method>
    /// Per nutrient id, summed over the counted meals. A nutrient that any
    /// counted meal could not supply is **absent from this dictionary** and
    /// named in `incompleteNutrients` — never present as a smaller number.
    public let nutrients: [String: Double]
    public let mealsCounted: Int
    /// Logged, but with no amount stated, so they contribute nothing.
    public let mealsWithoutAmount: [String]
    /// Logged against a food the catalog does not hold.
    public let mealsWithoutReference: [SourceIdentifier]
    /// Nutrients at least one counted meal did not report, reported as not
    /// analysed, or reported in a unit that disagrees with another meal's.
    public let incompleteNutrients: [String]

    public var isComplete: Bool {
        mealsWithoutAmount.isEmpty && mealsWithoutReference.isEmpty
            && incompleteNutrients.isEmpty
    }
}

/// Reads the food log against the reference catalog.
///
/// Holds nothing and stores nothing: totals are derived on demand, so a
/// corrected reference value corrects every day already logged against it. That
/// is the whole reason `nutrition_log` carries no energy column.
public struct NutritionSummary: Sendable {
    private let log: NutritionLogStore
    private let catalog: NutritionCatalog

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.log = NutritionLogStore(db: db, clock: clock, zone: zone)
        self.catalog = NutritionCatalog(db: db)
    }

    public func loggedFoods(from: String, to: String) throws -> [LoggedFood] {
        let cache = Cache(catalog)
        return try log.logged(from: from, to: to).map { placed in
            let ref = placed.entry.foodRef
            let food = try cache.food(ref)
            var energy: EnergyEstimate?
            if food != nil, let grams = placed.entry.grams {
                energy = EnergyEstimate.preferred(from: try cache.values(ref), basis: .per100g)?
                    .scaled(toGrams: grams)
            }
            return LoggedFood(entry: placed.entry, occurrence: placed.occurrence,
                              basis: placed.basis, food: food, energy: energy)
        }
    }

    /// A day of the same rice is one lookup, not one per helping. Scoped to a
    /// single call, so nothing here goes stale between them.
    private final class Cache {
        private let catalog: NutritionCatalog
        private var foodCache: [SourceIdentifier: NutritionFood?] = [:]
        private var valueCache: [SourceIdentifier: [NutrientValue]] = [:]
        init(_ catalog: NutritionCatalog) { self.catalog = catalog }

        func food(_ ref: SourceIdentifier) throws -> NutritionFood? {
            if let hit = foodCache[ref] { return hit }
            let loaded = try catalog.food(ref)
            foodCache[ref] = loaded
            return loaded
        }

        func values(_ ref: SourceIdentifier) throws -> [NutrientValue] {
            if let hit = valueCache[ref] { return hit }
            let loaded = try catalog.values(for: ref, basis: .per100g)
            valueCache[ref] = loaded
            return loaded
        }
    }

    /// The same reads, for a logical day rather than a pair of ISO strings.
    ///
    /// "What did I eat today" is not a UTC range: a day in Riyadh starts at
    /// 21:00Z the evening before, and a body monitor's day may not start at
    /// midnight at all. Both questions go through `TimeModel`, which is where
    /// the boundary rule lives — so when the placeholder day boundary stops
    /// being the placeholder it is today, every total moves with it instead of
    /// needing to be found and changed here.
    ///
    /// Nil when the model cannot place the day, which is what it returns for a
    /// date that does not exist.
    public func totals(on day: LogicalDay, in model: TimeModel) throws -> NutritionTotals? {
        guard let bounds = NutritionSummary.textBounds(day, model) else { return nil }
        return try totals(from: bounds.start, to: bounds.end)
    }

    public func loggedFoods(on day: LogicalDay, in model: TimeModel) throws -> [LoggedFood]? {
        guard let bounds = NutritionSummary.textBounds(day, model) else { return nil }
        return try loggedFoods(from: bounds.start, to: bounds.end)
    }

    /// Normalised to UTC text before it reaches the range reads, the same way
    /// `HealthSampleStore` normalises its query bounds — comparing a stored
    /// `...Z` value against a caller's `+03:00` text is wrong by the offset,
    /// and silently so.
    private static func textBounds(_ day: LogicalDay,
                                   _ model: TimeModel) -> (start: String, end: String)? {
        guard let bounds = model.bounds(of: day) else { return nil }
        return DateRange(start: bounds.start, end: bounds.end).utcTextBounds
    }

    public func totals(from: String, to: String) throws -> NutritionTotals {
        let cache = Cache(catalog)
        var counted: [(ref: SourceIdentifier, grams: Double)] = []
        var withoutAmount: [String] = []
        var withoutReference: [SourceIdentifier] = []
        var incomplete: Set<String> = []
        var kcal = 0.0
        var bases: Set<EnergyEstimate.Method> = []

        for placed in try log.logged(from: from, to: to) {
            let entry = placed.entry
            guard let grams = entry.grams else {
                withoutAmount.append(entry.id)
                continue
            }
            guard try cache.food(entry.foodRef) != nil else {
                withoutReference.append(entry.foodRef)
                continue
            }
            counted.append((entry.foodRef, grams))

            if let energy = EnergyEstimate.preferred(from: try cache.values(entry.foodRef), basis: .per100g)?
                .scaled(toGrams: grams) {
                kcal += energy.kilocalories
                bases.insert(energy.method)
            } else {
                // This meal contributed calories nobody can put a number on, so
                // the running total understates and must say so.
                incomplete.insert("energy_kcal")
            }
        }

        var nutrientIDs: Set<String> = []
        for (ref, _) in counted {
            nutrientIDs.formUnion(try cache.values(ref).map(\.nutrientID))
        }

        var totals: [String: Double] = [:]
        for nutrientID in nutrientIDs {
            var sum = 0.0
            var unit: String?
            var usable = true
            for (ref, grams) in counted {
                guard let value = try cache.values(ref)
                        .first(where: { $0.nutrientID == nutrientID }),
                      let scaled = value.scaled(toGrams: grams) else {
                    usable = false
                    break
                }
                // Nothing here converts units, so two meals reporting a
                // nutrient on different scales are not added together.
                if let unit, UnitRegistry.key(unit) != UnitRegistry.key(value.sourceUnit) {
                    usable = false
                    break
                }
                unit = value.sourceUnit
                sum += scaled
            }
            if usable { totals[nutrientID] = sum } else { incomplete.insert(nutrientID) }
        }

        return NutritionTotals(
            kcal: kcal, energyBases: bases, nutrients: totals, mealsCounted: counted.count,
            mealsWithoutAmount: withoutAmount, mealsWithoutReference: withoutReference,
            incompleteNutrients: incomplete.sorted())
    }
}
