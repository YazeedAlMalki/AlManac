import Foundation

/// Migration 068 — the person's email address on their profile.
///
/// The owner's rule (2026-10-20): backups are for a person "registered with a
/// valid email". Nullable, because no install has one yet and a migration
/// cannot invent it. Kept on this phone only: nothing sends it anywhere.
public enum Migration068_ProfileEmail: Migration {
    public static let version = 68
    public static let name = "profile_email"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE profile ADD COLUMN email TEXT;")
    }
}
