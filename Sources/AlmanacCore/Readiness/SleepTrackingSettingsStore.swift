import Foundation

/// Reading and updating the `sleep_tracking_settings` singleton (Migration025).
/// Self-healing like `PrayerSettingsStore`: a write ensures the id=1 row
/// exists first, since nothing seeds it at migration time.
public struct SleepTrackingSettingsStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Whether sleep tracking is on. Defaults to `true` (decision 1.1: wake
    /// detection is the default cycle-boundary source) when no row exists yet.
    public func isEnabled() throws -> Bool {
        guard let row = try db.query("SELECT enabled FROM sleep_tracking_settings WHERE id = 1;").first else {
            return true
        }
        return row.int("enabled") == 1
    }

    public func setEnabled(_ enabled: Bool) throws {
        try db.run("""
        INSERT INTO sleep_tracking_settings (id, enabled, updatedAt) VALUES (1, ?, ?)
        ON CONFLICT(id) DO UPDATE SET enabled = excluded.enabled, updatedAt = excluded.updatedAt;
        """, [.integer(enabled ? 1 : 0), .text(nowText)])
    }
}
