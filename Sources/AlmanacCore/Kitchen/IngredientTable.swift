import Foundation

/// Turns a catalog food name into the key of the ingredient it is, or nil when
/// the food must stay an ingredient of its own.
///
/// ## The merge rule (unconfirmed — `CONTEXT.md`, Kitchen 2026-10-06)
///
/// Two foods are the same ingredient when their names agree once **how they
/// were prepared** is set aside:
///
/// 1. **Composition guard.** A name containing a word that says something was
///    *added* — coated, breaded, battered, sauce, stuffed, marinated, glazed,
///    filled, nuggets, ready meal, and the rest of `composition` — gets no key at
///    all. "Chicken breast, breaded" is not chicken breast with a cooking method;
///    it is chicken breast plus a coating, and the coating is where an egg or a
///    gluten allergen would be. It is never merged with anything.
/// 2. **Preparation set aside.** Cooking and storage words (raw, roasted, boiled,
///    grilled, frozen, organic, …) and cut-and-skin qualifiers ("meat only",
///    "without skin", "lean flesh", "no added fat", …) are dropped.
/// 3. **Form kept.** Words that change what the thing *is* in a kitchen — dried,
///    canned, smoked, salted, juice, powder — are kept, so dried apricots merge
///    with dried apricots and never with fresh ones.
/// 4. What remains, folded, singularised ("eggs" → "egg"), stop words removed
///    and duplicates dropped, in name order, is the key.
///
/// So "Chicken breast, raw" and "Chicken breast, roasted" are `chicken breast`;
/// "Chicken breast, breaded, fried" is nothing. Measured on the shipped lake
/// (2026-10-06): 8,354 foods → 5,816 keys; 871 keys hold more than one food and
/// 251 span more than one source; 1,184 foods are held back by the guard.
public enum IngredientNormaliser {
    /// Words that mean something was added. A name with one never merges.
    static let composition: Set<String> = [
        "coated", "breaded", "battered", "batter", "crumbed", "crumb", "crumbs",
        "breadcrumb", "breadcrumbs", "sauce", "gravy", "stuffed", "stuffing",
        "marinated", "marinade", "glazed", "filled", "nugget", "nuggets", "kiev",
        "dressing", "dressed", "topped", "topping", "ready", "meal", "dish", "recipe",
        "homemade", "takeaway", "imitation", "substitute", "alternative", "analogue"
    ]

    /// How it was cooked or kept. Set aside.
    static let preparation: Set<String> = [
        "raw", "cooked", "roasted", "baked", "boiled", "grilled", "fried", "steamed",
        "poached", "stewed", "braised", "casseroled", "microwaved", "fresh", "frozen",
        "chilled", "uncooked", "organic", "pasteurized", "pasteurised", "hard-boiled",
        "soft-boiled", "pan-fried", "stir-fried", "deep-fried", "dry-fried", "oven-baked",
        "barbecued", "toasted", "reheated", "thawed", "refrigerated", "unheated",
        "heated", "drained", "undrained"
    ]

    /// Cut, skin and fat qualifiers, as phrases. Removed longest first, so
    /// "without skin" goes before "with skin" could match inside it.
    static let qualifiers: [String] = [
        "no added fat", "no fat added", "without added fat", "with added fat",
        "label rouge", "free range", "free-range", "weighed with bone",
        "weighed with skin", "meat only", "meat and skin", "lean flesh", "skin & fat",
        "skin and fat", "without skin", "with skin", "flesh only", "flesh and skin",
        "broiler or fryers", "broilers or fryers", "broiler", "boneless", "skinless",
        "in corn oil", "in sunflower oil", "in olive oil", "in vegetable oil",
        "in rapeseed oil", "in oil"
    ].sorted { $0.count > $1.count }

    static let stopWords: Set<String> = ["and", "or", "of", "the", "a", "an", "with", "without",
                                         "in", "only", "&"]

    /// The ingredient key for `name`, or nil when it must not merge.
    public static func key(for name: String) -> String? {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        if words(in: folded).contains(where: composition.contains) { return nil }

        var text = folded
        for phrase in qualifiers {
            text = text.replacingOccurrences(of: phrase, with: " ")
        }
        var key: [String] = []
        for segment in text.split(separator: ",") {
            for word in words(in: String(segment)) {
                // A lone letter is what a phrase removal leaves behind
                // ("broilers" less "broiler"), never a word of the name.
                guard word.count > 1 || word.first?.isNumber == true,
                      !preparation.contains(word), !stopWords.contains(word) else { continue }
                let single = singular(word)
                if !key.contains(single) { key.append(single) }
            }
        }
        return key.isEmpty ? nil : key.joined(separator: " ")
    }

    /// Letters, digits, `&`, `'` and `-` make words; everything else — commas,
    /// slashes, brackets — separates them. "roasted/baked" is two words.
    static func words(in text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber || "&'-".contains($0)) }.map(String.init)
    }

    /// English plurals the catalogs actually use: berries, tomatoes, eggs.
    static func singular(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 4, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") {
            return String(word.dropLast())
        }
        return word
    }

    /// The canonical ingredient's id for a key: namespaced, so an ingredient id
    /// can never be mistaken for a `food_ref`.
    public static func id(forKey key: String) -> String { "ingredient:" + key }

    /// What the ingredient is called: its key, capitalised.
    public static func name(forKey key: String) -> String {
        key.prefix(1).uppercased() + key.dropFirst()
    }
}

