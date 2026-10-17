import Foundation

/// What the supplement plan editor does when a person sets a reminder.
///
/// A plan's reminder only reaches the planner when the `supplement` type is on
/// too (§5.25 seeds it off), so a person who sets "remind me at 21:00" on a
/// plan and hears nothing has been let down by a switch on a different screen.
/// Setting a plan's reminder **on** therefore turns the type on as well;
/// turning one plan's reminder off leaves the type alone, because other plans
/// may still want it. Unconfirmed — `CONTEXT.md`, "Supplements (2026-10-15)".
///
/// Both writes happen in one transaction, so a refused time changes nothing.
public struct SupplementReminderSetting: @unchecked Sendable {
    let db: Database

    public init(db: Database) { self.db = db }

    public func set(planId: Int64, enabled: Bool, minuteOfDay: Int?) throws {
        try db.transaction {
            try SupplementPlanStore(db: db).setReminder(id: planId, enabled: enabled,
                                                        reminderMinuteOfDay: minuteOfDay)
            if enabled {
                try NotificationRuleStore(db: db).setEnabled(true, for: .supplement)
            }
        }
    }
}
