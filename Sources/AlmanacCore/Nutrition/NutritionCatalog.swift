import Foundation

/// One household measure for a food: an amount, a unit, an optional modifier
/// and the gram weight the publisher (or the person) measured.
///
/// Held for any food in the catalog, reference or `almanac:` — either bundle-
/// imported (`NutritionReferenceImporter`, kind `household_measure`,
/// `nutrition.md` §8) or locally added through `addPortion`. A food's
/// *density* or *edible proportion*, the bundle's other two portion kinds,
/// are a different shape (a factor, not a quantity of a named unit) and live
/// in `NutritionFoodFactor` instead — see its own doc comment.
public struct NutritionPortion: Sendable, Hashable {
    public let id: String
    public let foodRef: SourceIdentifier
    public let amount: Double
    public let unitText: String
    public let modifierText: String?
    public let gramWeight: Double
    public let sequence: Int
    public let licenceGroup: LicenceGroup
    public let sourceValue: String?

    public init(foodRef: SourceIdentifier, amount: Double, unitText: String,
                gramWeight: Double, modifierText: String? = nil, sequence: Int = 0,
                licenceGroup: LicenceGroup, sourceValue: String? = nil,
                id: String = UUID().uuidString) {
        self.id = id
        self.foodRef = foodRef
        self.amount = amount
        self.unitText = unitText
        self.modifierText = modifierText
        self.gramWeight = gramWeight
        self.sequence = sequence
        self.licenceGroup = licenceGroup
        self.sourceValue = sourceValue
    }

    /// Grams per one of `unitText`. The stored row may be "2 tbsp = 30 g".
    public var gramsPerUnit: Double { gramWeight / amount }
}

/// The result of asking what a measure weighs.
///
/// `ambiguous` is a real answer, not a failure to find one: USDA carries
/// several "1 cup" rows for the same food, and picking by row order would
/// silently choose a mass. Same discipline as `CatalogMatchResult` in
/// Laboratory.
public enum PortionMatch: Sendable, Hashable {
    /// Deliberately not spelled `none`: this enum is returned unwrapped, and a
    /// case by that name reads as `Optional.none` at every call site.
    case notFound
    case one(NutritionPortion)
    case ambiguous([NutritionPortion])

    public var resolved: NutritionPortion? {
        if case .one(let p) = self { return p }
        return nil
    }
}

/// A food-level density or edible-proportion factor — the bundle's other two
/// `nutrition_portion` kinds (`specific_gravity`, `edible_proportion`;
/// Processing Design v0.1 §4), reconciled into their own table
/// (`nutrition_food_factor`, Migration027) rather than sharing
/// `NutritionPortion`'s shape, which is a quantity of a named unit and has no
/// slot for a bare density or fraction.
///
/// Per **reference food** — thousands of CoFID rows — unlike
/// `NutritionDish.edibleProportion`, which is the same concept for the one
/// case of a device-authored `almanac:` dish. Two different foods, never the
/// same row twice.
///
/// `value` is nil exactly when `qualifier` carries no quantity (CoFID's `N`,
/// "not analysed") — the same "a token never becomes a number" rule
/// `NutrientValue` already follows.
public struct NutritionFoodFactor: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case specificGravity = "specific_gravity"
        case edibleProportion = "edible_proportion"
    }

    public let foodRef: SourceIdentifier
    public let kind: Kind
    public let value: Double?
    public let qualifier: NutrientQualifier
    public let sourceValue: String
    public let licenceGroup: LicenceGroup

    public init(foodRef: SourceIdentifier, kind: Kind, value: Double?, qualifier: NutrientQualifier,
                sourceValue: String, licenceGroup: LicenceGroup) {
        self.foodRef = foodRef
        self.kind = kind
        self.value = value
        self.qualifier = qualifier
        self.sourceValue = sourceValue
        self.licenceGroup = licenceGroup
    }
}

/// A reference food as its publisher identifies and names it.
public struct NutritionFood: Sendable, Hashable {
    public let ref: SourceIdentifier
    public let licenceGroup: LicenceGroup
    public let foodGroupCode: String
    public let foodGroupName: String
    /// Where the row came from in the publisher's file, for tracing a value back.
    public let sourceRecord: String
    /// ISO 639 language code -> name.
    public let names: [String: String]
    public let primaryName: String
}

