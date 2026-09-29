import Foundation

/// Migration 045 — `notification_rule`, the per-type on/off switch behind
/// §14.2's "All types individually toggleable & time-adjustable" (BRD §6.14)
/// and the storage `NotificationRuleStore` reads.
///
/// Spec §5.25, transcribed with the spec's own camelCase column names — the
/// same convention Migration014 onward uses for §5 tables, against the
/// snake_case of the earlier repo-owned tables. `docs/architecture/
/// spec-reconciliation.md` §3 holds that naming split as a deferred decision.
///
/// **The default rows are the spec's own table, verbatim** (§5.25's "Default
/// notification_rule rows (inserted in Migration_001)"). Readiness, water,
/// suhoor and iftar start on; meal, bedtime, supplement, contextual_snack and
/// contextual_hydration start off. Those are the spec's decisions, not this
/// migration's: water is on because a hydration prompt is the least intrusive
/// thing the app can say, and every meal- or context-shaped reminder is off
/// because a wrong one is worse than a missing one.
///
/// **The four `suppressDuring*` columns are created but never read.** Appendix B
/// is the authority on what suppresses what, and
/// `NotificationSuppressionMatrix` already transcribes it as pure logic with
/// its own tests. Storing a second, per-row copy of that matrix would be a
/// second source of truth for the same rule that could disagree with the first,
/// so these columns are left at their spec defaults and nothing writes them.
/// They exist because §5.25 names them, not because anything needs them; the
/// reconciliation note is in `docs/features/notifications.md`.
///
/// The spec's placement ("inserted in Migration_001") is not followed: 001 is
/// frozen, and every §5 table this repo has needed since has come as its own
/// numbered migration. Nothing has shipped, so the renumbering the spec
/// implies is still free, and still not urgent.
public enum Migration045_NotificationRule: Migration {
    public static let version = 45
    public static let name = "notification_rule"

    /// The §5.25 default table, in the spec's own column order. `type` is the
    /// `NotificationType` raw value, so these keys are the same strings the
    /// suppression matrix and the trigger assembler already speak.
    static let defaults: [(type: String, isEnabled: Bool, suppressDuringDryFast: Bool,
                           suppressDuringConfirmedFast: Bool)] = [
        ("readiness", true, false, false),
        ("water", true, true, false),
        ("suhoor", true, false, false),
        ("iftar", true, false, false),
        ("meal", false, false, true),
        ("bedtime", false, false, false),
        ("supplement", false, false, false),
        ("contextual_snack", false, false, true),
        ("contextual_hydration", false, true, false)
    ]

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE notification_rule (
            id                             INTEGER PRIMARY KEY,
            type                           TEXT NOT NULL UNIQUE,
            isEnabled                      INTEGER NOT NULL DEFAULT 0,
            scheduledTimeHHMM              TEXT,
            intervalMinutes                INTEGER,
            suppressDuringConfirmedFast    INTEGER NOT NULL DEFAULT 0,
            suppressDuringDryFast          INTEGER NOT NULL DEFAULT 0,
            suppressDuringNightShift       INTEGER NOT NULL DEFAULT 0,
            suppressDuringPostShiftSleep   INTEGER NOT NULL DEFAULT 0,
            createdAt                      TEXT NOT NULL,
            updatedAt                      TEXT NOT NULL
        );
        """)

        let now = ISO8601DateFormatter().string(from: Date())
        try db.run(
            """
            INSERT INTO notification_rule
                (type, isEnabled, suppressDuringDryFast, suppressDuringConfirmedFast, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            each: defaults.map { rule in
                [
                    .text(rule.type),
                    .integer(rule.isEnabled ? 1 : 0),
                    .integer(rule.suppressDuringDryFast ? 1 : 0),
                    .integer(rule.suppressDuringConfirmedFast ? 1 : 0),
                    .text(now),
                    .text(now)
                ] as [SQLValue]
            })
    }
}
