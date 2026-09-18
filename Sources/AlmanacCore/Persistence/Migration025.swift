import Foundation

/// Migration 025 — `sleep_tracking_settings`, the "Track sleep" toggle
/// (Ticket 1, 2026-09-18 handoff, decision 1.3).
///
/// A singleton row, same shape and self-healing pattern as `prayer_settings`
/// (Migration024) and `profile`: nothing seeds it here, `SleepTrackingSettingsStore`
/// inserts the id=1 row on first write. Named and cased like the rest of the
/// Readiness/Sleep domain (`readiness_cycle`, `sleep_episode`) — snake_case
/// table, camelCase columns — not like Training's camelCase tables.
public enum Migration025_SleepTrackingSettings: Migration {
    public static let version = 25
    public static let name = "sleep_tracking_settings"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE sleep_tracking_settings (
            id          INTEGER PRIMARY KEY DEFAULT 1,
            enabled     INTEGER NOT NULL DEFAULT 1,
            updatedAt   TEXT NOT NULL
        );
        """)
    }
}
