import Foundation

/// Packaged products from Open Food Facts (owner, 2026-10-19), one record per
/// real product (`tools/openfoodfacts`, `docs/features/open-food-facts.md`).
///
/// **Why its own tables.** Open Food Facts is under the ODbL, whose
/// share-alike attaches to any adapted database publicly used. The nutrition
/// reference (`nutrition_food` and friends) admits licence groups A, B and N
/// only and must stay that way, so these products live in `off_product` /
/// `off_value` / `off_barcode` (Migration 067), every row licence group C,
/// installed from their own bundled file, `open-food-facts.json`, which is
/// itself released under the ODbL. `NutritionCatalog` reads them through the
/// `off:` namespace, so search, logging and totals need no second path.
///
/// A logged product is stored as `off:<barcode>`. Any barcode of a merged
/// record resolves to it through `off_barcode`, so a later bundle that picks a
/// different base barcode does not orphan a meal.
public enum OpenFoodFactsBundle {
    public static var resourceURL: URL {
        Bundle.module.bundleURL.appendingPathComponent("open-food-facts.json")
    }

    struct File: Decodable {
        let products: [Product]
    }

    struct Product: Decodable {
        let ref: String
        let codes: [String]
        let name: String
        let brands: String
        let quantity: String
        let basis: String
        let servingText: String?
        let servingGrams: Double?
        let url: String
        let lastModified: Int64
        let values: [String: Value]
    }

    struct Value: Decodable {
        let amount: Double
        let qualifier: String
        let sourceValue: String
        let sourceField: String
        let unit: String
    }

    /// Installs the bundled products when missing or changed. Returns the
    /// number installed, or nil when this bundle is already installed.
    @discardableResult
    public static func installIfNeeded(into db: Database, clock: any Clock = SystemClock()) throws -> Int? {
        let data = try Data(contentsOf: resourceURL)
        let sha256 = SHA256File.hex(of: Array(data))
        let installed = try db.query("SELECT bundle_sha256 FROM off_import;").first?.string("bundle_sha256")
        guard installed != sha256 else { return nil }
        return try install(data, sha256: sha256, into: db, clock: clock)
    }

    /// Replaces every installed product with `data`'s, in one transaction.
    @discardableResult
    public static func install(_ data: Data, sha256: String, into db: Database,
                               clock: any Clock = SystemClock()) throws -> Int {
        let file = try JSONDecoder().decode(File.self, from: data)
        return try db.transaction { () throws -> Int in
            try db.execute("DELETE FROM off_barcode; DELETE FROM off_value; DELETE FROM off_product; DELETE FROM off_import;")
            for product in file.products {
                guard let basis = NutritionBasis(rawValue: product.basis) else { continue }
                try db.run("""
                INSERT INTO off_product (food_ref, name, name_fold, brands, quantity_text, serving_text,
                                         serving_grams, basis, url, last_modified, licence_group)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'C');
                """, [.text(product.ref), .text(product.name), .text(TextFold.fold(product.name)),
                      .text(product.brands), .text(product.quantity),
                      product.servingText.map { SQLValue.text($0) } ?? .null,
                      product.servingGrams.map { SQLValue.real($0) } ?? .null,
                      .text(basis.rawValue), .text(product.url), .integer(product.lastModified)])
                for code in product.codes {
                    try db.run("INSERT OR IGNORE INTO off_barcode (code, food_ref) VALUES (?, ?);",
                               [.text(code), .text(product.ref)])
                }
                for (nutrient, value) in product.values {
                    guard NutrientQualifier(rawValue: value.qualifier) != nil else { continue }
                    try db.run("""
                    INSERT INTO off_value (food_ref, nutrient_id, amount, qualifier, source_value,
                                           source_field, source_unit)
                    VALUES (?, ?, ?, ?, ?, ?, ?);
                    """, [.text(product.ref), .text(nutrient), .real(value.amount), .text(value.qualifier),
                          .text(value.sourceValue), .text(value.sourceField), .text(value.unit)])
                }
            }
            try db.run("INSERT INTO off_import (bundle_sha256, product_count, imported_at) VALUES (?, ?, ?);",
                       [.text(sha256), .integer(Int64(file.products.count)),
                        .text(ISO8601DateFormatter().string(from: clock.now))])
            return file.products.count
        }
    }
}

extension NutritionCatalog {
    /// The record a barcode belongs to: `off:<any member barcode>` → its row.
    private func offRow(_ ref: SourceIdentifier) throws -> Row? {
        try db.query("""
            SELECT p.* FROM off_barcode b JOIN off_product p ON p.food_ref = b.food_ref WHERE b.code = ?;
            """, [.text(ref.localID)]).first
    }

    func offFood(_ ref: SourceIdentifier) throws -> NutritionFood? {
        guard let row = try offRow(ref), let name = row.string("name"),
              let recordRef = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)) else { return nil }
        // The brand stands where a reference food shows its food group, so the
        // search row reads "Almarai · Open Food Facts products".
        return NutritionFood(ref: recordRef, licenceGroup: .shareAlike, foodGroupCode: "",
                             foodGroupName: row.string("brands") ?? "", sourceRecord: row.string("url") ?? "",
                             names: ["en": name], primaryName: name)
    }

    func offValues(for ref: SourceIdentifier, basis: NutritionBasis) throws -> [NutrientValue] {
        guard let row = try offRow(ref), row.string("basis") == basis.rawValue,
              let recordRef = row.string("food_ref") else { return [] }
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
        try offRow(ref)?.string("basis").flatMap(NutritionBasis.init(rawValue:)).map { [$0] } ?? []
    }

    /// The label's serving, when it states one in grams, as a portion named "serving".
    func offPortions(of ref: SourceIdentifier) throws -> [NutritionPortion] {
        guard let row = try offRow(ref), let grams = row.double("serving_grams"), grams > 0 else { return [] }
        return [NutritionPortion(foodRef: ref, amount: 1, unitText: "serving", gramWeight: grams,
                                 modifierText: row.string("serving_text"), licenceGroup: .shareAlike,
                                 sourceValue: row.string("serving_text"), id: "off-serving:\(ref.localID)")]
    }

    /// Products whose name or brand matches the folded LIKE pattern, or whose
    /// barcode is exactly `text` (leading zeros optional).
    func offCandidates(pattern: String, text: String, limit: Int) throws -> [(ref: SourceIdentifier, name: String, nameFolded: String)] {
        let digits = text.trimmingCharacters(in: .whitespaces)
        let code = digits.allSatisfy(\.isNumber) && !digits.isEmpty ? digits : ""
        return try db.query("""
            SELECT food_ref, name, name_fold FROM off_product
            WHERE name_fold LIKE ?1 ESCAPE '\\'
               OR (brands IS NOT NULL AND brands LIKE ?1 ESCAPE '\\')
               OR food_ref IN (SELECT food_ref FROM off_barcode
                               WHERE ?2 <> '' AND ltrim(code, '0') = ltrim(?2, '0'))
            ORDER BY name_fold, food_ref LIMIT ?3;
            """, [.text(pattern), .text(code), .integer(Int64(limit))])
            .compactMap { row -> (ref: SourceIdentifier, name: String, nameFolded: String)? in
            guard let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let name = row.string("name") else { return nil }
            return (ref, name, row.string("name_fold") ?? "")
        }
    }
}
