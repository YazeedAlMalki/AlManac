import Foundation

/// One food-search response, and what the allergen filter did to it.
///
/// ## Why search returns this rather than `[NutritionFood]`
///
/// A hard filter that only removes things is a lie by omission. Somebody with a
/// peanut allergy searches "satay", sees no peanut sauce in the results, and
/// concludes the app checked. It did not — it matched a food's *name* against a
/// word list. So the search has to hand back three things rather than one: what
/// is shown, what was withheld and why, and whether there is any caveat at all.
///
/// None of it is a `Bool`. `didFilter` cannot distinguish "your allergies
/// matched nothing" from "you have no allergies", and those are very different
/// things to tell somebody: the first means the filter ran and found nothing, the
/// second means the filter did not run. `allergens` being empty is how the screen
/// knows which sentence to use.
///
/// ## What `blocked` is for
///
/// Showing a person what was hidden, and why, is the difference between a filter
/// they trust and one they work around. A food they can see being withheld for a
/// reason they recognise is a filter they believe; a food that silently vanishes
/// is one they conclude is broken. `NutritionFoodSearchResults.blocked` is that
/// list — **not** a way to add the food back. There is no override, and its
/// absence is deliberate: an override on a hard allergen filter is a checkbox
/// that says "click this if you would like to be shown something that may kill
/// you", and no such affordance should be added without the user asking for it by
/// name.
public struct NutritionFoodSearchResults: Sendable, Hashable {
    /// The foods to show, in catalog order.
    public let foods: [NutritionFood]
    /// Per-food verdict, keyed by ref. A missing entry means no food at that ref
    /// survived, or the caller built this without verdicts.
    public let verdicts: [SourceIdentifier: AllergenVerdict]
    /// Withheld foods and the allergens their names declared.
    public let blocked: [SourceIdentifier: AllergenVerdict]
    /// The counts and triggers, for the screen's own sentence.
    public let effect: AllergenFilterEffect
    /// Whether the SQL `LIMIT` was reached, so there may be matches beyond it.
    ///
    /// Distinct from "there are no more results": a search for "oil" returns the
    /// first 50 by name order and the filter then removes some of them, so the
    /// list is short *and* truncated and the two need saying separately. Without
    /// this a short list reads as complete, and somebody searching "coconut" is
    /// told there are no coconut milks when there are forty past the limit.
    public let hitTheLimit: Bool
    /// The allergens this search was filtered against.
    public let allergens: Set<FoodAllergen>

    public init(foods: [NutritionFood] = [],
                verdicts: [SourceIdentifier: AllergenVerdict] = [:],
                blocked: [SourceIdentifier: AllergenVerdict] = [:],
                effect: AllergenFilterEffect = AllergenFilterEffect(),
                hitTheLimit: Bool = false,
                allergens: Set<FoodAllergen> = []) {
        self.foods = foods
        self.verdicts = verdicts
        self.blocked = blocked
        self.effect = effect
        self.hitTheLimit = hitTheLimit
        self.allergens = allergens
    }

    /// Whether the allergen filter is in force at all.
    ///
    /// False means every result here is exactly what an unfiltered search would
    /// return, and the screen should not mention allergies — showing an allergy
    /// note to somebody with no allergies is noise that trains people to ignore
    /// the note.
    public var isFiltered: Bool { !allergens.isEmpty }

    /// The sentence a search screen owes somebody who has allergens recorded.
    ///
    /// **Present whether or not anything was removed.** This is the part that
    /// makes the filter honest: the filter only reads food names, so "no results
    /// mention your allergens" is not "these results are safe for you". Returning
    /// `nil` when `effect.removed == 0` would let the screen go quiet in exactly
    /// the case where a quiet screen reads as a clean bill of health.
    public var disclaimer: String? {
        guard isFiltered else { return nil }
        return "Checked food names only — Almanac has no ingredient lists, so it cannot confirm a food is allergen-free."
    }

    /// The one line above or below the results, or `nil` when there is nothing
    /// worth saying.
    ///
    /// Both halves can be present at once and both are load-bearing: the counts
    /// say what the filter did, the disclaimer says what it cannot do.
    public var note: String? {
        let parts = [effect.explanation, disclaimer].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The verdict for a food, or `.notApplicable` when there is none.
    public func verdict(for ref: SourceIdentifier) -> AllergenVerdict {
        verdicts[ref] ?? AllergenVerdict(status: .notApplicable)
    }
}
