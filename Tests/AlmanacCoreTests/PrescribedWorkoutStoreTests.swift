import Testing
import Foundation
@testable import AlmanacCore

@Suite("PrescribedWorkoutStore Tests")
struct PrescribedWorkoutStoreTests {
    let db = try! TestDatabase()
    var store: PrescribedWorkoutStore { PrescribedWorkoutStore(db: db) }

    @Test("Create and fetch a template")
    func createAndFetch() throws {
        let id = try store.create(name: "Push Day", containerType: "straight_sets", notes: "Chest/shoulders/triceps")

        let workout = try store.workout(id: id)
        #expect(workout?.name == "Push Day")
        #expect(workout?.containerType == "straight_sets")
        #expect(workout?.notes == "Chest/shoulders/triceps")
    }

    @Test("Container type outside the ten is rejected")
    func rejectsInvalidContainerType() throws {
        #expect(throws: (any Error).self) {
            _ = try store.create(name: "Bad", containerType: "not_a_container")
        }
    }

    @Test("Soft delete")
    func softDelete() throws {
        let id = try store.create(name: "Push Day", containerType: "straight_sets")
        #expect(try store.delete(id: id) == true)
        #expect(try store.workout(id: id)?.deletedAt != nil)
    }
}
