import Foundation

public struct NutritionImportReport: Sendable, Hashable {
    public let bundleSHA256: String
    public let schemaVersion: Int
    public let namespaces: [SourceIdentifier.Namespace]
    public let foodCount: Int
    public let valueCount: Int
}

public enum NutritionImportError: Error, CustomStringConvertible, Sendable {
    case bundleMissing(path: String)
    case unsupportedSchemaVersion(found: String?)
    case unknownNamespace(String)
    case unknownLicenceGroup(identifier: String, group: String)
    case licenceGroupDisagrees(identifier: String, bundle: LicenceGroup, registry: LicenceGroup)
    case qualifierVocabularyDiffers(String)

    public var description: String {
        switch self {
        case .bundleMissing(let path):
            return "No nutrition bundle at \(path)."
        case .unsupportedSchemaVersion(let found):
            return "Nutrition bundle schema version \(found ?? "(none)") is not supported; this build reads "
                + "version \(NutritionReferenceImporter.supportedSchemaVersion)."
        case .unknownNamespace(let namespace):
            return "Nutrition bundle names source namespace \"\(namespace)\", which AlmanacCore does not know."
        case .unknownLicenceGroup(let identifier, let group):
            return "\(identifier) has licence group \"\(group)\", which AlmanacCore does not know."
        case .licenceGroupDisagrees(let identifier, let bundle, let registry):
            return "\(identifier) is labelled licence group \(bundle.rawValue) but its source is group "
                + "\(registry.rawValue). The bundle was not built by tools/nutrition."
        case .qualifierVocabularyDiffers(let qualifier):
            return "The bundle's qualifier \"\(qualifier)\" does not mean what NutrientQualifier means."
        }
    }
}

/// Replaces the nutrition reference tables with a bundle built by tools/nutrition
/// (bundle schema v1). Nothing is written to the bundle. Everything it claims is
/// checked first — the licence assertion runs again here, against AlmanacCore's own
/// registry — and then every row is copied in one transaction, so a refused or
/// failed import leaves the previous reference data exactly as it was.
public struct NutritionReferenceImporter: @unchecked Sendable {
    public static let supportedSchemaVersion = 1
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    @discardableResult
    public func importBundle(at path: String) throws -> NutritionImportReport {
        // ATTACH would create an empty database at a missing path and import nothing.
        guard FileManager.default.fileExists(atPath: path) else {
            throw NutritionImportError.bundleMissing(path: path)
        }
        let sha256 = try SHA256File.hex(ofFileAt: path)
        try db.run("ATTACH DATABASE ? AS bundle;", [.text(path)])
        defer { try? db.execute("DETACH DATABASE bundle;") }

        let version = try meta("schema_version")
        guard version == String(Self.supportedSchemaVersion) else {
            throw NutritionImportError.unsupportedSchemaVersion(found: version)
        }
        try verifyQualifiers()
        try verifyLicenceGroups("""
            SELECT namespace AS identifier, namespace, licence_group FROM bundle.nutrition_source;
            """)
        try verifyLicenceGroups("""
            SELECT food_ref AS identifier, namespace, licence_group FROM bundle.nutrition_food;
            """)
        try verifyLicenceGroups("""
            SELECT food_ref || '/' || nutrient_id || '/' || basis AS identifier,
                   substr(food_ref, 1, instr(food_ref, ':') - 1) AS namespace, licence_group
            FROM bundle.nutrition_value;
            """)
        let namespaces = try db.query("SELECT namespace FROM bundle.nutrition_source ORDER BY namespace;")
            .compactMap { $0.string("namespace").flatMap(SourceIdentifier.Namespace.init(rawValue:)) }

        return try db.transaction {
            try db.execute("""
            DELETE FROM nutrition_value;
            DELETE FROM nutrition_food_name;
            DELETE FROM nutrition_food;
            DELETE FROM nutrition_nutrient;
            DELETE FROM nutrition_source;
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
                SELECT namespace, dataset_id, name, release, licence, licence_group, attribution, url
                FROM bundle.nutrition_source;
            INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
                SELECT nutrient_id, infoods_tag, name, unit, description FROM bundle.nutrition_nutrient;
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
                SELECT food_ref, namespace, local_id, licence_group, food_group_code, food_group_name,
                       source_record
                FROM bundle.nutrition_food;
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary)
                SELECT food_ref, language, name, is_primary FROM bundle.nutrition_food_name;
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                                         source_value, source_nutrient_id, source_unit, licence_group)
                SELECT food_ref, nutrient_id, basis, amount, qualifier, confidence, source_value,
                       source_nutrient_id, source_unit, licence_group
                FROM bundle.nutrition_value;
            """)
            // Search matches folded names, folded the way Laboratory folds its aliases.
            for name in try db.query("SELECT food_ref, language, name FROM nutrition_food_name;") {
                try db.run("UPDATE nutrition_food_name SET name_fold = ? WHERE food_ref = ? AND language = ?;",
                           [.text(TextFold.fold(name.string("name") ?? "")),
                            .text(name.string("food_ref") ?? ""), .text(name.string("language") ?? "")])
            }
            let foods = try count("nutrition_food")
            let values = try count("nutrition_value")
            try db.run("""
            INSERT INTO nutrition_reference_import (imported_at, bundle_sha256, schema_version,
                                                    dictionary_sha256, namespaces, food_count, value_count)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """, [.text(ISO8601DateFormatter().string(from: clock.now)), .text(sha256),
                  .integer(Int64(Self.supportedSchemaVersion)), .text(try meta("dictionary_sha256") ?? ""),
                  .text(namespaces.map(\.rawValue).joined(separator: ",")),
                  .integer(Int64(foods)), .integer(Int64(values))])
            return NutritionImportReport(bundleSHA256: sha256, schemaVersion: Self.supportedSchemaVersion,
                                         namespaces: namespaces, foodCount: foods, valueCount: values)
        }
    }