/// The canonical ingredients and which foods are each — what Kitchen matches
/// pantry, log and recipes through, and what the allergen check reads in
/// addition to each food's own name.
public struct IngredientTable: Sendable {
    /// Hand-made merges the rule cannot see. Key → canonical key. Kept short
    /// and in one place; a rebuild applies them and never removes them.
    public static let curatedAliases: [String: String] = [
        // CIQUAL's "Egg, raw" is a whole hen's egg, which CoFID and AFCD spell out.
        "egg": "egg chicken whole",
        "egg whole": "egg chicken whole",
        // Strips are a cut of the breast, not a different ingredient.
        "chicken breast strip": "chicken breast"
    ]

    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func isEmpty() throws -> Bool {
        try db.query("SELECT 1 AS present FROM kitchen_ingredient_food LIMIT 1;").isEmpty
    }

    /// Recomputes every `normalised` mapping from the names now in the catalog —
    /// reference foods and the person's own dishes alike — with the curated
    /// aliases applied. `curated` rows are left as they are. One transaction.
    @discardableResult
    public func rebuild() throws -> Int {
        let foods = try db.query("""
            SELECT f.food_ref, n.name FROM nutrition_food f
            JOIN nutrition_food_name n ON n.food_ref = f.food_ref AND n.is_primary = 1;
            """)
        let curated = Set(try db.query("""
            SELECT food_ref FROM kitchen_ingredient_food WHERE source = 'curated';
            """).compactMap { $0.string("food_ref") })
        var mapped = 0
        try db.transaction {
            try db.run("DELETE FROM kitchen_ingredient_food WHERE source = 'normalised';")
            try db.run("""
                DELETE FROM kitchen_ingredient WHERE id NOT IN
                    (SELECT ingredient_id FROM kitchen_ingredient_food);
                """)
            for row in foods {
                guard let ref = row.string("food_ref"), !curated.contains(ref),
                      let name = row.string("name"),
                      let raw = IngredientNormaliser.key(for: name) else { continue }
                let key = Self.curatedAliases[raw] ?? raw
                let id = IngredientNormaliser.id(forKey: key)
                try db.run("INSERT INTO kitchen_ingredient (id, name) VALUES (?, ?) ON CONFLICT(id) DO NOTHING;",
                           [.text(id), .text(IngredientNormaliser.name(forKey: key))])
                try db.run("""
                    INSERT INTO kitchen_ingredient_food (food_ref, ingredient_id, source)
                    VALUES (?, ?, 'normalised') ON CONFLICT(food_ref) DO NOTHING;
                    """, [.text(ref), .text(id)])
                mapped += 1
            }
        }
        return mapped
    }

    /// A hand-made mapping for one food, which no rebuild overwrites.
    public func curate(_ ref: SourceIdentifier, as key: String) throws {
        let id = IngredientNormaliser.id(forKey: key)
        try db.transaction {
            try db.run("INSERT INTO kitchen_ingredient (id, name) VALUES (?, ?) ON CONFLICT(id) DO NOTHING;",
                       [.text(id), .text(IngredientNormaliser.name(forKey: key))])
            try db.run("""
                INSERT INTO kitchen_ingredient_food (food_ref, ingredient_id, source) VALUES (?, ?, 'curated')
                ON CONFLICT(food_ref) DO UPDATE SET ingredient_id = excluded.ingredient_id, source = 'curated';
                """, [.text(ref.description), .text(id)])
        }
    }

    /// The ingredient each ref is, as the matching key Kitchen compares: the
    /// ingredient id when mapped, else the ref itself — so an unmapped food
    /// matches exactly as it did before the table existed.
    public func matchKeys(for refs: Set<SourceIdentifier>) throws -> [SourceIdentifier: String] {
        guard !refs.isEmpty else { return [:] }
        let json = String(decoding: try JSONEncoder().encode(refs.map(\.description).sorted()), as: UTF8.self)
        var keys = Dictionary(uniqueKeysWithValues: refs.map { ($0, $0.description) })
        for row in try db.query("""
            SELECT food_ref, ingredient_id FROM kitchen_ingredient_food
            WHERE food_ref IN (SELECT value FROM json_each(?));
            """, [.text(json)]) {
            guard let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let id = row.string("ingredient_id") else { continue }
            keys[ref] = id
        }
        return keys
    }

    /// The canonical ingredient a food is, when it is mapped.
    public func ingredient(of ref: SourceIdentifier) throws -> (id: String, name: String)? {
        guard let row = try db.query("""
            SELECT i.id, i.name FROM kitchen_ingredient_food m
            JOIN kitchen_ingredient i ON i.id = m.ingredient_id WHERE m.food_ref = ?;
            """, [.text(ref.description)]).first,
              let id = row.string("id"), let name = row.string("name") else { return nil }
        return (id, name)
    }
}
