import Foundation

/// Migration 057 — the recovery days a person declares.
///
/// Technical Specification §9.6 ranks "Manually selected recovery day (user set
/// via UI)" second in precedence, below an active injury and above a planned
/// rest day. `ReadinessContext.manualRecoveryDay` and the engine's wording for it
/// existed from the start; nothing recorded a declaration, so the flag was
/// always false and the rule had never fired.
///
/// One row per declared logical day, keyed on the day as `mood_log` and
/// `soreness_log` are, so a declaration made the next morning about yesterday is
/// still yesterday's. A day with no row is not a recovery day. Clearing a
/// declaration deletes its row: it is a switch the person sets, not a reading
/// with a history, and the scored day's `readiness_record.precedenceApplied`
/// already records whether the rule held when the score was worked out.
public enum Migration057_RecoveryDayDeclaration: Migration {
    public static let version = 57
    public static let name = "recovery_day_declaration"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE recovery_day_declaration (
            logicalDay      TEXT PRIMARY KEY,
            declaredAt      TEXT NOT NULL,
            timezoneOffset  INTEGER
        ) STRICT;
        """)
    }
}
