import Foundation

/// Migration 056 — which built-in circumference points the owner has hidden.
///
/// BRD §6.6 makes custom circumference measurements owner-priority and
/// "user-definable". The seven built-in points (`BodyMeasurementType`) carried
/// a fixed list; owner-defined points already live in
/// `custom_measurement_definition` (Migration018). What was missing is a way
/// to take a built-in point *off* the list. One row per hidden point; a point
/// with no row is shown. Hiding never touches `body_measurement`: a hidden
/// point's readings stay in the record and in its chart.
public enum Migration056_CircumferencePointVisibility: Migration {
    public static let version = 56
    public static let name = "circumference_point_visibility"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE circumference_point_hidden (
            measurement_type TEXT PRIMARY KEY,
            hidden_at        TEXT NOT NULL
        ) STRICT;
        """)
    }
}
