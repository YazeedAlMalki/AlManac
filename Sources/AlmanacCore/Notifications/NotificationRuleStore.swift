import Foundation

/// A `notification_rule` row: whether one notification type is on, and the
/// optional user-set times §14.2 gives that type.
///
/// `scheduledMinuteOfDay` is minutes since local midnight, not the spec's
/// `"HH:MM"` text — the same decision `meal_reminder_setting.reminderMinuteOfDay`
/// (Migration029) already made and for the same reason: every other time in
/// this repo is arithmetic before it is text, and a `"07:30"` string would make
/// the trigger assembler parse what the schema could have stored. The spec's
/// column is kept under its own name; only the encoding differs.
public struct NotificationRule: Sendable, Hashable, Identifiable {
    public let type: NotificationType
    public let isEnabled: Bool
    /// The one fixed time this type fires at, when the user has set one. Nil
    /// is a real state, not an absence: a type can be on and still have nothing
    /// to fire at.
    public let scheduledMinuteOfDay: Int?
    /// Interval-based types (water) get their cadence here rather than from
    /// their own type's settings table; nil falls back to that type's rule.
    public let intervalMinutes: Int?
    public let updatedAt: Date

    public var id: String { type.rawValue }

    public init(type: NotificationType, isEnabled: Bool, scheduledMinuteOfDay: Int? = nil,
                intervalMinutes: Int? = nil, updatedAt: Date = Date()) {
        self.type = type
        self.isEnabled = isEnabled
        self.scheduledMinuteOfDay = scheduledMinuteOfDay
        self.intervalMinutes = intervalMinutes
        self.updatedAt = updatedAt
    }
}

/// Reads and writes the `notification_rule` rows (Migration045) — the per-type
/// on/off switch BRD §6.14 requires ("All types individually toggleable") and
/// §14.2's per-type "Default: OFF"/"Default: ON" statements describe.
///
/// **Self-healing, like every other settings store here.** Nothing is seeded at
/// a call site: Migration045 inserts the §5.25 default rows, and `rule(for:)`
/// synthesizes the default again if a row is somehow absent, so no caller has to
/// distinguish "not configured" from "configured off" — for a notification the
/// two mean the same thing, which is the whole of what this store decides.
///
/// Deliberately *not* a second copy of Appendix B. Its four `suppressDuring*`
/// columns exist because §5.25 names them, and are never written or read;
/// `NotificationSuppressionMatrix` is the one authority on what suppresses
/// what. Two writable copies of the same matrix is a rule that can disagree
/// with itself, which is worse than no user control over it at all.
public struct NotificationRuleStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: clock.now)
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// §5.25's default table, as data. This is the one place the spec's
    /// defaults are stated in Swift; Migration045 has its own copy for the
    /// INSERT because a migration must not depend on a type that can change
    /// under it. `testSeededRulesMatchTheDocumentedDefaults` is what keeps the
    /// two from drifting.
    public static func defaultRule(for type: NotificationType) -> NotificationRule {
        let enabled: Bool
        switch type {
        case .readiness, .water, .suhoor, .iftar: enabled = true
        case .meal, .bedtime, .supplement, .contextualSnack, .contextualHydration, .prayer: enabled = false
        }
        return NotificationRule(type: type, isEnabled: enabled)
    }

    /// `type`'s stored rule, or the §5.25 default when no row exists.
    public func rule(for type: NotificationType) throws -> NotificationRule {
        guard let row = try db.query("""
            SELECT type, isEnabled, scheduledTimeHHMM, intervalMinutes, updatedAt
            FROM notification_rule WHERE type = ?;
            """, [.text(type.rawValue)]).first else {
            return Self.defaultRule(for: type)
        }
        return NotificationRule(
            type: type,
            isEnabled: (row.int("isEnabled") ?? 0) != 0,
            scheduledMinuteOfDay: Self.minuteOfDay(row.string("scheduledTimeHHMM")),
            intervalMinutes: row.int("intervalMinutes").map(Int.init),
            updatedAt: row.string("updatedAt").flatMap(iso8601ToDate) ?? clock.now)
    }

    /// Every type's rule, in `NotificationType.allCases` order — one entry per
    /// type, whether or not rows exist for all of them.
    public func allRules() throws -> [NotificationRule] {
        try NotificationType.allCases.map { try rule(for: $0) }
    }

    /// Whether `type` is on. The one call the scheduler makes per type, kept as
    /// a method of its own because it is the only question this store exists to
    /// answer for most callers.
    public func isEnabled(_ type: NotificationType) throws -> Bool {
        try rule(for: type).isEnabled
    }

    /// Upserts `type`'s rule. `scheduledMinuteOfDay` is validated to
    /// `0..<1440` when non-nil, for the same reason
    /// `MealReminderSettingsStore.setReminder` validates: an out-of-range value
    /// is a caller bug, and silently clamping it would schedule a reminder at a
    /// time the user did not ask for.
    public func setRule(_ rule: NotificationRule) throws {
        if let minute = rule.scheduledMinuteOfDay {
            guard (0..<1440).contains(minute) else {
                throw NotificationRuleStoreError.invalidMinuteOfDay(minute)
            }
        }
        if let interval = rule.intervalMinutes, interval <= 0 {
            throw NotificationRuleStoreError.invalidInterval(interval)
        }
        let now = nowText
        try db.run("""
        INSERT INTO notification_rule
            (type, isEnabled, scheduledTimeHHMM, intervalMinutes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(type) DO UPDATE SET
            isEnabled = excluded.isEnabled,
            scheduledTimeHHMM = excluded.scheduledTimeHHMM,
            intervalMinutes = excluded.intervalMinutes,
            updatedAt = excluded.updatedAt;
        """, [
            .text(rule.type.rawValue),
            .integer(rule.isEnabled ? 1 : 0),
            rule.scheduledMinuteOfDay.map { SQLValue.text(Self.hhmm($0)) } ?? .null,
            rule.intervalMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(now),
            .text(now)
        ])
    }

    /// Flips only the on/off switch, leaving any time the user has set alone.
    /// The shape every toggle in the UI wants: a user turning meal reminders
    /// off and on again should not silently lose the 07:30 they chose.
    public func setEnabled(_ enabled: Bool, for type: NotificationType) throws {
        let existing = try rule(for: type)
        try setRule(NotificationRule(type: type, isEnabled: enabled,
                                     scheduledMinuteOfDay: existing.scheduledMinuteOfDay,
                                     intervalMinutes: existing.intervalMinutes))
    }

    // MARK: - Private

    /// Minutes-since-midnight to the column's `"HH:MM"`. Zero-padded, matching
    /// the spec's own format string so a value read by hand out of the database
    /// looks like what the spec says it should.
    static func hhmm(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// The inverse, nil rather than a throw for unparseable text: a corrupt
    /// column should leave the rule "on, with no time chosen", which is the
    /// ordinary not-yet-configured state, not a crash on a settings read.
    static func minuteOfDay(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

public enum NotificationRuleStoreError: Error, Sendable, Equatable {
    case invalidMinuteOfDay(Int)
    case invalidInterval(Int)
}
