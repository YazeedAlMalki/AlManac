import Foundation

/// Keep revision identity separate from content: a deliberate revert is a new event.
public enum Migration007_ConflictResolution: Migration {
    public static let version = 7
    public static let name = "conflict_resolution_and_deliberate_reverts"
    public static func up(_ db: Database) throws {
        try db.execute("DROP INDEX idx_lab_revision_fingerprint;")
        try db.execute("CREATE INDEX idx_lab_revision_fingerprint ON lab_observation_revision(observation_id, content_fingerprint);")
        try db.execute("ALTER TABLE lab_report_revision ADD COLUMN resolved_at TEXT;")
        try db.execute("ALTER TABLE lab_report_revision ADD COLUMN resolved_by TEXT;")
        try db.execute("ALTER TABLE lab_report_revision ADD COLUMN resolution_reason TEXT;")
    }
}
