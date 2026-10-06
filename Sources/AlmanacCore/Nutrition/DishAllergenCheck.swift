import Foundation

/// One `almanac:` dish judged against the person's allergens.
public struct DishAllergenJudgement: Sendable, Hashable {
    public let ref: SourceIdentifier
    public let verdict: AllergenVerdict
    /// The names under the dish that declared an allergen — the dish's own, or
    /// an ingredient's, through nested dishes — sorted. Empty unless `verdict`
    /// declares. Lets the warning say *where* the allergen was found.
    public let foundIn: [String]

    public init(ref: SourceIdentifier, verdict: AllergenVerdict, foundIn: [String] = []) {
        self.ref = ref
        self.verdict = verdict
        self.foundIn = foundIn
    }

    /// Whether the dish is hidden by default.
    public var isHidden: Bool { verdict.isFilteredOut }

    /// The warning shown on the dish's own page once it has been opened from
    /// the hidden list. Nil when nothing was declared.
    ///
    /// Names the allergen by its recorded title, the way `AllergenVerdict.reason`
    /// does, and says where it was found. It does not say "contains": the check
    /// reads names, and a name naming peanuts is what was found.
    public var warning: String? {
        guard verdict.isFilteredOut else { return nil }
        let titles = verdict.declared.sorted { $0.sortIndex < $1.sortIndex }.map(\.title)
        let list = titles.count == 1
            ? titles[0]
            : titles.dropLast().joined(separator: ", ") + " and " + titles[titles.count - 1]
        var text = "Allergen warning: this names \(list), which you have recorded as an allergen."
        if !foundIn.isEmpty {
            text += " Found in: \(foundIn.joined(separator: ", "))."
        }
        return text
    }
}

/// Items split by the allergen check: shown, and hidden with their judgement.
public struct AllergenPartition<Item: Sendable & Hashable>: Sendable, Hashable {
    public struct Hidden: Sendable, Hashable {
        public let item: Item
        public let judgement: DishAllergenJudgement
    }

    public let shown: [Item]
    public let hidden: [Hidden]
    /// The allergens the check ran against. Empty means nothing was checked.
    public let allergens: Set<FoodAllergen>

    public init(shown: [Item] = [], hidden: [Hidden] = [], allergens: Set<FoodAllergen> = []) {
        self.shown = shown
        self.hidden = hidden
        self.allergens = allergens
    }
}

/// **The** allergen check for Almanac's own dishes.
///
/// A Kitchen recipe and a saved meal are the same row — an `almanac:` dish — so
/// they are checked by one implementation, and the owner's rule (2026-10-06,
/// "same rule everywhere") is enforced by there being nowhere else to put a
/// second one. `RecipeFinder` and `SavedMeals` both call `judge`.
///
/// The rule is the food search's: a dish is hidden when a name under it
/// declares one of the person's allergens — its own name, or any ingredient's,
/// through nested dishes. Everything else is `.noDeclaration`, which is not a
/// safety claim. What differs from food search is what "hidden" means on screen:
/// a hidden dish can still be opened, on its own page, under a warning.
///
/// The person's allergens are a parameter, as for `NutritionCatalog.search`.
/// Reading them is the caller's job, and a failed read must reach the screen as
/// an error rather than as an empty set (`NutritionModel`).
public struct DishAllergenCheck: Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// One judgement per dish in `dishes`. With no allergens recorded every
    /// dish is `.notApplicable` and nothing is read.
    public func judge(_ dishes: [SourceIdentifier],
                      allergens: Set<FoodAllergen>) throws -> [SourceIdentifier: DishAllergenJudgement] {
        guard !allergens.isEmpty else {
            return Dictionary(uniqueKeysWithValues: Set(dishes).map {
                ($0, DishAllergenJudgement(ref: $0, verdict: AllergenVerdict(status: .notApplicable)))
            })
        }
        let names = try namesUnder(dishes)
        var result: [SourceIdentifier: DishAllergenJudgement] = [:]
        for dish in Set(dishes) {
            var declared: Set<FoodAllergen> = []
            var foundIn: Set<String> = []
            for name in names[dish] ?? [] {
                let verdict = AllergenVerdict.forFood(named: name, personAllergens: allergens)
                if verdict.isFilteredOut {
                    declared.formUnion(verdict.declared)
                    foundIn.insert(name)
                }
            }
            result[dish] = DishAllergenJudgement(
                ref: dish,
                verdict: AllergenVerdict(declared: declared, status: declared.isEmpty ? .noDeclaration : .declares),
                foundIn: foundIn.sorted())
        }
        return result
    }

    /// Splits `items` into shown and hidden, keeping each half in the order given.
    public func partition<Item: Sendable & Hashable>(
        _ items: [Item], ref: (Item) -> SourceIdentifier,
        allergens: Set<FoodAllergen>
    ) throws -> AllergenPartition<Item> {
        let judged = try judge(items.map(ref), allergens: allergens)
        var shown: [Item] = []
        var hidden: [AllergenPartition<Item>.Hidden] = []
        for item in items {
            if let judgement = judged[ref(item)], judgement.isHidden {
                hidden.append(.init(item: item, judgement: judgement))
            } else {
                shown.append(item)
            }
        }
        return AllergenPartition(shown: shown, hidden: hidden, allergens: allergens)
    }

    /// The disclaimer a dish list owes whenever allergens are recorded, whether
    /// or not anything was hidden. `noun` is what the screen calls a dish.
    public static func disclaimer(noun: String, allergens: Set<FoodAllergen>) -> String? {
        guard !allergens.isEmpty else { return nil }
        return "Checked \(noun) and ingredient names only — a name can be silent about an allergen, so Almanac cannot confirm a \(noun) is allergen-free."
    }

    /// Every primary name under each dish: its own, its ingredients', and theirs
    /// where an ingredient is itself a dish. `UNION` rather than `UNION ALL`, so
    /// a cycle already in the data ends instead of recursing — `setRecipe`
    /// refuses to create one, and this does not rely on it.
    private func namesUnder(_ dishes: [SourceIdentifier]) throws -> [SourceIdentifier: [String]] {
        guard !dishes.isEmpty else { return [:] }
        let json = String(decoding: try JSONEncoder().encode(Set(dishes).map(\.description).sorted()),
                          as: UTF8.self)
        var names: [SourceIdentifier: [String]] = [:]
        for row in try db.query("""
            WITH RECURSIVE part(root, ref) AS (
                SELECT value, value FROM json_each(?)
                UNION
                SELECT part.root, c.component_ref
                FROM part JOIN nutrition_dish_component c ON c.dish_ref = part.ref
            )
            SELECT part.root, n.name FROM part
            JOIN nutrition_food_name n ON n.food_ref = part.ref AND n.is_primary = 1;
            """, [.text(json)]) {
            guard let root = row.string("root").flatMap(SourceIdentifier.init(parsing:)),
                  let name = row.string("name") else { continue }
            names[root, default: []].append(name)
        }
        return names
    }
}
