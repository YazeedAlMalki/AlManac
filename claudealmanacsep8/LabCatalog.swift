import Foundation

/// A catalog entry. `id` is an Almanac-owned string that is stable for the
/// life of the product; external codes are optional, live in their own table,
/// and are only trusted for matching once verified.
public struct CatalogAnalyte: Sendable, Hashable {
    public let id: String
    public let canonicalName: String
    public let family: String
    public let subfamily: String?
    /// The distinct measurable form, where a family has more than one.
    /// "25-OH D3" and "1,25-dihydroxy D" are different analytes, not one.
    public let form: String?
    public let defaultValueType: LabValueType
    /// What the entry measures: the substance, a precursor of it, or a marker
    /// of its status. Not every entry in a vitamin family is a vitamin
    /// measurement, and the difference decides what may be trended together.
    public let measurementRole: MeasurementRole
    public let notes: String?

    public init(id: String, canonicalName: String, family: String,
                subfamily: String? = nil, form: String? = nil,
                defaultValueType: LabValueType = .quantitative,
                measurementRole: MeasurementRole = .direct, notes: String? = nil) {
        self.measurementRole = measurementRole
        self.id = id
        self.canonicalName = canonicalName
        self.family = family
        self.subfamily = subfamily
        self.form = form
        self.defaultValueType = defaultValueType
        self.notes = notes
    }
}

public struct CatalogMatch: Sendable, Hashable {
    public let analyteID: String
    public let origin: String        // "alias" | "external_code" | "user"
    public let confidence: String    // "exact_alias" | "verified_code" | "user_assigned"
}

