import Foundation

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
}
