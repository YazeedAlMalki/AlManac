import Foundation

/// Carries the recorded zone context for custom measurement timestamps.
public enum Migration038_CustomMeasurementTimezone: Migration {
    public static let version = 38
    public static let name = "custom_measurement_timezone"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE custom_measurement_log ADD COLUMN timezoneOffset TEXT;")
        try db.execute("ALTER TABLE custom_measurement_log ADD COLUMN timezoneIdentifier TEXT;")
    }
}