public struct LabCatalogStore: Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }

    public func upsert(_ analyte: CatalogAnalyte) throws {
        try db.run("""
        INSERT INTO lab_catalog_analyte
            (id, canonical_name, family, subfamily, form, default_value_type,
             measurement_role, notes, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            canonical_name = excluded.canonical_name,
            family = excluded.family,
            subfamily = excluded.subfamily,
            form = excluded.form,
            default_value_type = excluded.default_value_type,
            measurement_role = excluded.measurement_role,
            notes = excluded.notes;
        """, [
            .text(analyte.id), .text(analyte.canonicalName), .text(analyte.family),
            analyte.subfamily.map { SQLValue.text($0) } ?? .null,
            analyte.form.map { SQLValue.text($0) } ?? .null,
            .text(analyte.defaultValueType.rawValue),
            .text(analyte.measurementRole.rawValue),
            analyte.notes.map { SQLValue.text($0) } ?? .null,
            .text(nowText)
        ])
    }

    public func addAlias(_ text: String, to analyteID: String,
                         locale: String? = nil, origin: String = "almanac") throws {
        try db.run("""
        INSERT INTO lab_catalog_alias (id, analyte_id, alias_text, alias_fold, locale, origin)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(analyte_id, alias_fold) DO UPDATE SET alias_text = excluded.alias_text;
        """, [
            .text(UUID().uuidString), .text(analyteID), .text(text),
            .text(TextFold.fold(text)),
            locale.map { SQLValue.text($0) } ?? .null, .text(origin)
        ])
    }

    /// External codes are stored unverified by default and are **not** used for
    /// matching until someone verifies them. No code is seeded unverified as
    /// though it were confirmed.
    public func addExternalCode(system: String, code: String, to analyteID: String,
                                verified: Bool = false, verifiedBy: String? = nil) throws {
        try db.run("""
        INSERT INTO lab_catalog_external_code
            (analyte_id, system, code, verified, verified_at, verified_by)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(analyte_id, system, code) DO UPDATE SET
            verified = excluded.verified,
            verified_at = excluded.verified_at,
            verified_by = excluded.verified_by;
        """, [
            .text(analyteID), .text(system), .text(code),
            .integer(verified ? 1 : 0),
            verified ? .text(nowText) : .null,
            verifiedBy.map { SQLValue.text($0) } ?? .null
        ])
    }

    public func setLocalizedName(_ name: String, for analyteID: String, locale: String) throws {
        try db.run("""
        INSERT INTO lab_catalog_localization (analyte_id, locale, name) VALUES (?, ?, ?)
        ON CONFLICT(analyte_id, locale) DO UPDATE SET name = excluded.name;
        """, [.text(analyteID), .text(locale), .text(name)])
    }

    public func localizedName(for analyteID: String, locale: String) throws -> String? {
        try db.query("SELECT name FROM lab_catalog_localization WHERE analyte_id = ? AND locale = ?;",
                     [.text(analyteID), .text(locale)]).first?.string("name")
    }

    /// Alias lookup, folded. Returns nil rather than a nearest guess.
    public func match(sourceText: String?) throws -> CatalogMatch? {
        guard let sourceText, !sourceText.isEmpty else { return nil }
        let folded = TextFold.fold(sourceText)
        guard !folded.isEmpty else { return nil }
        if let row = try db.query(
            "SELECT analyte_id FROM lab_catalog_alias WHERE alias_fold = ? LIMIT 1;",
            [.text(folded)]).first, let id = row.string("analyte_id") {
            return CatalogMatch(analyteID: id, origin: "alias", confidence: "exact_alias")
        }
        return nil
    }

    public func matchExternalCode(system: String, code: String) throws -> CatalogMatch? {
        guard let row = try db.query("""
            SELECT analyte_id FROM lab_catalog_external_code
            WHERE system = ? AND code = ? AND verified = 1 LIMIT 1;
            """, [.text(system), .text(code)]).first,
            let id = row.string("analyte_id") else { return nil }
        return CatalogMatch(analyteID: id, origin: "external_code", confidence: "verified_code")
    }

    public func analyte(_ id: String) throws -> CatalogAnalyte? {
        guard let row = try db.query("""
            SELECT id, canonical_name, family, subfamily, form, default_value_type,
                   measurement_role, notes
            FROM lab_catalog_analyte WHERE id = ?;
            """, [.text(id)]).first,
            let rid = row.string("id"), let name = row.string("canonical_name"),
            let family = row.string("family") else { return nil }
        return CatalogAnalyte(
            id: rid, canonicalName: name, family: family,
            subfamily: row.string("subfamily"), form: row.string("form"),
            defaultValueType: LabValueType(rawValue: row.string("default_value_type") ?? "")
                ?? .quantitative,
            measurementRole: MeasurementRole(rawValue: row.string("measurement_role") ?? "")
                ?? .direct,
            notes: row.string("notes"))
    }

    /// Ids in a family whose entries actually measure the substance, excluding
    /// precursors and status markers.
    public func directAnalyteIDs(family: String) throws -> [String] {
        try db.query("""
        SELECT id FROM lab_catalog_analyte
        WHERE family = ? AND measurement_role = 'direct' ORDER BY id;
        """, [.text(family)]).compactMap { $0.string("id") }
    }

    public func measurementRole(of analyteID: String) throws -> MeasurementRole? {
        try db.query("SELECT measurement_role FROM lab_catalog_analyte WHERE id = ?;",
                     [.text(analyteID)]).first?.string("measurement_role")
            .flatMap(MeasurementRole.init(rawValue:))
    }

    public func analyteIDs(family: String? = nil) throws -> [String] {
        let rows = family == nil
            ? try db.query("SELECT id FROM lab_catalog_analyte ORDER BY id;")
            : try db.query("SELECT id FROM lab_catalog_analyte WHERE family = ? ORDER BY id;",
                           [.text(family!)])
        return rows.compactMap { $0.string("id") }
    }

    // MARK: - Panels

    public func createPanel(id: String, name: String, origin: String = "almanac",
                            analyteIDs: [String]) throws {
        try db.transaction {
            try db.run("""
            INSERT INTO lab_panel (id, name, origin, created_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name;
            """, [.text(id), .text(name), .text(origin), .text(nowText)])
            try db.run("DELETE FROM lab_panel_member WHERE panel_id = ?;", [.text(id)])
            for (index, analyteID) in analyteIDs.enumerated() {
                try db.run("""
                INSERT INTO lab_panel_member (panel_id, analyte_id, position) VALUES (?, ?, ?);
                """, [.text(id), .text(analyteID), .integer(Int64(index))])
            }
        }
    }

    public func panelMembers(_ panelID: String) throws -> [String] {
        try db.query("""
        SELECT analyte_id FROM lab_panel_member WHERE panel_id = ? ORDER BY position;
        """, [.text(panelID)]).compactMap { $0.string("analyte_id") }
    }
}