    /// The bundle's qualifiers must be exactly NutrientQualifier, meaning the same things.
    private func verifyQualifiers() throws {
        var seen = Set<NutrientQualifier>()
        for row in try db.query("SELECT qualifier, has_quantity, directly_observed FROM bundle.nutrition_qualifier;") {
            let name = row.string("qualifier") ?? ""
            guard let qualifier = NutrientQualifier(rawValue: name),
                  (row.int("has_quantity") == 1) == qualifier.hasQuantity,
                  (row.int("directly_observed") == 1) == qualifier.isDirectlyObserved else {
                throw NutritionImportError.qualifierVocabularyDiffers(name)
            }
            seen.insert(qualifier)
        }
        if let missing = NutrientQualifier.allCases.first(where: { !seen.contains($0) }) {
            throw NutritionImportError.qualifierVocabularyDiffers(missing.rawValue)
        }
    }

    /// `sql` yields `identifier`, `namespace` and `licence_group` for every row of one table.
    private func verifyLicenceGroups(_ sql: String) throws {
        var rows: [(identifier: String, group: LicenceGroup, namespace: SourceIdentifier.Namespace)] = []
        for row in try db.query(sql) {
            let identifier = row.string("identifier") ?? ""
            let groupText = row.string("licence_group") ?? ""
            guard let group = LicenceGroup(rawValue: groupText) else {
                throw NutritionImportError.unknownLicenceGroup(identifier: identifier, group: groupText)
            }
            let namespaceText = row.string("namespace") ?? ""
            guard let namespace = SourceIdentifier.Namespace(rawValue: namespaceText) else {
                throw NutritionImportError.unknownNamespace(namespaceText)
            }
            rows.append((identifier, group, namespace))
        }
        // The pipeline's assertion, run again: a restricted row fails loudly and by name.
        try BundleGuard.assertShippable(rows.map { (identifier: $0.identifier, group: $0.group) })
        // A shippable group is still wrong if it is not the one AlmanacCore registers for the source.
        if let wrong = rows.first(where: { $0.group != $0.namespace.licenceGroup }) {
            throw NutritionImportError.licenceGroupDisagrees(identifier: wrong.identifier, bundle: wrong.group,
                                                             registry: wrong.namespace.licenceGroup)
        }
    }

    private func meta(_ key: String) throws -> String? {
        try db.query("SELECT value FROM bundle.bundle_meta WHERE key = ?;", [.text(key)]).first?.string("value")
    }

    private func count(_ table: String) throws -> Int {
        Int(try db.query("SELECT COUNT(*) AS n FROM \(table);").first?.int("n") ?? 0)
    }
}
