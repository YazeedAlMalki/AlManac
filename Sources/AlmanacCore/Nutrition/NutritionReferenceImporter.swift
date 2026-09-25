import Foundation

/// Installs the production nutrition reference packaged with AlmanacCore.
public enum NutritionReferenceBundle {
    /// Imports the bundled reference when it is missing or its contents changed.
    /// Returns `nil` when the installed bundle already has the same SHA-256.
    @discardableResult
    public static func installIfNeeded(
        into db: Database,
        clock: any Clock = SystemClock()
    ) throws -> NutritionImportReport? {
        let path = Bundle.module.bundleURL.appendingPathComponent("almanac.sqlite").path
        let sha256 = try SHA256File.hex(ofFileAt: path)
        let installedSHA256 = try db.query("""
            SELECT bundle_sha256 FROM nutrition_reference_import ORDER BY rowid DESC LIMIT 1;
            """).first?.string("bundle_sha256")
        guard installedSHA256 != sha256 else { return nil }
        return try NutritionReferenceImporter(db: db, clock: clock)
            .importBundle(at: path, bundleSHA256: sha256)
    }
}

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
        return try importBundle(at: path, bundleSHA256: SHA256File.hex(ofFileAt: path))
    }

    func importBundle(at path: String, bundleSHA256 sha256: String) throws -> NutritionImportReport {
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
        try verifyLicenceGroups("""
            SELECT food_ref || '/' || kind || '/' || source_record AS identifier,
                   substr(food_ref, 1, instr(food_ref, ':') - 1) AS namespace, licence_group
            FROM bundle.nutrition_portion;
            """)
        let namespaces = try db.query("SELECT namespace FROM bundle.nutrition_source ORDER BY namespace;")
            .compactMap { $0.string("namespace").flatMap(SourceIdentifier.Namespace.init(rawValue:)) }
        let namespacePlaceholders = namespaces.map { _ in "?" }.joined(separator: ", ")
        let namespaceValues: [SQLValue] = namespaces.map { .text($0.rawValue) }

        return try db.transaction {
            // Every food is replaced wholesale — that is what "removing a
            // whole source stays one step" (§3) means, and it is how a source
            // dropped from the next bundle disappears here too — *except* an
            // `almanac:` row a person authored on this device through
            // `NutritionDishEditor`, which the pipeline knows nothing about
            // and must not erase on the next reimport. The pipeline does ship
            // its own `almanac:` rows (curated native foods, once there are
            // any) and those are ordinary reference data, replaced like any
            // other row; `nutrition_dish` is what tells the two apart, since
            // only a device-authored dish ever gets a row there. Deleting
            // children before parents, in FK order, is what lets the parent
            // tables use a plain DELETE at all.
            try db.execute("""
                DELETE FROM nutrition_value WHERE food_ref IN (
                    SELECT food_ref FROM nutrition_food
                    WHERE food_ref NOT IN (SELECT food_ref FROM nutrition_dish)
                );
                DELETE FROM nutrition_food_name WHERE food_ref IN (
                    SELECT food_ref FROM nutrition_food
                    WHERE food_ref NOT IN (SELECT food_ref FROM nutrition_dish)
                );
                DELETE FROM nutrition_food
                    WHERE food_ref NOT IN (SELECT food_ref FROM nutrition_dish);
                """)
            // Now safe: no surviving row references a withdrawn source.
            try db.run("""
                DELETE FROM nutrition_source
                WHERE namespace <> 'almanac' AND namespace NOT IN (\(namespacePlaceholders));
                """, namespaceValues)
            // Upserted, not replaced: a preserved `almanac:` value still
            // references `nutrition_nutrient` and its own `nutrition_source`
            // row, and deleting either out from under it — even for one
            // statement inside this same transaction — is a foreign-key
            // violation, not a reordering problem a later INSERT undoes.
            // Row by row rather than `INSERT ... SELECT ... ON CONFLICT`:
            // SQLite's upsert clause is not accepted after a SELECT source,
            // only after VALUES.
            for row in try db.query("SELECT * FROM bundle.nutrition_source;") {
                try db.run("""
                INSERT INTO nutrition_source
                    (namespace, dataset_id, name, release, licence, licence_group, attribution, url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (namespace) DO UPDATE SET
                    dataset_id = excluded.dataset_id, name = excluded.name, release = excluded.release,
                    licence = excluded.licence, licence_group = excluded.licence_group,
                    attribution = excluded.attribution, url = excluded.url;
                """, [.text(row.string("namespace") ?? ""), .text(row.string("dataset_id") ?? ""),
                      .text(row.string("name") ?? ""), .text(row.string("release") ?? ""),
                      .text(row.string("licence") ?? ""), .text(row.string("licence_group") ?? ""),
                      .text(row.string("attribution") ?? ""), .text(row.string("url") ?? "")])
            }
            for row in try db.query("SELECT * FROM bundle.nutrition_nutrient;") {
                try db.run("""
                INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (nutrient_id) DO UPDATE SET
                    infoods_tag = excluded.infoods_tag, name = excluded.name, unit = excluded.unit,
                    description = excluded.description;
                """, [.text(row.string("nutrient_id") ?? ""), .text(row.string("infoods_tag") ?? ""),
                      .text(row.string("name") ?? ""), .text(row.string("unit") ?? ""),
                      .text(row.string("description") ?? "")])
            }
            try db.execute("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
                SELECT food_ref, namespace, local_id, licence_group, food_group_code, food_group_name,
                       source_record
                FROM bundle.nutrition_food;
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                                         source_value, source_nutrient_id, source_unit, licence_group)
                SELECT food_ref, nutrient_id, basis, amount, qualifier, confidence, source_value,
                       source_nutrient_id, source_unit, licence_group
                FROM bundle.nutrition_value;
            """)
            let foodNames = try db.query("SELECT food_ref, language, name, is_primary FROM bundle.nutrition_food_name;")
                .map { row -> [SQLValue] in
                    let name = row.string("name") ?? ""
                    return [.text(row.string("food_ref") ?? ""), .text(row.string("language") ?? ""),
                            .text(name), .integer(row.int("is_primary") ?? 0), .text(TextFold.fold(name))]
                }
            try db.run("""
                INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
                VALUES (?, ?, ?, ?, ?);
                """, each: foodNames)
            // Household measures (kind = 'household_measure') go into the existing
            // nutrition_portion table — a real quantity of a named unit, the
            // shape it was already built for (Migration010). The insert statement
            // is prepared once because unit_fold needs TextFold in Swift. Bundle
            // rows use '' for "no modifier" (a NOT NULL column); the device
            // table uses NULL, matching what addPortion already writes.
            let householdMeasures = try db.query("SELECT * FROM bundle.nutrition_portion WHERE kind = 'household_measure';")
                .map { row -> [SQLValue] in
                    let unit = row.string("unit") ?? ""
                    let modifier = row.string("modifier").flatMap { $0.isEmpty ? nil : $0 }
                    return [.text(UUID().uuidString), .text(row.string("food_ref") ?? ""),
                            .real(row.double("amount") ?? 0), .text(unit), .text(TextFold.fold(unit)),
                            modifier.map { SQLValue.text($0) } ?? .null, .real(row.double("value") ?? 0),
                            .text(row.string("licence_group") ?? ""), .text(row.string("source_value") ?? "")]
                }
            try db.run("""
                INSERT INTO nutrition_portion
                    (id, food_ref, amount, unit_text, unit_fold, modifier_text,
                     gram_weight, sequence, licence_group, source_value)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?);
                """, each: householdMeasures)
            // specific_gravity and edible_proportion are a food-level factor, not a
            // quantity — nutrition_food_factor (Migration027), a plain bulk copy since
            // no Swift-side computation is needed for these two kinds.
            try db.execute("""
            INSERT INTO nutrition_food_factor (food_ref, kind, value, qualifier, source_value,
                                               source_record, licence_group)
                SELECT food_ref, kind, value, qualifier, source_value, source_record, licence_group
                FROM bundle.nutrition_portion WHERE kind <> 'household_measure';
            """)
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
