import Foundation

public enum Migration041_BodyMeasurements: Migration {
    public static let version = 41
    public static let name = "body_measurements"

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE profile ADD COLUMN bodyMeasurementTrackSides INTEGER NOT NULL DEFAULT 0
            CHECK (bodyMeasurementTrackSides IN (0, 1));
        CREATE TABLE body_measurement (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            measured_at TEXT NOT NULL,
            logical_day TEXT NOT NULL,
            measurement_type TEXT NOT NULL CHECK (measurement_type IN
                ('waist', 'chest', 'hips', 'neck', 'arm', 'thigh', 'calf')),
            side TEXT CHECK (side IN ('left', 'right')),
            value_cm REAL NOT NULL CHECK (value_cm > 0),
            source TEXT NOT NULL CHECK (source IN ('manual', 'healthkit')),
            source_identifier TEXT UNIQUE,
            note TEXT,
            is_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_edited IN (0, 1)),
            CHECK (side IS NULL OR measurement_type IN ('arm', 'thigh')),
            CHECK (source = 'manual' OR
                (measurement_type = 'waist' AND source_identifier IS NOT NULL AND is_edited = 0)),
            CHECK (source_identifier IS NULL OR measurement_type = 'waist')
        );
        CREATE INDEX idx_body_measurement_day ON body_measurement(logical_day, measured_at);
        """)
        // A manual waist row also keeps its exported HealthKit UUID in source_identifier.
    }
}
