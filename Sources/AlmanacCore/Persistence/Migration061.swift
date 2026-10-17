import Foundation

/// Migration 061 — the name an external code is shown and stored with.
///
/// The owner accepted LOINC's licence on 2026-10-16 (G5). It requires that
/// "any information that is extracted from the Licensed Material must always be
/// associated with the corresponding identifier from LOINC … and include the
/// corresponding LOINC display name" — for a LOINC code, one of its LOINC names,
/// such as the long common name. `lab_catalog_external_code` held only the
/// code, so a seeded LOINC code could not have met that. Nullable: a code from
/// a system with no such rule needs none.
public enum Migration061_ExternalCodeDisplayName: Migration {
    public static let version = 61
    public static let name = "external_code_display_name"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE lab_catalog_external_code ADD COLUMN display_name TEXT;")
    }
}
