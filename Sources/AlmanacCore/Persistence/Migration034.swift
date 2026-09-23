import Foundation

/// Migration 034 — `exerciseCatalog.licenseAuthor`.
///
/// wger licenses each exercise separately and names an author per row
/// (`license_author` in its own API), and the Attributions requirement says
/// that field must survive every processing stage into the app database so a
/// per-exercise credit line — or the Attributions page's per-author list —
/// can show it. Nullable on purpose: a CC0 row needs no author, and Almanac's
/// own future `almanac:` exercises have none either.
public enum Migration034_ExerciseLicenseAuthor: Migration {
    public static let version = 34
    public static let name = "exercise_license_author"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE exerciseCatalog ADD COLUMN licenseAuthor TEXT;")
    }
}
