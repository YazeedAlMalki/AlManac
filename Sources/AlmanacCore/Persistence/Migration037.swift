import Foundation

/// Adds the timezone identifier needed to interpret a HealthKit sample's
/// instant safely. The older `timezoneOffset` column is not enough for
/// reconciliation across daylight-saving transitions.
public enum Migration037_HealthSampleTimezoneIdentifier: Migration {
    public static let version = 37
    public static let name = "health_sample_timezone_identifier"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE body_composition_measurement ADD COLUMN timezoneIdentifier TEXT;")
        try db.execute("ALTER TABLE vitals_record ADD COLUMN timezoneIdentifier TEXT;")
    }
}
