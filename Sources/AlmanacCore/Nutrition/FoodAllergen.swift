import Foundation

/// A food allergen, as one of the fourteen that food labelling laws name.
///
/// **These fourteen are a published list, not this app's taxonomy.** The EU
/// regime lists exactly these as the allergens that must be declared on a label,
/// and the set is the same in the UK, Canada and Australia. Taking the list from
/// there rather than inventing one means a person reading this picker recognises
/// every row, and — the reason it matters — that an app which said "Shellfish"
/// where the law says "Crustaceans" and "Molluscs" would give somebody with an
/// allergy two rows that read as one concept and a gap where a third is.
///
/// `rawValue` is the stable id stored in `food_allergen` and
/// `profile_allergen`, seeded by Migration048. It is lower snake case and is not
/// to be renamed: it is in a database on any install that has opened the app,
/// and unlike a Swift case name there is no refactoring story for a string.
///
/// **The set is closed, and this is the point of the type.** An allergen list is
/// used to withhold food from somebody. A typo in that list means either a food
/// somebody cannot eat is suggested to them, or one they can eat is hidden for no
/// reason. Both are the kind of mistake that has to be structurally impossible
/// rather than caught in review, which is what an `enum` over a `TEXT` column
/// buys and what a `[String]` does not.
public enum FoodAllergen: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case gluten
    case crustaceans
    case eggs
    case fish
    case peanuts
    case soy
    case milk
    case nuts
    case celery
    case mustard
    case sesame
    case sulphites
    case lupin
    case molluscs

    public var id: String { rawValue }

    /// The name as it appears in a picker.
    ///
    /// "Tree nuts" rather than "Nuts" for the tree-nut row. "Nuts" on its own
    /// reads as all nuts, and somebody avoiding peanuts would read a row called
    /// "Nuts" as the row that covers theirs — which is the one misreading this
    /// vocabulary most easily causes, and the reason peanuts and tree nuts are
    /// separate rows.
    public var title: String {
        switch self {
        case .gluten: return localized("Gluten / cereals")
        case .crustaceans: return localized("Crustaceans")
        case .eggs: return localized("Eggs")
        case .fish: return localized("Fish")
        case .peanuts: return localized("Peanuts")
        case .soy: return localized("Soy")
        case .milk: return localized("Milk")
        case .nuts: return localized("Tree nuts")
        case .celery: return localized("Celery")
        case .mustard: return localized("Mustard")
        case .sesame: return localized("Sesame")
        case .sulphites: return localized("Sulphites")
        case .lupin: return localized("Lupin")
        case .molluscs: return localized("Molluscs")
        }
    }

    /// A short note for somebody deciding whether a row applies to them.
    ///
    /// Every one names what is covered, because the common allergen accidents are
    /// all about a row meaning less than the person reading it assumed: soy sauce
    /// has soy and gluten, "cereals" is a third of what gluten is.
    public var guidance: String {
        switch self {
        case .gluten: return localized("Wheat, barley, rye, oats, and anything made from them.")
        case .crustaceans: return localized("Crab, lobster, prawn, shrimp, crayfish.")
        case .eggs: return localized("Egg and egg products, including mayonnaise and some batters.")
        case .fish: return localized("Any fish, including fish sauce and anchovy paste.")
        case .peanuts: return localized("Peanut oil and peanut flour included.")
        case .soy: return localized("Soy sauce, tofu, tempeh, and most meat substitutes.")
        case .milk: return localized("Milk, cheese, butter, yoghurt, cream, and casein.")
        case .nuts: return localized("Almond, cashew, walnut, hazelnut, pistachio, and their oils.")
        case .celery: return localized("Celery stalk, celery salt, and some soups and stocks.")
        case .mustard: return localized("Mustard seed, powder, and most mustards.")
        case .sesame: return localized("Sesame seed, oil, tahini, and hummus.")
        case .sulphites: return localized("Preservatives above 10 mg/kg. Common in wine and dried fruit.")
        case .lupin: return localized("Lupin flour, and some bakery and gluten-free products.")
        case .molluscs: return localized("Squid, octopus, clams, mussels, snails, scallops.")
        }
    }
}

public extension FoodAllergen {
    /// Whether a food name names this allergen.
    ///
    /// Folds its own input rather than trusting the caller to have done it.
    /// Folding is idempotent, so the search path pays nothing for it, and the
    /// alternative is a method whose parameter name is a promise — the kind of
    /// promise that is honoured at one call site and forgotten at the next, and
    /// the failure is silent: an unfolded name simply matches fewer words, so a
    /// peanut allergy quietly stops filtering.
    func matches(_ name: String) -> Bool {
        let folded = TextFold.fold(name)
        return FoodAllergen.nameWords[self, default: []].contains { folded.contains($0) }
    }

