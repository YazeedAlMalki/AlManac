import Foundation

/// Migration 050 — the prayer-time preferences §12 left without storage, and
/// the prayer-time alert.
///
/// ## `prayer_settings.asrMethod`
///
/// §5.22 stores a calculation method and five offsets, and nothing for Asr's
/// juristic rule. The method decides Fajr and Isha; it does not decide Asr,
/// which is one shadow-length (Shafi'i, Maliki, Hanbali) or two (Hanafi). A
/// Hanafi user had no way to say so, and was shown an Asr about an hour before
/// their school's. `'standard'` is the default because it is Umm al-Qura's own
/// convention, which is §12.1's default method.
///
/// ## `prayer_settings.alertPrayers`
///
/// Which of the five prayers raise an alert at their time, as a comma-separated
/// list of `prayer_times_cache` column names. Every prayer by default: the
/// switch that decides whether *any* alert is sent is the `prayer`
/// notification rule below, and it starts off. A list rather than five
/// columns because the only reader asks "is this prayer in it", and a sixth
/// name (sunrise) must stay unrepresentable as an alert rather than become a
/// column someone can turn on.
///
/// ## `notification_rule` row `prayer`
///
/// BRD §6.13 asks for a prayer-time engine and §6.14 for every notification
/// type to be individually switchable. Seeded **off**: like every reminder the
/// spec did not name, a wrong or unwanted one is worse than a missing one, and
/// the user turning it on is the moment the permission prompt belongs to.
/// `INSERT OR IGNORE`, so a row the store already self-healed into existence is
/// left exactly as the user set it.
public enum Migration050_PrayerPreferences: Migration {
    public static let version = 50
    public static let name = "prayer_preferences"

    /// The seeded rule, in Migration045's shape so the rule-store test can hold
    /// the two migrations' defaults against the Swift table together.
    static let defaults: [(type: String, isEnabled: Bool, suppressDuringDryFast: Bool,
                           suppressDuringConfirmedFast: Bool)] = [
        ("prayer", false, false, false)
    ]

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE prayer_settings ADD COLUMN asrMethod TEXT NOT NULL DEFAULT 'standard';")
        try db.execute("""
        ALTER TABLE prayer_settings ADD COLUMN alertPrayers TEXT NOT NULL DEFAULT 'fajr,dhuhr,asr,maghrib,isha';
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
