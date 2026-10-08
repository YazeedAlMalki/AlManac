import Testing
import Foundation
@testable import AlmanacCore

/// `NotificationRuleStore` over the rows Migration045 seeds. The default table
/// is the spec's (§5.25), so "the seeded default is right" is a claim about the
/// spec and gets tested as one.
@Suite("NotificationRuleStore Tests")
struct NotificationRuleStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    private var store: NotificationRuleStore { NotificationRuleStore(db: db) }

    @Test("Every type has a row after migration, and there is exactly one per type")
    func seededOneRowPerType() throws {
        let rules = try store.allRules()
        #expect(rules.count == NotificationType.allCases.count)
        #expect(Set(rules.map(\.type)) == Set(NotificationType.allCases))

        let rowCount = try db.query("SELECT COUNT(*) AS n FROM notification_rule;").first?.int("n")
        #expect(rowCount == Int64(NotificationType.allCases.count))
    }

    @Test("The seeded defaults are the spec's §5.25 table")
    func seededDefaultsMatchSpec() throws {
        // `prayer` (Migration050) is not in §5.25 and starts off.
        let expectedEnabled: Set<NotificationType> = [.readiness, .water, .suhoor, .iftar]
        for rule in try store.allRules() {
            #expect(rule.isEnabled == expectedEnabled.contains(rule.type), "\(rule.type)")
        }
    }

    @Test("The Swift default table and the migrations' INSERTs cannot drift apart")
    func swiftDefaultsMatchMigrationDefaults() throws {
        // Migration045 seeds the spec's nine; Migration050 seeds `prayer`.
        let seeded = Migration045_NotificationRule.defaults + Migration050_PrayerPreferences.defaults
        #expect(seeded.count == NotificationType.allCases.count)
        #expect(Set(seeded.map(\.type)) == Set(NotificationType.allCases.map(\.rawValue)))
        for (rawType, isEnabled, _, _) in seeded {
            guard let type = NotificationType(rawValue: rawType) else {
                Issue.record("Migration045 seeds \(rawType), which is not a NotificationType")
                continue
            }
            #expect(NotificationRuleStore.defaultRule(for: type).isEnabled == isEnabled, "\(type)")
        }
    }

    @Test("A missing row reads back as the documented default rather than as absent")
    func missingRowSynthesizesDefault() throws {
        try db.run("DELETE FROM notification_rule WHERE type = 'water';")
        #expect(try store.rule(for: .water).isEnabled)
        #expect(try store.rule(for: .meal).isEnabled == false)
    }

    @Test("setRule round-trips the enabled flag, the time and the interval")
    func roundTrip() throws {
        try store.setRule(NotificationRule(type: .bedtime, isEnabled: true,
                                           scheduledMinuteOfDay: 22 * 60 + 15, intervalMinutes: 45))
        let read = try store.rule(for: .bedtime)
        #expect(read.isEnabled)
        #expect(read.scheduledMinuteOfDay == 22 * 60 + 15)
        #expect(read.intervalMinutes == 45)
    }

    @Test("A minute-of-day is stored in the spec's own HH:MM text")
    func storedAsHHMM() throws {
        try store.setRule(NotificationRule(type: .bedtime, isEnabled: true, scheduledMinuteOfDay: 7 * 60 + 5))
        let raw = try db.query("SELECT scheduledTimeHHMM AS t FROM notification_rule WHERE type = 'bedtime';")
            .first?.string("t")
        #expect(raw == "07:05")
        #expect(try store.rule(for: .bedtime).scheduledMinuteOfDay == 425)
    }

    @Test("An out-of-range minute of day is rejected rather than clamped")
    func rejectsOutOfRangeMinute() throws {
        #expect(throws: NotificationRuleStoreError.invalidMinuteOfDay(1440)) {
            try store.setRule(NotificationRule(type: .bedtime, isEnabled: true, scheduledMinuteOfDay: 1440))
        }
        #expect(throws: NotificationRuleStoreError.invalidMinuteOfDay(-1)) {
            try store.setRule(NotificationRule(type: .bedtime, isEnabled: true, scheduledMinuteOfDay: -1))
        }
    }

    @Test("A non-positive interval is rejected")
    func rejectsNonPositiveInterval() throws {
        #expect(throws: NotificationRuleStoreError.invalidInterval(0)) {
            try store.setRule(NotificationRule(type: .water, isEnabled: true, intervalMinutes: 0))
        }
    }

    @Test("Toggling the switch leaves a time the user already chose alone")
    func togglePreservesTime() throws {
        try store.setRule(NotificationRule(type: .bedtime, isEnabled: true, scheduledMinuteOfDay: 22 * 60 + 15))
        try store.setEnabled(false, for: .bedtime)
        #expect(try store.rule(for: .bedtime).scheduledMinuteOfDay == 22 * 60 + 15)
        try store.setEnabled(true, for: .bedtime)
        #expect(try store.rule(for: .bedtime).scheduledMinuteOfDay == 22 * 60 + 15)
    }

    @Test("Corrupt HH:MM text reads as no time chosen, not as a crash")
    func corruptTextIsNil() throws {
        try store.setRule(NotificationRule(type: .bedtime, isEnabled: true, scheduledMinuteOfDay: 22 * 60))
        try db.run("UPDATE notification_rule SET scheduledTimeHHMM = 'half past seven' WHERE type = 'bedtime';")
        #expect(try store.rule(for: .bedtime).scheduledMinuteOfDay == nil)
        // The enabled flag is a separate column and survives the corruption.
        #expect(try store.rule(for: .bedtime).isEnabled)
    }

    @Test("Nothing writes the four suppressDuring columns, so they cannot become a second matrix")
    func suppressionColumnsAreNeverWritten() throws {
        try store.setRule(NotificationRule(type: .water, isEnabled: true, intervalMinutes: 60))
        let row = try db.query("""
            SELECT suppressDuringDryFast AS dry, suppressDuringConfirmedFast AS ifFast,
                   suppressDuringNightShift AS night, suppressDuringPostShiftSleep AS postShift
            FROM notification_rule WHERE type = 'water';
            """).first
        #expect(row?.int("dry") == 1, "the spec's own water default")
        #expect(row?.int("ifFast") == 0)
        #expect(row?.int("night") == 0)
        #expect(row?.int("postShift") == 0)
    }
}
