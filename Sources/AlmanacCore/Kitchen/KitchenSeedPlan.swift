import Foundation

/// The recipes a UI test asks the app to plant before Kitchen is driven, and
/// the only way the app is ever permitted to plant them.
///
/// ## Why this exists
///
/// Nothing in the app creates a dish with components. `NutritionDishEditor` can,
/// and the Saved meals list shows what it made, but no screen calls `setRecipe`
/// — so on a fresh simulator Kitchen has no recipe to find, and a UI test of it
/// would be a test of three empty states. The same reasoning as
/// `VitalsSeedPlan`: name the state in a launch argument, write it through the
/// same public editor a recipe import would use, and keep the whole cost behind
/// two gates — `fromLaunchArguments` returns nil for every ordinary launch
/// (`KitchenSeedPlanTests` pins that), and the app's only call site is
/// `#if DEBUG`.
///
/// ## What it plants
///
/// Four `almanac:` foods under a `ui-kitchen-` prefix, so they cannot collide
/// with anything a person made:
///
/// - **Kitchen test rice** and **Kitchen test peanut sauce**: plain foods.
/// - **Kitchen test rice bowl**: a recipe of the rice alone. Its names declare
///   no allergen.
/// - **Kitchen test satay**: rice and peanut sauce. "peanut" is in the
///   peanuts word list, so it is withheld whenever peanuts are recorded.
/// - **Kitchen test oats**: a plain food, logged once on each of the three
///   logical days before today, so `PantrySuggestions` offers it (3 days in
///   14). Not today, so today's totals on every other screen are untouched.
///   The entries carry an external id per day offset, so re-applying revises
///   the same three rows rather than adding more, and its dismissal is cleared
///   so a test that dismissed it can be run again.
///
/// ## The spec
///
/// `recipes` plants the four and empties the pantry of them; `recipes,peanuts`
/// also records a peanut allergy; `recipes,noallergens` also removes it. The
/// allergen half is stated rather than left as it was, so a test that recorded
/// peanuts can put the simulator back the way the next test expects it.
public struct KitchenSeedPlan: Sendable, Hashable {
    public static let launchArgument = "-AlmanacSeedKitchen"

    public enum Allergens: Sendable, Hashable {
        /// Leave the recorded allergens as they are.
        case unchanged
        /// Record peanuts (in addition to whatever is recorded).
        case peanuts
        /// Remove peanuts (leaving any other recorded allergen alone).
        case noPeanuts
    }

    public static let riceRef = SourceIdentifier(namespace: .almanac, localID: "ui-kitchen-rice")
    public static let sauceRef = SourceIdentifier(namespace: .almanac, localID: "ui-kitchen-peanut-sauce")
    public static let bowlRef = SourceIdentifier(namespace: .almanac, localID: "ui-kitchen-rice-bowl")
    public static let satayRef = SourceIdentifier(namespace: .almanac, localID: "ui-kitchen-satay")
    public static let oatsRef = SourceIdentifier(namespace: .almanac, localID: "ui-kitchen-oats")

    public static let riceName = "Kitchen test rice"
    public static let sauceName = "Kitchen test peanut sauce"
    public static let bowlName = "Kitchen test rice bowl"
    public static let satayName = "Kitchen test satay"
    public static let oatsName = "Kitchen test oats"
    /// Logical days before today on which the oats are logged.
    public static let oatsDaysBack = [1, 2, 3]

    public let allergens: Allergens

    public init(allergens: Allergens) {
        self.allergens = allergens
    }

    /// `recipes`, optionally followed by `,peanuts` or `,noallergens`. Anything
    /// else rejects the whole spec, for the reason `VitalsSeedPlan(spec:)` gives.
    public init?(spec: String) {
        let parts = spec.trimmingCharacters(in: .whitespaces)
            .split(separator: ",").map { String($0) }
        guard parts.first == "recipes" else { return nil }
        switch parts.dropFirst().first {
        case nil where parts.count == 1: allergens = .unchanged
        case "peanuts" where parts.count == 2: allergens = .peanuts
        case "noallergens" where parts.count == 2: allergens = .noPeanuts
        default: return nil
        }
    }

    /// The plan the given launch arguments asked for, or nil if they did not ask.
    /// The only way into `apply`.
    public static func fromLaunchArguments(_ arguments: [String]) -> KitchenSeedPlan? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return KitchenSeedPlan(spec: arguments[index + 1])
    }

    /// Plants the fixture. Authoritative, not additive: re-applying leaves the
    /// same five foods, the same two recipes, the same three oats entries and
    /// none of them in the pantry, because the simulator's database is shared
    /// across runs and never reset.
    public func apply(into db: Database, now: Date = Date(),
                      timeModel: TimeModel = TimeModel(timeZone: .current)) throws {
        let editor = NutritionDishEditor(db: db)
        try editor.create(localID: Self.riceRef.localID, nameText: Self.riceName)
        try editor.create(localID: Self.sauceRef.localID, nameText: Self.sauceName)
        try editor.create(localID: Self.bowlRef.localID, nameText: Self.bowlName)
        try editor.create(localID: Self.satayRef.localID, nameText: Self.satayName)
        try editor.create(localID: Self.oatsRef.localID, nameText: Self.oatsName)
        try editor.setRecipe([DishComponent(Self.riceRef, grams: 200)], for: Self.bowlRef)
        try editor.setRecipe([DishComponent(Self.riceRef, grams: 150),
                              DishComponent(Self.sauceRef, grams: 50)], for: Self.satayRef)

        let log = NutritionLogStore(db: db, zone: ZoneContext(timeModel.timeZone))
        for back in Self.oatsDaysBack {
            var day = timeModel.logicalDay(now)
            for _ in 0..<back { day = timeModel.day(before: day) ?? day }
            // Noon on that logical day (its start is 04:00).
            guard let noon = timeModel.start(of: day)?.addingTimeInterval(8 * 3600) else { continue }
            try log.record(NutritionLogDraft(
                foodRef: Self.oatsRef, grams: 40,
                eatenAt: PartialDateTime(instant: noon, zone: ZoneContext(timeModel.timeZone, at: noon)),
                foodNameText: Self.oatsName,
                sourceSystem: "ui-seed", externalID: "ui-kitchen-oats-\(back)"))
        }
        try db.run("DELETE FROM kitchen_pantry_dismissal WHERE food_ref = ?;",
                   [.text(Self.oatsRef.description)])

        let pantry = KitchenPantry(db: db)
        for ref in [Self.riceRef, Self.sauceRef, Self.bowlRef, Self.satayRef, Self.oatsRef] {
            try pantry.remove(ref)
        }

        let profile = ProfileStore(db: db)
        switch allergens {
        case .unchanged: break
        case .peanuts: try profile.addAllergen(.peanuts)
        case .noPeanuts: try profile.removeAllergen(.peanuts)
        }
    }
}
