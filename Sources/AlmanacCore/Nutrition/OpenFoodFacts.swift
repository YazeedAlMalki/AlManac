import Foundation

/// Packaged products from Open Food Facts (owner, 2026-10-19), one record per
/// real product (`tools/openfoodfacts`, `docs/features/open-food-facts.md`).
///
/// **Why a file of its own, read in place.** Open Food Facts is under the
/// ODbL, whose share-alike attaches to any adapted database publicly used. So
/// the products are never written into the nutrition reference tables (groups
/// A, B and N only) or anywhere else in the person's database: they stay in
/// the bundled `open-food-facts.sqlite`, itself released under the ODbL, which
/// is opened read-only here. Nothing is installed, and backups do not carry
/// it. `NutritionCatalog` reads it through the `off:` namespace, so search,
/// logging and totals need no second path.
///
/// A logged product is stored as `off:<barcode>`. Any barcode of a merged
/// record resolves to it through `off_barcode`, so a later file that picks a
/// different base barcode does not orphan a meal.
public enum OpenFoodFacts {
    static let path = Bundle.module.bundleURL.appendingPathComponent("open-food-facts.sqlite").path

    /// Nil only if the file is missing from the build, which is a packaging
    /// bug: the catalog then has no products rather than failing every search.
    static let db: Database? = {
        do { return try Database(readOnlyPath: path) } catch {
            assertionFailure("open-food-facts.sqlite missing or unreadable: \(error)")
            return nil
        }
    }()

    struct Entry {
        let ref: SourceIdentifier
        let name: String
        let nameFolded: String
        let brandFolded: String
    }

    /// Every product's name, folded by the same `TextFold` the reference
    /// names are, read once. About 3,500 short rows, so searching them in
    /// memory costs less than keeping a second fold in step with this one.
    static let index: [Entry] = {
        guard let db else { return [] }
        return ((try? db.query("SELECT food_ref, name, brands FROM off_product ORDER BY food_ref;")) ?? [])
            .compactMap { row in
                guard let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                      let name = row.string("name") else { return nil }
                return Entry(ref: ref, name: name, nameFolded: TextFold.fold(name),
                             brandFolded: TextFold.fold(row.string("brands") ?? ""))
            }
    }()

    /// The record a barcode belongs to: `off:<any member barcode>` → its row.
    static func row(_ ref: SourceIdentifier) throws -> Row? {
        try db?.query("""
            SELECT p.* FROM off_barcode b JOIN off_product p ON p.food_ref = b.food_ref WHERE b.code = ?;
            """, [.text(ref.localID)]).first
    }
}

extension NutritionCatalog {
    func offFood(_ ref: SourceIdentifier) throws -> NutritionFood? {
        guard let row = try OpenFoodFacts.row(ref), let name = row.string("name"),
              let recordRef = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)) else { return nil }
        // The brand stands where a reference food shows its food group, so the
        // search row reads "Almarai · Open Food Facts products".
        return NutritionFood(ref: recordRef, licenceGroup: .shareAlike, foodGroupCode: "",
                             foodGroupName: row.string("brands") ?? "", sourceRecord: row.string("url") ?? "",
                             names: ["en": name], primaryName: name)
    }

    func offValues(for ref: SourceIdentifier, basis: NutritionBasis) throws -> [NutrientValue] {
        guard let row = try OpenFoodFacts.row(ref), row.string("basis") == basis.rawValue,
              let recordRef = row.string("food_ref"), let db = OpenFoodFacts.db else { return [] }
        return try db.query("""
            SELECT nutrient_id, amount, qualifier, source_value, source_field, source_unit
            FROM off_value WHERE food_ref = ? ORDER BY nutrient_id;
            """, [.text(recordRef)]).compactMap { value in
            guard let nutrient = value.string("nutrient_id"),
                  let qualifier = value.string("qualifier").flatMap(NutrientQualifier.init(rawValue:)),
                  let sourceValue = value.string("source_value"), let field = value.string("source_field"),
                  let unit = value.string("source_unit") else { return nil }
            return NutrientValue(foodRef: ref, nutrientID: nutrient, amount: value.double("amount"),
                                 qualifier: qualifier, sourceValue: sourceValue, sourceNutrientID: field,
                                 sourceUnit: unit, licenceGroup: .shareAlike, basis: basis)
        }
    }

    func offBases(for ref: SourceIdentifier) throws -> [NutritionBasis] {
        try OpenFoodFacts.row(ref)?.string("basis").flatMap(NutritionBasis.init(rawValue:)).map { [$0] } ?? []
    }

    /// The label's serving, when it states one in grams, as a portion named "serving".
    func offPortions(of ref: SourceIdentifier) throws -> [NutritionPortion] {
        guard let row = try OpenFoodFacts.row(ref), let grams = row.double("serving_grams"), grams > 0 else { return [] }
        return [NutritionPortion(foodRef: ref, amount: 1, unitText: "serving", gramWeight: grams,
                                 modifierText: row.string("serving_text"), licenceGroup: .shareAlike,
                                 sourceValue: row.string("serving_text"), id: "off-serving:\(ref.localID)")]
    }

    /// Products whose folded name or brand contains `folded`, or whose barcode
    /// is exactly `text` (leading zeros optional), in name order.
    func offCandidates(folded: String, text: String, limit: Int)
        throws -> [(ref: SourceIdentifier, name: String, nameFolded: String)] {
        var hits = OpenFoodFacts.index.filter { $0.nameFolded.contains(folded) || $0.brandFolded.contains(folded) }
        let digits = text.trimmingCharacters(in: .whitespaces)
        if !digits.isEmpty, digits.allSatisfy(\.isNumber), let db = OpenFoodFacts.db {
            let refs = Set(try db.query("SELECT food_ref FROM off_barcode WHERE ltrim(code, '0') = ltrim(?, '0');",
                                        [.text(digits)]).compactMap { $0.string("food_ref") })
            let seen = Set(hits.map(\.ref.description))
            hits += OpenFoodFacts.index.filter { refs.contains($0.ref.description) && !seen.contains($0.ref.description) }
        }
        return hits.sorted { ($0.nameFolded, $0.ref.description) < ($1.nameFolded, $1.ref.description) }
            .prefix(limit).map { (ref: $0.ref, name: $0.name, nameFolded: $0.nameFolded) }
    }
}
