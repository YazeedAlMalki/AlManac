import Foundation

/// Persists the single user-controlled Activity Rings display setting.
public enum Migration039_ActivityRingSettings: Migration {
    public static let version = 39
    public static let name = "activity_ring_settings"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE activity_ring_settings (
            id                  TEXT PRIMARY KEY CHECK (id = 'local'),
            digestion_enabled   INTEGER NOT NULL DEFAULT 0 CHECK (digestion_enabled IN (0, 1)),
            updated_at          TEXT NOT NULL
        );
        """)
    }
}
