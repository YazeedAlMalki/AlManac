import Testing
import Foundation
@testable import AlmanacCore

@Suite("WorkoutSessionStore Tests")
struct WorkoutSessionStoreTests {
    let db = try! TestDatabase()
    var store: WorkoutSessionStore { WorkoutSessionStore(db: db) }

    @Test("Log and fetch a session")
    func logAndFetch() throws {
        let draft = WorkoutSessionDraft(date: "2026-09-16", durationMinutes: 45, rpe: 7,
                                         notes: "Sabre footwork + accessories")
        let id = try store.log(draft)

        let session = try store.session(id: id)
        #expect(session?.date == "2026-09-16")
        #expect(session?.durationMinutes == 45)
        #expect(session?.rpe == 7)
        #expect(session?.notes == "Sabre footwork + accessories")
    }

    @Test("Fetch sessions for a date")
    func fetchByDate() throws {
        _ = try store.log(WorkoutSessionDraft(date: "2026-09-16", durationMinutes: 30))
        _ = try store.log(WorkoutSessionDraft(date: "2026-09-16", durationMinutes: 20))
        _ = try store.log(WorkoutSessionDraft(date: "2026-09-17", durationMinutes: 40))

        let day16 = try store.sessions(date: "2026-09-16")
        #expect(day16.count == 2)
        let day17 = try store.sessions(date: "2026-09-17")
        #expect(day17.count == 1)
    }

    @Test("RPE outside 1-10 is rejected")
    func rpeOutOfRangeRejected() throws {
        #expect(throws: (any Error).self) {
            _ = try store.log(WorkoutSessionDraft(date: "2026-09-16", rpe: 11))
        }
        #expect(throws: (any Error).self) {
            _ = try store.log(WorkoutSessionDraft(date: "2026-09-16", rpe: 0))
        }
    }

    @Test("A session can reference a prescribed workout template")
    func linksToTemplate() throws {
        let workoutStore = PrescribedWorkoutStore(db: db)
        let templateId = try workoutStore.create(name: "Push Day", containerType: "straight_sets")

        let sessionId = try store.log(WorkoutSessionDraft(date: "2026-09-16", prescribedWorkoutId: templateId))
        let session = try store.session(id: sessionId)
        #expect(session?.prescribedWorkoutId == templateId)
    }

    @Test("Soft delete removes a session from date listings")
    func softDelete() throws {
        let id = try store.log(WorkoutSessionDraft(date: "2026-09-16", durationMinutes: 30))
        #expect(try store.sessions(date: "2026-09-16").count == 1)

        #expect(try store.delete(id: id) == true)
        #expect(try store.sessions(date: "2026-09-16").count == 0)
        #expect(try store.session(id: id)?.deletedAt != nil)
    }
}
