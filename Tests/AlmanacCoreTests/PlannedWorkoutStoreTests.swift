import Testing
import Foundation
@testable import AlmanacCore

@Suite("PlannedWorkoutStore Tests")
struct PlannedWorkoutStoreTests {
    let db = try! TestDatabase()
    var store: PlannedWorkoutStore { PlannedWorkoutStore(db: db) }

    @Test("Create a planned workout and read it back")
    func createAndRead() throws {
        let scheduledAt = Date(timeIntervalSince1970: 1_800_000_000)
        let id = try store.create(PlannedWorkoutDraft(scheduledAt: scheduledAt, notes: "Leg day"))

        let planned = try store.planned(id: id)
        #expect(planned?.scheduledAt == scheduledAt)
        #expect(planned?.notes == "Leg day")
        #expect(planned?.prescribedWorkoutId == nil)
    }

    @Test("Create a planned workout linked to a prescribed workout template")
    func createLinkedToTemplate() throws {
        let templateId = try PrescribedWorkoutStore(db: db).create(name: "Push Day", containerType: "straight_sets")
        let scheduledAt = Date(timeIntervalSince1970: 1_800_000_000)
        let id = try store.create(PlannedWorkoutDraft(scheduledAt: scheduledAt, prescribedWorkoutId: templateId))

        #expect(try store.planned(id: id)?.prescribedWorkoutId == templateId)
    }

    @Test("Delete removes a planned workout")
    func deletePlanned() throws {
        let id = try store.create(PlannedWorkoutDraft(scheduledAt: Date()))
        try store.delete(id: id)
        #expect(try store.planned(id: id) == nil)
    }

    @Test("nextUpcoming returns the soonest workout scheduled strictly after the given instant")
    func nextUpcomingPicksSoonest() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soonId = try store.create(PlannedWorkoutDraft(scheduledAt: now.addingTimeInterval(3600)))
        _ = try store.create(PlannedWorkoutDraft(scheduledAt: now.addingTimeInterval(7200)))

        let next = try store.nextUpcoming(after: now)
        #expect(next?.id == soonId)
    }

    @Test("nextUpcoming excludes workouts scheduled at or before the given instant")
    func nextUpcomingExcludesPastAndPresent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try store.create(PlannedWorkoutDraft(scheduledAt: now.addingTimeInterval(-3600)))
        _ = try store.create(PlannedWorkoutDraft(scheduledAt: now))

        #expect(try store.nextUpcoming(after: now) == nil)
    }

    @Test("nextUpcoming is nil with nothing planned")
    func nextUpcomingNilWithNothingPlanned() throws {
        #expect(try store.nextUpcoming(after: Date()) == nil)
    }
}
