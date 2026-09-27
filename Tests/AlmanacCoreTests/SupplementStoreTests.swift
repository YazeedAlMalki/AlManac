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

    @Test("allPlans includes deactivated ones, active first")
    func allPlansIncludesDeactivated() throws {
        let keep = try store.create(SupplementPlanDraft(name: "Fish Oil", doseAmount: 1, doseUnit: "capsule",
                                                          frequency: "daily"))
        let drop = try store.create(SupplementPlanDraft(name: "Old Stack", doseAmount: 1, doseUnit: "capsule",
                                                          frequency: "daily"))
        try store.deactivate(id: drop)

        // A deactivated plan is still the subject of real adherence history, so
        // a plan screen listing only active plans would show a discontinued
        // supplement as though it had never existed.
        #expect(try store.allPlans().map { $0.id } == [keep, drop])
    }

    @Test("update changes the authored fields")
    func updatePlanFields() throws {
        let id = try store.create(SupplementPlanDraft(name: "Creatine", doseAmount: 5, doseUnit: "g",
                                                      frequency: "daily"))
        try store.update(SupplementPlanDraft(name: "Creatine HCl", doseAmount: 5, doseUnit: "g",
                                             frequency: "pre_workout", timingNotes: "with the shake"),
                         id: id)

        let plan = try store.plan(id: id)
        #expect(plan?.name == "Creatine HCl")
        #expect(plan?.frequency == "pre_workout")
        #expect(plan?.timingNotes == "with the shake")
    }

    @Test("update does not clear the reminder or reactivate a plan")
    func updateLeavesReminderAndActiveAlone() throws {
        // Both have their own single-purpose methods, so an edit form that
        // omitted them would silently wipe a reminder and revive a discontinued
        // plan. That is the reason they are not on `update`.
        let id = try store.create(SupplementPlanDraft(name: "Magnesium", doseAmount: 400, doseUnit: "mg",
                                                      frequency: "daily"))
        try store.setReminder(id: id, enabled: true, reminderMinuteOfDay: 21 * 60)
        try store.deactivate(id: id)
        try store.update(SupplementPlanDraft(name: "Magnesium glycinate", doseAmount: 400, doseUnit: "mg",
                                             frequency: "daily"),
                         id: id)

        let plan = try store.plan(id: id)
        #expect(plan?.name == "Magnesium glycinate")
        #expect(plan?.isActive == false)
        #expect(plan?.reminderEnabled == true)
        #expect(plan?.reminderMinuteOfDay == 21 * 60)
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

    @Test("Adherence across every plan in a range, newest first")
    func adherenceAcrossAllPlansInRange() throws {
        // A history list reads down the screen, so the order has to be by when
        // things were taken rather than grouped by plan — grouping would put two
        // entries from different supplements side by side as if simultaneous.
        let d = try planStore.create(SupplementPlanDraft(name: "Vitamin D", doseAmount: 2000, doseUnit: "iu",
                                                          frequency: "daily"))
        let magnesium = try planStore.create(SupplementPlanDraft(name: "Magnesium", doseAmount: 400, doseUnit: "mg",
                                                                 frequency: "daily"))

        _ = try logStore.log(SupplementLogDraft(planId: d, timestamp: iso("2026-09-14T08:00:00Z")), logicalDay: "2026-09-14")
        _ = try logStore.log(SupplementLogDraft(planId: magnesium, timestamp: iso("2026-09-14T21:00:00Z")), logicalDay: "2026-09-14")
        _ = try logStore.log(SupplementLogDraft(planId: d, timestamp: iso("2026-09-20T08:00:00Z")), logicalDay: "2026-09-20")

        let entries = try logStore.entries(from: "2026-09-14", to: "2026-09-16")
        #expect(entries.map { $0.planId } == [magnesium, d])
    }

    @Test("setTaken corrects a logged dose in place")
    func setTakenCorrectsInPlace() throws {
        let planId = try planStore.create(SupplementPlanDraft(
            name: "Creatine", doseAmount: 5, doseUnit: "g", frequency: "daily"))
        let id = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-16")

        try logStore.setTaken(id: id, to: false)
        #expect(try logStore.entries(for: "2026-09-16").first?.taken == false)

        try logStore.setTaken(id: id, to: true)
        #expect(try logStore.entries(for: "2026-09-16").first?.taken == true)
        // The entry keeps its identity — a delete-and-reinsert would hand the
        // row a new id and a new createdAt for what the user calls a correction.
        #expect(try logStore.entries(for: "2026-09-16").first?.id == id)
    }

    @Test("delete removes a mis-tapped entry")
    func deleteRemovesEntry() throws {
        let planId = try planStore.create(SupplementPlanDraft(
            name: "Creatine", doseAmount: 5, doseUnit: "g", frequency: "daily"))
        let id = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-16")

        try logStore.delete(id: id)
        #expect(try logStore.entries(for: "2026-09-16").isEmpty)
    }

    @Test("Deleting an entry leaves the plan it belonged to alone")
    func deleteDoesNotTouchThePlan() throws {
        let planId = try planStore.create(SupplementPlanDraft(
            name: "Creatine", doseAmount: 5, doseUnit: "g", frequency: "daily"))
        let id = try logStore.log(SupplementLogDraft(planId: planId, timestamp: Date()), logicalDay: "2026-09-16")

        try logStore.delete(id: id)
        #expect(try planStore.plan(id: planId)?.isActive == true)
    }

    private func iso(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)!
    }
}