    /// The folded words that name this allergen in a food's name.
    ///
    /// ## How these lists are tuned
    ///
    /// The lists are deliberately **wider than the allergen**, because the two
    /// mistakes do not cost the same. A word that catches a food somebody cannot
    /// eat produces a result they do not see, and they can see why. A missing
    /// word produces a food somebody *can* be harmed by, and they cannot tell.
    ///
    /// So the direction is over-inclusion — `cream` catches "cream soda", and
    /// `butter` catches "almond butter" — and the tests pin those cases rather
    /// than pretending they do not happen.
    ///
    /// The exceptions are words that appear inside **other** words, where
    /// over-inclusion stops being a false positive and becomes a wrong answer
    /// about a food with nothing to do with the allergen: `oat` inside "g**oat**",
    /// `bran` inside "b**ran**ch", and `tongue` in "beef tongue". Those are the
    /// three words this table was wrong about first, and each has a test.
    ///
    /// Multi-word entries work because `TextFold` collapses runs of whitespace to
    /// a single space and folds punctuation to spaces too, so "Soy  Sauce" and
    /// "Soy, Sauce" are both the single string "soy sauce".
    static let nameWords: [FoodAllergen: [String]] = [
        .gluten: ["gluten", "wheat", "barley", "rye", "oats", "oatmeal", "bread",
                  "pasta", "semolina", "spaghetti", "linguine", "couscous", "bulgur",
                  "farro", "malt", "flour", "seitan", "batter", "crouton", "soy sauce"],
        .crustaceans: ["crustacean", "shrimp", "prawn", "crab", "lobster", "crayfish",
                       "crawfish", "nauvis", "langoustine"],
        .eggs: ["egg", "mayonnaise", "mayo", "meringue", "omelette", "omelet", "frittata"],
        .fish: ["fish", "salmon", "tuna", "cod", "haddock", "mackerel", "sardine",
                "anchov", "trout", "herring", "bass", "hake", "monkfish", "halibut",
                "worcestershire", "roe", "caviar", "seafood"],
        .peanuts: ["peanut", "groundnut", "monkey nut", "arachis"],
        .soy: ["soy", "soya", "tofu", "tempeh", "edamame", "miso", "natto",
               "textured vegetable"],
        .milk: ["milk", "cheese", "cheddar", "mozzarella", "parmesan", "butter",
                "yoghurt", "yogurt", "cream", "casein", "lactose", "whey", "custard",
                "brie", "ricotta", "mascarpone", "halloumi"],
        .nuts: ["almond", "cashew", "walnut", "hazelnut", "pistachio", "pecan",
                "brazil nut", "macadamia", "praline", "marzipan", "frangipane", "nutella"],
        .celery: ["celery"],
        .mustard: ["mustard"],
        .sesame: ["sesame", "tahini", "hummus", "benne", "gingelly"],
        .sulphites: ["sulphite", "sulfite", "metabisulphite", "metabisulfite",
                     "sulphur dioxide", "e220", "e221", "e222", "e223", "e224",
                     "e226", "e227", "e228"],
        .lupin: ["lupin"],
        .molluscs: ["mollusc", "mollusk", "squid", "octopus", "calamari", "clam",
                    "mussel", "snail", "scallop", "oyster", "whelk", "cockle", "escargot"]
    ]

    /// The position in the picker's list, mirroring `food_allergen.sort_order`.
    ///
    /// Duplicated as a literal rather than read from the database so the ordering
    /// is a property of the type and testable without a row existing — and so a
    /// `sort_order` that drifted from the enum would fail a test rather than
    /// silently reorder a picker. Migration048 seeds the same order.
    var sortIndex: Int {
        switch self {
        case .gluten: return 1
        case .crustaceans: return 2
        case .eggs: return 3
        case .fish: return 4
        case .peanuts: return 5
        case .soy: return 6
        case .milk: return 7
        case .nuts: return 8
        case .celery: return 9
        case .mustard: return 10
        case .sesame: return 11
        case .sulphites: return 12
        case .lupin: return 13
        case .molluscs: return 14
        }
    }

