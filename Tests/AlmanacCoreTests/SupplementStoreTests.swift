import Testing
import Foundation
@testable import AlmanacCore

@Suite("SupplementPlanStore Tests")
struct SupplementPlanStoreTests {
    let db = try! TestDatabase()
    var store: SupplementPlanStore { SupplementPlanStore(db: db) }

    @Test("Create a plan and read it back")
    func createPlan() throws {
        let draft = SupplementPlanDraft(name: "Vitamin D", doseAmount: 2000, doseUnit: "iu",
                                         frequency: "daily")
        let id = try store.create(draft)
        let plan = try store.plan(id: id)

        #expect(plan?.name == "Vitamin D")
        #expect(plan?.doseAmount == 2000)
        #expect(plan?.doseUnit == "iu")
        #expect(plan?.frequency == "daily")
        #expect(plan?.isActive == true)
    }

    @Test("Deactivate a plan rather than delete it")
    func deactivatePlan() throws {
        let id = try store.create(SupplementPlanDraft(name: "Creatine", doseAmount: 5, doseUnit: "g",
                                                        frequency: "daily"))
        try store.deactivate(id: id)

        let plan = try store.plan(id: id)
        #expect(plan?.isActive == false)
    }

    @Test("Active plans excludes deactivated ones")
    func activePlansExcludesDeactivated() throws {
        let keep = try store.create(SupplementPlanDraft(name: "Fish Oil", doseAmount: 1, doseUnit: "capsule",
                                                          frequency: "daily"))
        let drop = try store.create(SupplementPlanDraft(name: "Old Stack", doseAmount: 1, doseUnit: "capsule",
                                                          frequency: "daily"))
        try store.deactivate(id: drop)

        let active = try store.activePlans()
        #expect(active.map { $0.id } == [keep])
    }

    // MARK: - §14.2 Supplement Reminders (Migration030)

    @Test("A new plan's reminder defaults to off with no time set")
    func reminderDefaultsOff() throws {
        let id = try store.create(SupplementPlanDraft(name: "Magnesium", doseAmount: 400, doseUnit: "mg",
                                                        frequency: "daily"))
        let plan = try store.plan(id: id)
        #expect(plan?.reminderEnabled == false)
        #expect(plan?.reminderMinuteOfDay == nil)
    }

    @Test("setReminder turns a plan's reminder on with a time")
    func setReminderOnWithTime() throws {
        let id = try store.create(SupplementPlanDraft(name: "Magnesium", doseAmount: 400, doseUnit: "mg",
                                                        frequency: "daily"))
        try store.setReminder(id: id, enabled: true, reminderMinuteOfDay: 21 * 60) // 21:00

        let plan = try store.plan(id: id)
        #expect(plan?.reminderEnabled == true)
        #expect(plan?.reminderMinuteOfDay == 21 * 60)
    }

    @Test("setReminder rejects a minute-of-day outside 0..<1440")
    func setReminderRejectsInvalidMinute() throws {
        let id = try store.create(SupplementPlanDraft(name: "Magnesium", doseAmount: 400, doseUnit: "mg",
                                                        frequency: "daily"))
        #expect(throws: SupplementPlanStoreError.invalidMinuteOfDay(1440)) {
            try store.setReminder(id: id, enabled: true, reminderMinuteOfDay: 1440)
        }
    }

    @Test("activePlansWithReminders excludes plans that are inactive, off, or have no time set")
    func activePlansWithRemindersFiltering() throws {
        let onAndTimed = try store.create(SupplementPlanDraft(name: "A", doseAmount: 1, doseUnit: "capsule",
                                                                frequency: "daily"))
        try store.setReminder(id: onAndTimed, enabled: true, reminderMinuteOfDay: 480)

        let onNoTime = try store.create(SupplementPlanDraft(name: "B", doseAmount: 1, doseUnit: "capsule",
                                                              frequency: "daily"))
        try store.setReminder(id: onNoTime, enabled: true, reminderMinuteOfDay: nil)

        let offButTimed = try store.create(SupplementPlanDraft(name: "C", doseAmount: 1, doseUnit: "capsule",
                                                                 frequency: "daily"))
        try store.setReminder(id: offButTimed, enabled: false, reminderMinuteOfDay: 480)

        let deactivated = try store.create(SupplementPlanDraft(name: "D", doseAmount: 1, doseUnit: "capsule",
                                                                 frequency: "daily"))
        try store.setReminder(id: deactivated, enabled: true, reminderMinuteOfDay: 480)
        try store.deactivate(id: deactivated)

        let withReminders = try store.activePlansWithReminders()
        #expect(withReminders.map { $0.id } == [onAndTimed])
    }
}

@Suite("SupplementLogStore Tests")
struct SupplementLogStoreTests {
    let db = try! TestDatabase()
    var planStore: SupplementPlanStore { SupplementPlanStore(db: db) }
    var logStore: SupplementLogStore { SupplementLogStore(db: db) }

    @Test("Log adherence for a plan and read it back for a day")
    func logAdherence() throws {
        let planId = try planStore.create(SupplementPlanDraft(
            name: "Vitamin D", doseAmount: 2000, doseUnit: "iu", frequency: "daily"))

        _ = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-16")

        let entries = try logStore.entries(for: "2026-09-16")
        #expect(entries.count == 1)
        #expect(entries[0].planId == planId)
        #expect(entries[0].taken == true)
    }

    @Test("A skipped dose can be logged as not taken")
    func logSkippedDose() throws {
        let planId = try planStore.create(SupplementPlanDraft(
            name: "Creatine", doseAmount: 5, doseUnit: "g", frequency: "daily"))

        _ = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date(), taken: false),
                              logicalDay: "2026-09-16")

        let entries = try logStore.entries(for: "2026-09-16")
        #expect(entries[0].taken == false)
    }

    @Test("Adherence for a plan across a date range")
    func adherenceForPlanRange() throws {
        let planId = try planStore.create(SupplementPlanDraft(
            name: "Vitamin D", doseAmount: 2000, doseUnit: "iu", frequency: "daily"))

        _ = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-14")
        _ = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-15")
        _ = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-20")

        let entries = try logStore.entries(planId: planId, from: "2026-09-14", to: "2026-09-16")
        #expect(entries.count == 2)
    }
}