/// Read access to the imported reference foods. A seam over SQL, not an ORM.
public struct NutritionCatalog: @unchecked Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func hasReferenceFoods() throws -> Bool {
        try !db.query("SELECT 1 FROM nutrition_food LIMIT 1;").isEmpty
    }

    public func food(_ ref: SourceIdentifier) throws -> NutritionFood? {
        guard let row = try db.query("""
            SELECT licence_group, food_group_code, food_group_name, source_record
            FROM nutrition_food WHERE food_ref = ?;
            """, [.text(ref.description)]).first,
              let group = row.string("licence_group").flatMap(LicenceGroup.init(rawValue:)) else { return nil }
        var names: [String: String] = [:]
        var primary = ""
        for name in try db.query("""
            SELECT language, name, is_primary FROM nutrition_food_name WHERE food_ref = ? ORDER BY language;
            """, [.text(ref.description)]) {
            guard let language = name.string("language"), let text = name.string("name") else { continue }
            names[language] = text
            if name.int("is_primary") == 1 { primary = text }
        }
        return NutritionFood(ref: ref, licenceGroup: group, foodGroupCode: row.string("food_group_code") ?? "",
                             foodGroupName: row.string("food_group_name") ?? "",
                             sourceRecord: row.string("source_record") ?? "", names: names, primaryName: primary)
    }

    /// Every value published for the food on one basis. Tokens keep an empty amount.
    public func values(for ref: SourceIdentifier, basis: NutritionBasis) throws -> [NutrientValue] {
        try db.query("""
            SELECT nutrient_id, amount, qualifier, confidence, source_value, source_nutrient_id, source_unit,
                   licence_group
            FROM nutrition_value WHERE food_ref = ? AND basis = ? ORDER BY nutrient_id;
            """, [.text(ref.description), .text(basis.rawValue)]).compactMap { row in
            // The table's CHECK constraints admit only values these types can parse.
            guard let nutrient = row.string("nutrient_id"),
                  let qualifier = row.string("qualifier").flatMap(NutrientQualifier.init(rawValue:)),
                  let group = row.string("licence_group").flatMap(LicenceGroup.init(rawValue:)),
                  let sourceValue = row.string("source_value"),
                  let sourceNutrient = row.string("source_nutrient_id"),
                  let sourceUnit = row.string("source_unit") else { return nil }
            return NutrientValue(foodRef: ref, nutrientID: nutrient, amount: row.double("amount"),
                                 qualifier: qualifier, confidence: row.string("confidence"),
                                 sourceValue: sourceValue, sourceNutrientID: sourceNutrient,
                                 sourceUnit: sourceUnit, licenceGroup: group, basis: basis)
        }
    }

    /// The bases the publisher gives values on: per 100 g, and for some liquids per 100 mL too.
    public func bases(for ref: SourceIdentifier) throws -> [NutritionBasis] {
        try db.query("SELECT DISTINCT basis FROM nutrition_value WHERE food_ref = ? ORDER BY basis;",
                     [.text(ref.description)])
            .compactMap { $0.string("basis").flatMap(NutritionBasis.init(rawValue:)) }
    }

    /// Almanac's calorie number for the food on one basis (see `EnergyEstimate.preferred`).
    public func energy(for ref: SourceIdentifier, basis: NutritionBasis) throws -> EnergyEstimate? {
        EnergyEstimate.preferred(from: try values(for: ref, basis: basis), basis: basis)
    }

    /// Foods whose name in any language contains `text`, compared folded (`TextFold`):
    /// case, accents and Arabic letter variants do not matter. Each food once, by primary name.
    public func search(_ text: String, limit: Int = 50) throws -> [NutritionFood] {
        let folded = TextFold.fold(text)
        guard !folded.isEmpty, limit > 0 else { return [] }
        let pattern = "%" + folded.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        return try db.query("""
            SELECT f.food_ref FROM nutrition_food f
            JOIN nutrition_food_name p ON p.food_ref = f.food_ref AND p.is_primary = 1
            WHERE EXISTS (SELECT 1 FROM nutrition_food_name n
                          WHERE n.food_ref = f.food_ref AND n.name_fold LIKE ? ESCAPE '\\')
            ORDER BY p.name_fold, f.food_ref
            LIMIT ?;
            """, [.text(pattern), .integer(Int64(limit))])
            .compactMap { row in
                try row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)).flatMap(food)
            }
    }

    // MARK: Portions

    @discardableResult
    public func addPortion(_ portion: NutritionPortion) throws -> String {
        guard portion.gramWeight.isFinite, portion.gramWeight > 0 else {
            throw NutritionError.invalidGramWeight(portion.gramWeight)
        }
        guard portion.amount.isFinite, portion.amount > 0 else {
            throw NutritionError.invalidAmount(portion.amount)
        }
        try BundleGuard.assertShippable([(identifier: portion.foodRef.description,
                                          group: portion.licenceGroup)])
        guard try food(portion.foodRef) != nil else {
            throw NutritionError.foodNotFound(portion.foodRef)
        }
        // Re-adding a measure already held updates it rather than storing a
        // second copy — two identical rows would otherwise read as an
        // ambiguity between a row and itself. See Migration011.
        try db.run("""
        INSERT INTO nutrition_portion
            (id, food_ref, amount, unit_text, unit_fold, modifier_text,
             gram_weight, sequence, licence_group, source_value)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(food_ref, unit_fold, COALESCE(modifier_text, ''), amount, gram_weight)
        DO UPDATE SET
            unit_text     = excluded.unit_text,
            sequence      = excluded.sequence,
            licence_group = excluded.licence_group,
            source_value  = excluded.source_value;
        """, [
            .text(portion.id), .text(portion.foodRef.description), .real(portion.amount),
            .text(portion.unitText), .text(TextFold.fold(portion.unitText)),
            portion.modifierText.map { SQLValue.text($0) } ?? .null,
            .real(portion.gramWeight), .integer(Int64(portion.sequence)),
            .text(portion.licenceGroup.rawValue),
            portion.sourceValue.map { SQLValue.text($0) } ?? .null
        ])
        // The held row's id, which is the caller's only when this was an insert.
        return try db.query("""
            SELECT id FROM nutrition_portion
            WHERE food_ref = ? AND unit_fold = ? AND COALESCE(modifier_text, '') = ?
              AND amount = ? AND gram_weight = ?;
            """, [.text(portion.foodRef.description), .text(TextFold.fold(portion.unitText)),
                  .text(portion.modifierText ?? ""), .real(portion.amount),
                  .real(portion.gramWeight)]).first?.string("id") ?? portion.id
    }

    /// Every measure held for a food, in the order it was added.
    public func portions(of ref: SourceIdentifier) throws -> [NutritionPortion] {
        try db.query("""
            SELECT id, food_ref, amount, unit_text, modifier_text, gram_weight,
                   sequence, licence_group, source_value
            FROM nutrition_portion WHERE food_ref = ? ORDER BY sequence, unit_text;
            """, [.text(ref.description)]).compactMap(NutritionCatalog.portion(from:))
    }

    /// What one named measure of this food weighs.
    ///
    /// A `modifier` narrows the search — "1 cup, cooked" against "1 cup, raw".
    /// When several rows still match, they all come back: choosing between two
    /// gram weights is the caller's decision with the user in front of it, not
    /// a silent pick by row order.
    public func portion(of ref: SourceIdentifier, unit: String,
                        modifier: String? = nil) throws -> PortionMatch {
        let forms = NutritionCatalog.matchableForms(unit)
        guard !forms.isEmpty else { return .notFound }
        var candidates = try db.query("""
            SELECT id, food_ref, amount, unit_text, modifier_text, gram_weight,
                   sequence, licence_group, source_value
            FROM nutrition_portion
            WHERE food_ref = ? AND unit_fold IN (?, ?, ?)
            ORDER BY sequence, id;
            """, [.text(ref.description), .text(forms[0]), .text(forms[1]), .text(forms[2])])
            .compactMap(NutritionCatalog.portion(from:))

        if let modifier {
            let wanted = TextFold.fold(modifier)
            let narrowed = candidates.filter {
                TextFold.fold($0.modifierText ?? "") == wanted
            }
            // An unmatched modifier narrows to nothing rather than falling back
            // to every row: "1 cup, cooked" must not quietly answer with raw.
            candidates = narrowed
        }

        switch candidates.count {
        case 0:  return .notFound
        case 1:  return .one(candidates[0])
        default: return .ambiguous(candidates)
        }
    }

    /// Resolves a household measure to grams — "2 cups" → 316 g.
    ///
    /// Nil when the measure is unknown or ambiguous. The caller stores the
    /// number; it is deliberately not recomputed at read time, because a later
    /// correction to a gram weight must not silently change the mass of a meal
    /// the user already confirmed.
    public func grams(of ref: SourceIdentifier, amount: Double, unit: String,
                      modifier: String? = nil) throws -> Double? {
        guard amount.isFinite, amount > 0 else { throw NutritionError.invalidAmount(amount) }
        guard let portion = try self.portion(of: ref, unit: unit, modifier: modifier).resolved
        else { return nil }
        return portion.gramsPerUnit * amount
    }

    // MARK: Food factors

    /// A food's density or edible-proportion factor, bundle-imported into
    /// `nutrition_food_factor` (Migration027). Nil when the food has no row
    /// of that kind — most foods outside CoFID, and CoFID foods the source
    /// itself left blank.
    ///
    /// One row is the expected shape (one factor per food per kind); several
    /// source records disagreeing is a data anomaly, not a real ambiguity a
    /// person resolves the way `portion(of:)` lets them — this simply
    /// returns the first, ordered by `source_record`, rather than adding a
    /// second ambiguity type for a case nothing has ever produced.
    public func foodFactor(of ref: SourceIdentifier, kind: NutritionFoodFactor.Kind) throws -> NutritionFoodFactor? {
        try db.query("""
            SELECT food_ref, value, qualifier, source_value, licence_group
            FROM nutrition_food_factor
            WHERE food_ref = ? AND kind = ?
            ORDER BY source_record
            LIMIT 1;
            """, [.text(ref.description), .text(kind.rawValue)])
            .first.flatMap { row -> NutritionFoodFactor? in
                guard let qualifierText = row.string("qualifier"),
                      let qualifier = NutrientQualifier(rawValue: qualifierText),
                      let sourceValue = row.string("source_value"),
                      let group = row.string("licence_group").flatMap(LicenceGroup.init(rawValue:))
                else { return nil }
                return NutritionFoodFactor(foodRef: ref, kind: kind, value: row.double("value"),
                                           qualifier: qualifier, sourceValue: sourceValue, licenceGroup: group)
            }
    }

    /// The folded forms a typed measure may match: itself, its plural, and its
    /// singular. Always three, so the query shape is fixed.
    ///
    /// `TextFold` normalises case, diacritics and script — not grammar — so a
    /// stored "cup" never matches a typed "cups", and "2 cups" is exactly the
    /// input this feature exists to answer. Matching extra forms at *query*
    /// time rather than normalising what is stored means nothing is lost on
    /// the way in and two genuinely different units are never merged: a
    /// publisher shipping both "cup" and "cups" rows still comes back
    /// `.ambiguous`, which is the honest answer.
    ///
    /// English -s only. "glasses"/"glass" and other -es plurals miss and fall
    /// out as `.notFound`, which the caller already handles. A unit dictionary
    /// is the upgrade if a source ships measures this gets wrong.
    static func matchableForms(_ unit: String) -> [String] {
        let fold = TextFold.fold(unit)
        guard !fold.isEmpty else { return [] }
        let singular = fold.count > 2 && fold.hasSuffix("s") ? String(fold.dropLast()) : fold
        return [fold, fold + "s", singular]
    }

    private static func portion(from row: Row) -> NutritionPortion? {
        guard let id = row.string("id"),
              let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
              let amount = row.double("amount"), let unit = row.string("unit_text"),
              let gramWeight = row.double("gram_weight"),
              let group = row.string("licence_group").flatMap(LicenceGroup.init(rawValue:))
        else { return nil }
        return NutritionPortion(
            foodRef: ref, amount: amount, unitText: unit, gramWeight: gramWeight,
            modifierText: row.string("modifier_text"),
            sequence: Int(row.int("sequence") ?? 0), licenceGroup: group,
            sourceValue: row.string("source_value"), id: id)
    }
}
