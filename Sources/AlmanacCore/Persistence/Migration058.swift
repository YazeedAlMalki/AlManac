import Foundation

/// Migration 058 — how far a prayer-anchored reminder sits from its prayer.
///
/// BRD §6.14 makes every reminder "time-adjustable". Suhoor and iftar are not
/// at a clock time: §14.2 puts suhoor 20 minutes before Fajr and iftar at
/// Maghrib, and both prayers move every day. A fixed time in
/// `scheduledTimeHHMM` would drift off them (a 04:10 suhoor reminder fires
/// after Fajr by the end of a summer), so what a person adjusts is the
/// distance: minutes before Fajr for suhoor, minutes after Maghrib for iftar.
/// Null is "the spec's own distance". Other types leave it null.
public enum Migration058_NotificationRuleOffset: Migration {
    public static let version = 58
    public static let name = "notification_rule_offset"

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE notification_rule ADD COLUMN offsetMinutes INTEGER;
        """)
    }
}