    /// Every allergen, in picker order.
    static var inPickerOrder: [FoodAllergen] {
        allCases.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// What the app can honestly say about a food and a person's allergens.
///
/// **Three states, because two is the design flaw here.** The tempting shape is
/// "safe / not safe", and the reason it is wrong is that the two states are not
/// symmetric: "this food contains peanut" is a claim the app can back, and "this
/// food is safe for you" is a claim it cannot. Producing the second one from a
/// name match would be the app certifying somebody's food safety off a string
/// comparison — and if it were wrong, nothing in the app would let them find out.
///
/// So the states are separated by *what they are evidence of*:
///
/// - `.declares` — the food's name names the allergen. Evidence the food contains
///   it. The strongest thing the app can say.
/// - `.noDeclaration` — the food's name is silent about the allergen. **Not
///   evidence of safety.** The absence of a word in a name is not the absence of
///   the allergen.
/// - `.notApplicable` — no allergens recorded, so the question is not being asked.
///
/// The name is `noDeclaration` rather than `safe` on purpose: the word does the
/// work of not being a promise.
public struct AllergenVerdict: Sendable, Hashable {
    /// The allergens the food's name names.
    public let declared: Set<FoodAllergen>
    /// What the app concludes.
    public let status: Status

    public enum Status: Sendable, Hashable {
        /// The name names at least one of this person's allergens.
        case declares
        /// The name names none of them. Not a statement that the food is safe.
        case noDeclaration
        /// No allergens recorded, so nothing is filtered.
        case notApplicable
    }

    public init(declared: Set<FoodAllergen> = [], status: Status) {
        self.declared = declared
        self.status = status
    }

    /// The verdict for a food name, against this person's allergens.
    public static func forFood(named name: String, personAllergens: Set<FoodAllergen>) -> AllergenVerdict {
        guard !personAllergens.isEmpty else {
            return AllergenVerdict(status: .notApplicable)
        }
        var declared: Set<FoodAllergen> = []
        for allergen in personAllergens where allergen.matches(name) {
            declared.insert(allergen)
        }
        return AllergenVerdict(declared: declared,
                               status: declared.isEmpty ? .noDeclaration : .declares)
    }

    /// Whether the food's name names this allergen.
    public func declares(_ allergen: FoodAllergen) -> Bool {
        declared.contains(allergen)
    }

    /// One line naming the allergens this food's name declared, or `nil`.
    ///
    /// Lives here rather than in the search screen so the sentence is tested
    /// beside the matching rule it explains, and so a screen cannot describe a
    /// removal more confidently than `matches` actually matched.
    ///
    /// **Sorted, not set order.** `Set` iteration order is stable within a
    /// process but not across runs, so an unsorted join produces a reason that
    /// reads "Milk, Peanuts, Gluten / cereals" on one launch and a different
    /// order on the next. This is a sentence a person compares against a shopping
    /// list.
    ///
    /// **Titles verbatim, not lower-cased.** Lower-casing reads better for a
    /// single word but mangles the ones that are not single words: `.gluten`'s
    /// title is "Gluten / cereals", and "gluten / cereals" reads as a typo while
    /// "Gluten / cereals" reads as the allergen the labelling laws name. So the
    /// sentence is "Names Milk and Peanuts" — slightly formal, and always exactly
    /// the string the picker shows the user when they recorded it.
    public var reason: String? {
        guard !declared.isEmpty else { return nil }
        // "Peanuts and Milk", "Peanuts, Milk and Soy": what reads as a list at a
        // glance, in either language (`localizedList`).
        return localized("Names %@", localizedList(declared.map(\.title).sorted()))
    }

    /// Whether the food should be withheld from a search a person is looking at.
    ///
    /// The decision the app was asked for: a hard filter, so a food that declares
    /// one of somebody's allergens does not appear in their results at all. It is
    /// the *only* thing this type ever withholds — `.noDeclaration` results stay,
    /// because the alternative is a search that returns almost nothing for most
    /// people and all of it is a guess about what is safe.
    public var isFilteredOut: Bool {
        status == .declares
    }
}

/// What the filter actually did to a result set, for the screen to state plainly.
///
/// **This type exists because the hard filter is easy to over-claim.** The filter
/// catches foods whose *name* names an allergen. It cannot see ingredients, so a
/// result set full of `.noDeclaration` foods is not a set of verified-safe foods,
/// and a screen that says "Filtered for your allergies" over one is making a
/// safety claim the app cannot support. So the search reports what it did, and
/// the screen shows that rather than a reassuring adjective.
public struct AllergenFilterEffect: Sendable, Hashable {
    /// How many foods were withheld.
    public let removed: Int
    /// How many survived.
    public let kept: Int
    /// The allergens that caused a removal, so the screen can name them.
    public let triggeredBy: Set<FoodAllergen>

    public init(removed: Int = 0, kept: Int = 0, triggeredBy: Set<FoodAllergen> = []) {
        self.removed = removed
        self.kept = kept
        self.triggeredBy = triggeredBy
    }

    /// Whether the filter actually withheld anything.
    ///
    /// `removed > 0`, not `!triggeredBy.isEmpty`. The two looked interchangeable —
    /// the catalog only ever puts an allergen in `triggeredBy` when it removed a
    /// food — but they disagree on a hand-built value, and then a screen says
    /// "Hidden 0 foods naming Peanuts", which is a sentence that should not exist.
    ///
    /// Note this is *not* the same question as "does the person have allergens".
    /// Somebody with a peanut allergy who searched "apple" has removed nothing,
    /// and the screen still owes them the disclaimer — which is why that check
    /// lives on `NutritionFoodSearchResults`, against the allergen set, and not
    /// here.
    public var isActive: Bool { removed > 0 }

    /// The one-line explanation a search screen shows.
    ///
    /// Says what was withheld and by what. When nothing was withheld it says
    /// nothing, because "no foods matched your allergies" reads as a safety
    /// statement and this is not one.
    public var explanation: String? {
        guard isActive else { return nil }
        // A spoken list, because this is prose somebody may hear read aloud by
        // VoiceOver, and "gluten, milk and, soy" is what a naive join produces.
        let list = localizedList(triggeredBy.sorted { $0.sortIndex < $1.sortIndex }.map(\.title))
        return removed == 1
            ? localized("Hidden 1 food naming %@.", list)
            : localized("Hidden %@ foods naming %@.", String(removed), list)
    }
}
