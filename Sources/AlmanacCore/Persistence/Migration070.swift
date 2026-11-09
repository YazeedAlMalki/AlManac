import Foundation

/// Migration 070 — night-shift runs (shifts-profile spec, sections 3 and 4).
///
/// Additive only.
///
/// ## `shift_schedule.nightRunCapPercent`
///
/// The most a run of night shifts may take off a day's readiness score, as a
/// percentage of that score. One cap for every saved pattern, so it lives on
/// the schedule rather than on each pattern. Null means "not set", and the
/// app's default applies (`NightRunStore.defaultCapPercent`).
///
/// ## `notification_rule` row `night_run`
///
/// The warning when a run of nights passes its run length, sent the evening
/// before and on the night itself. Seeded **on**: the spec has the app send it.
/// `INSERT OR IGNORE`, as in Migration050.
public enum Migration070_NightRuns: Migration {
    public static let version = 70
    public static let name = "night_runs"

    static let defaults: [(type: String, isEnabled: Bool, suppressDuringDryFast: Bool,
                           suppressDuringConfirmedFast: Bool)] = [
        ("night_run", true, false, false)
    ]

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE shift_schedule ADD COLUMN nightRunCapPercent REAL
            CHECK (nightRunCapPercent IS NULL OR (nightRunCapPercent > 0 AND nightRunCapPercent <= 100));
        """)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())
        for rule in defaults {
            try db.run("""
            INSERT OR IGNORE INTO notification_rule
                (type, isEnabled, suppressDuringDryFast, suppressDuringConfirmedFast, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?);
            """, [
                .text(rule.type),
                .integer(rule.isEnabled ? 1 : 0),
                .integer(rule.suppressDuringDryFast ? 1 : 0),
                .integer(rule.suppressDuringConfirmedFast ? 1 : 0),
                .text(now),
                .text(now)
            ])
        }
    }
}
