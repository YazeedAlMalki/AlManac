import Foundation

/// Migration 069 — saved shift patterns (shifts-profile spec, section 2).
///
/// Additive only: one new table, nullable columns on two existing ones, and a
/// notification rule. No existing row is rewritten.
///
/// ## `saved_shift_pattern`
///
/// A named pattern: blocks of consecutive days on one shift (`blocks`, a JSON
/// array of `{"shift": …, "days": …}`), a start date the person picks, a
/// cadence (`weekly` or `monthly`, counted from that date) and a run length in
/// nights. `runLengthNights` is nullable: "not set" is an answer, and the app's
/// default applies to it rather than being written in.
///
/// ## `shift_recurrence_pattern.savedPatternId`
///
/// The saved pattern a rule was written for. A rule with one is the only kind
/// `ShiftPatternExpander` expands with a weekly or monthly cadence; a
/// `monthly_rotation` without one is still refused.
///
/// ## `shift_schedule` selection columns
///
/// Which saved pattern is running (`currentSavedPatternId`, counted from
/// `currentSavedPatternAnchor`), which one the person set to run next, and the
/// day that next pattern starts by itself when the period-end reminder is off
/// (`nextSavedPatternStartsOn`). All null until a pattern is used.
///
/// ## `notification_rule` row `shift_pattern`
///
/// The reminder at the end of a pattern's week or month. Seeded **on**: the
/// spec has the app remind the person, and turning it off is what lets the
/// next pattern start by itself. `INSERT OR IGNORE`, as in Migration050.
public enum Migration069_SavedShiftPatterns: Migration {
    public static let version = 69
    public static let name = "saved_shift_patterns"

    /// The seeded rule, in Migration045's shape so the rule-store test can hold
    /// every migration's defaults against the Swift table together.
    static let defaults: [(type: String, isEnabled: Bool, suppressDuringDryFast: Bool,
                           suppressDuringConfirmedFast: Bool)] = [
        ("shift_pattern", true, false, false)
    ]

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE saved_shift_pattern (
            id               INTEGER PRIMARY KEY,
            scheduleId       INTEGER NOT NULL REFERENCES shift_schedule(id),
            name             TEXT NOT NULL CHECK (length(trim(name)) > 0),
            blocks           TEXT NOT NULL,
            startDate        TEXT NOT NULL,
            cadence          TEXT NOT NULL CHECK (cadence IN ('weekly', 'monthly')),
            runLengthNights  INTEGER CHECK (runLengthNights IS NULL OR runLengthNights > 0),
            createdAt        TEXT NOT NULL,
            updatedAt        TEXT NOT NULL
        );
        """)
        try db.execute("""
        ALTER TABLE shift_recurrence_pattern
            ADD COLUMN savedPatternId INTEGER REFERENCES saved_shift_pattern(id);
        """)
        try db.execute("""
        ALTER TABLE shift_schedule
            ADD COLUMN currentSavedPatternId INTEGER REFERENCES saved_shift_pattern(id);
        """)
        try db.execute("ALTER TABLE shift_schedule ADD COLUMN currentSavedPatternAnchor TEXT;")
        try db.execute("""
        ALTER TABLE shift_schedule
            ADD COLUMN nextSavedPatternId INTEGER REFERENCES saved_shift_pattern(id);
        """)
        try db.execute("ALTER TABLE shift_schedule ADD COLUMN nextSavedPatternStartsOn TEXT;")

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
