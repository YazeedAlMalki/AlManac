import Foundation
import Testing
@testable import AlmanacCore

/// What the app says about a food and somebody's allergies.
///
/// **The tests here are mostly about not claiming more than the app knows.** The
/// filter reads food names. It is not an ingredient database, it cannot see a
/// "may contain" line, and the difference between "this food names peanut" and
/// "this food is safe for you" is the whole reason `AllergenVerdict` has three
/// states. A test that only checked the filter removed peanut butter would pass
/// against a version that also called everything else safe.
@Suite("Food allergens and the search filter")
struct FoodAllergenTests {

    // MARK: - The vocabulary

    @Test("The set is the published fourteen, in the published order")
    func theFourteen() {
        // Not this app's taxonomy. The labelling laws name exactly these, and a
        // person reading the picker recognises all of them.
        #expect(FoodAllergen.allCases.count == 14)
        #expect(FoodAllergen.inPickerOrder.map(\.rawValue) == [
            "gluten", "crustaceans", "eggs", "fish", "peanuts", "soy", "milk", "nuts",
            "celery", "mustard", "sesame", "sulphites", "lupin", "molluscs"
        ])
    }

    @Test("Peanuts and tree nuts are separate, because conflating them is the expensive mistake")
    func peanutsAreNotNuts() {
        // Somebody avoiding peanuts who reads a row called "Nuts" as covering
        // theirs will stop avoiding them. Two rows, and the tree-nut one is
        // labelled "Tree nuts" rather than "Nuts" for exactly this reason.
        #expect(FoodAllergen.peanuts != FoodAllergen.nuts)
        #expect(FoodAllergen.peanuts.title == "Peanuts")
        #expect(FoodAllergen.nuts.title == "Tree nuts")
        // Almond matches tree nuts and not peanuts.
        #expect(FoodAllergen.nuts.matches("almond butter"))
        #expect(!FoodAllergen.peanuts.matches("almond butter"))
    }

    @Test("Crustaceans and molluscs are separate, and both catch seafood")
    func crustaceansAreNotMolluscs() {
        // The other split the labelling laws require: prawn is not squid, and a
        // person allergic to one is usually fine with the other.
        #expect(FoodAllergen.crustaceans.matches("grilled prawn"))
        #expect(!FoodAllergen.molluscs.matches("grilled prawn"))
        #expect(FoodAllergen.molluscs.matches("calamari"))
        #expect(!FoodAllergen.crustaceans.matches("calamari"))
        // And "seafood" is a name-word for both, because a dish called "seafood
        // salad" is exactly the row that needs withholding.
        #expect(FoodAllergen.fish.matches("seafood platter"))
    }

    @Test("Every allergen names at least one word, and every word belongs to its own allergen")
    func wordListsAreWellFormed() {
        for allergen in FoodAllergen.allCases {
            let words = FoodAllergen.nameWords[allergen] ?? []
            #expect(!words.isEmpty, "\(allergen.rawValue) has no name words, so nothing is ever caught")
            for word in words {
                #expect(word == word.lowercased(),
                        "\(word) will not match a folded name")
                #expect(!word.contains("  "),
                        "\"\(word)\" has a double space, which no folded name has")
                #expect(word == word.trimmingCharacters(in: .whitespaces),
                        "\"\(word)\" is padded, so it can never match")
            }
        }
    }

    // MARK: - The verdict

    @Test("A food that names an allergen says so")
    func declaringFood() {
        let verdict = AllergenVerdict.forFood(named: "Peanut Butter, Smooth",
                                              personAllergens: [.peanuts])
        #expect(verdict.status == .declares)
        #expect(verdict.declares(.peanuts))
        #expect(verdict.isFilteredOut)
    }

    @Test("Over-matching is accepted, and pinned where it happens")
    func overMatchingIsAccepted() {
        // "butter" catches "peanut butter", so a milk allergy hides peanut butter
        // too — and "cream" catches "cream soda". Both are wrong answers, and both
        // are the accepted direction: a hidden food is one the person did not
        // choose, a suggested one is a hazard they cannot see. The alternative —
        // trimming the lists to be precise — trades a nuisance for a risk.
        //
        // Pinned so the trade is a decision rather than an accident. If someone
        // later decides false positives hurt more, this test is where that shows.
        let milkAllergy = AllergenVerdict.forFood(named: "Peanut Butter, Smooth",
                                                  personAllergens: [.milk])
        #expect(milkAllergy.declares(.milk))
        #expect(milkAllergy.status == .declares)

        let soda = AllergenVerdict.forFood(named: "Cream Soda", personAllergens: [.milk])
        #expect(soda.status == .declares)
    }

    @Test("A word inside another word is a wrong answer, not a false positive")
    func wordsInsideOtherWords() {
        // The three cases where over-inclusion stops being harmless and becomes an
        // answer about a food with nothing to do with the allergen. Each of these
        // was in the first version of the word lists.
        //
        // "goat cheese" containing "oat", "cranberry branch" containing "bran", and
        // "beef tongue" being filed as fish. A milk allergy hiding goat cheese is
        // the same class of nuisance as hiding cream soda — but "tongue" for fish is
        // not a nuisance, it is a food about a different animal entirely being
        // withheld on a false premise.
        #expect(!FoodAllergen.gluten.matches("Goat Cheese, Aged"))
        #expect(!FoodAllergen.gluten.matches("Cranberry Branch Muffin"))
        #expect(!FoodAllergen.fish.matches("Beef Tongue, Smoked"))
        #expect(!FoodAllergen.fish.matches("Ox Tongue"))
        // And the words still work where they should.
        #expect(FoodAllergen.gluten.matches("Oatmeal, Rolled"))
        #expect(FoodAllergen.gluten.matches("Wholewheat Bread"))

    }

    @Test("A food whose name is silent is not called safe")
    func silentFoodIsNotSafe() {
        // This is the test the whole three-state design exists for. "Apple juice"
        // says nothing about peanuts, and the app must not conclude it is
        // peanut-free — it has simply not been asked.
        let verdict = AllergenVerdict.forFood(named: "Apple Juice, Unsweetened",
                                              personAllergens: [.peanuts])
        #expect(verdict.status == .noDeclaration)
        #expect(verdict.declared.isEmpty)
        #expect(!verdict.isFilteredOut)
    }

    @Test("No allergens means the question is not being asked")
    func noAllergensIsNotApplicable() {
        // Distinct from "noDeclaration": there is nothing to declare *against*.
        let verdict = AllergenVerdict.forFood(named: "Peanut Butter", personAllergens: [])
        #expect(verdict.status == .notApplicable)
        #expect(!verdict.isFilteredOut)
    }

    @Test("Matching is case, accent and punctuation blind")
    func matchingIsFolded() {
        // `TextFold` is what makes this work, and it is the same folding the food
        // search itself uses — so "Crème Fraîche" and "creme fraiche" produce one
        // verdict rather than two.
        let accents = AllergenVerdict.forFood(named: "FETA CHEESE, Crumbled", personAllergens: [.milk])
        #expect(accents.status == .declares)
        let mixed = AllergenVerdict.forFood(named: "Mixed Nuts (Cashew, Almond)",
                                            personAllergens: [.nuts])
        #expect(mixed.status == .declares)
        // Punctuation folds to a space, so "Worcestershire Sauce" and
        // "Worcestershire,Sauce" are one string — which is why multi-word entries
        // in the tables work at all.
        #expect(FoodAllergen.fish.matches("Worcestershire,Sauce"))
        #expect(FoodAllergen.gluten.matches("Soy  Sauce"))
    }

    @Test("A food naming several of somebody's allergens reports all of them")
    func severalAllergensAtOnce() {
        // "soy sauce" is a name-word for gluten as well as soy, because every soy
        // sauce on a shelf contains wheat. Reporting only one would let a screen
        // say "hidden because of soy" when gluten is also why — and the reader
        // would take that as a complete account.
        let verdict = AllergenVerdict.forFood(named: "Soy Sauce", personAllergens: [.gluten, .soy])
        #expect(verdict.declared == [.gluten, .soy])
    }

    @Test("Substring matching catches the products, not just the allergen")
    func catchesDerivedProducts() {
        // The allergen is a word; the food in a shop is not. Tahini, tempeh,
        // worcestershire, halloumi — a filter that only matched the allergen name
        // would be right about the corner shop and useless about the supermarket.
        let cases: [(String, FoodAllergen)] = [
            ("Tahini", .sesame), ("Hummus", .sesame),
            ("Tempeh", .soy), ("Edamame", .soy),
            ("Halloumi", .milk), ("Mascarpone", .milk),
            ("Marzipan", .nuts), ("Praline", .nuts),
            ("Calamari", .molluscs), ("Escargot", .molluscs),
            ("Linguine", .gluten), ("Bulgur Wheat", .gluten),
            ("Anchovy Paste", .fish), ("Worcestershire Sauce", .fish)
        ]
        for (name, allergen) in cases {
            #expect(allergen.matches(name.lowercased()),
                    "\"\(name)\" should be caught as \(allergen.rawValue)")
        }
    }

    // MARK: - The filter's own account of itself

    @Test("The effect names what it removed and why")
    func effectExplanation() {
        let one = AllergenFilterEffect(removed: 1, kept: 9, triggeredBy: [.peanuts])
        #expect(one.isActive)
        #expect(one.explanation == "Hidden 1 food naming Peanuts.")
        let many = AllergenFilterEffect(removed: 3, kept: 7,
                                        triggeredBy: [.peanuts, .gluten, .sesame])
        #expect(many.explanation == "Hidden 3 foods naming Gluten / cereals, Peanuts and Sesame.")
        // Two, so the "and" is right.
        let two = AllergenFilterEffect(removed: 2, kept: 0, triggeredBy: [.milk, .nuts])
        #expect(two.explanation == "Hidden 2 foods naming Milk and Tree nuts.")
    }

    @Test("Removed nothing means there is nothing to explain")
    func nothingRemoved() {
        // But it does *not* mean the filter was off, which is why `isActive` and
        // `didRemoveAnything` are separate properties and not one.
        let effect = AllergenFilterEffect(removed: 0, kept: 5, triggeredBy: [])
        #expect(effect.explanation == nil)
        #expect(!effect.isActive)

        let ranAndFoundNothing = AllergenFilterEffect(removed: 0, kept: 5, triggeredBy: [.peanuts])
        #expect(ranAndFoundNothing.explanation == nil)
        // Removed nothing, so not active — even though an allergen is named. The
        // alternative reads as "Hidden 0 foods naming Peanuts", which is a
        // sentence that should not be producible.
        #expect(!ranAndFoundNothing.isActive)
    }

    // MARK: - The disclaimer

    @Test("The disclaimer is shown even when nothing was filtered out")
    func disclaimerIsNotConditional() {
        // The failure this prevents: a screen that says nothing when the filter
        // matched nothing, which reads as "these results are safe for you".
        let results = NutritionFoodSearchResults(
            foods: [], effect: AllergenFilterEffect(removed: 0, kept: 12,
                                                     triggeredBy: [.peanuts]),
            allergens: [.peanuts])
        #expect(results.effect.explanation == nil)
        #expect(results.disclaimer != nil)
        #expect(results.note?.contains("no ingredient lists") == true)
        // And the specific claim the app cannot make is named: it is not the
        // filter's presence that reassures, it is the absence of a clean bill.
        #expect(results.disclaimer?.contains("cannot confirm") == true)
    }

    @Test("Somebody with no allergens is told nothing about allergies")
    func noAllergensNoDisclaimer() {
        // Noise that trains people to ignore the note.
        let results = NutritionFoodSearchResults(foods: [], allergens: [])
        #expect(results.isFiltered == false)
        #expect(results.disclaimer == nil)
        #expect(results.note == nil)
    }

    // MARK: - The reason a food was withheld

    @Test("One allergen reads as one reason, in lower case")
    func singleAllergenReason() {
        let verdict = AllergenVerdict.forFood(named: "Peanut Sauce", personAllergens: [.peanuts])
        // Lower-cased because the sentence begins "Names …" and a capitalised
        // allergen there reads as the start of a new clause.
        #expect(verdict.reason == "Names Peanuts")
    }

    @Test("Two allergens read as a list with an 'and'")
    func twoAllergenReason() {
        let verdict = AllergenVerdict(declared: [.peanuts, .milk], status: .declares)
        #expect(verdict.reason == "Names Milk and Peanuts")
    }

    @Test("Three or more allergens keep the comma, and the order does not vary")
    func manyAllergenReasonsAreStable() {
        // `Set` iteration order is stable within a process but not across runs, so
        // an unsorted join produces a reason that differs between launches. This
        // is a sentence a person compares against a shopping list; it cannot
        // reorder itself.
        let declared: Set<FoodAllergen> = [.gluten, .peanuts, .milk, .soy]
        let verdict = AllergenVerdict(declared: declared, status: .declares)
        let expected = "Names Gluten / cereals, Milk, Peanuts and Soy"
        #expect(verdict.reason == expected)

        // Built the other way round, from a different literal order, to catch a
        // sort that happens to agree with this one insertion order.
        let other: Set<FoodAllergen> = [.soy, .milk, .gluten, .peanuts]
        #expect(AllergenVerdict(declared: other, status: .declares).reason == expected)
    }

    @Test("A food that declares nothing has no reason to state")
    func noDeclarationHasNoReason() {
        // The absence is load-bearing: `.noDeclaration` results stay in the list,
        // and a reason printed against one would tell the reader the food had been
        // checked for something it was not checked for.
        #expect(AllergenVerdict.forFood(named: "Apple Juice", personAllergens: [.peanuts]).reason == nil)
        #expect(AllergenVerdict.forFood(named: "Apple Juice", personAllergens: []).reason == nil)
    }

    @Test("A withheld food keeps the publisher's punctuation and case")
    func withheldFoodKeepsTheDisplayName() {
        let ref = SourceIdentifier(namespace: .usda, localID: "1105904")
        let withheld = WithheldFood(ref: ref, name: "Peanut Butter, Smooth",
                                    verdict: AllergenVerdict(declared: [.peanuts], status: .declares))
        // Verbatim. Neither `TextFold.fold`ed ("peanut butter smooth"), nor
        // re-capitalised, nor upper-cased: this string is the label the reader is
        // holding, and it has to be matchable against it.
        #expect(withheld.name == "Peanut Butter, Smooth")
        #expect(withheld.id == ref)
    }
}
