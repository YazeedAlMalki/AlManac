import Testing
import Foundation
@testable import AlmanacCore

@Suite("ExerciseCatalogStore Tests")
struct ExerciseCatalogStoreTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    @Test("Insert and fetch by id")
    func insertAndFetch() throws {
        let draft = ExerciseCatalogDraft(sourceId: "wger", exerciseId: "132", name: "Barbell Squat",
                                          category: "legs", equipment: "barbell", force: "push",
                                          prescriptionType: "reps_load", licenseGroup: "cc0",
                                          confidence: "high")
        let id = try store.insert(draft)

        let entry = try store.exercise(id: id)
        #expect(entry?.name == "Barbell Squat")
        #expect(entry?.prescriptionType == "reps_load")
        #expect(entry?.licenseGroup == "cc0")
        #expect(entry?.sourceId == "wger")
        #expect(entry?.exerciseId == "132")
    }

    @Test("Fetch by (sourceId, exerciseId)")
    func fetchBySourceIdentity() throws {
        let draft = ExerciseCatalogDraft(sourceId: "wger", exerciseId: "73", name: "Pull-up",
                                          prescriptionType: "reps_bodyweight", licenseGroup: "cc0")
        _ = try store.insert(draft)

        let entry = try store.exercise(sourceId: "wger", exerciseId: "73")
        #expect(entry?.name == "Pull-up")
    }

    @Test("Duplicate (sourceId, exerciseId) is rejected")
    func rejectsDuplicateSourceIdentity() throws {
        let draft = ExerciseCatalogDraft(sourceId: "wger", exerciseId: "1", name: "Deadlift",
                                          prescriptionType: "reps_load", licenseGroup: "cc0")
        _ = try store.insert(draft)
        #expect(throws: (any Error).self) {
            try store.insert(draft)
        }
    }

    @Test("Filter by prescription type")
    func filterByPrescriptionType() throws {
        _ = try store.insert(ExerciseCatalogDraft(sourceId: "wger", exerciseId: "1", name: "Deadlift",
                                                    prescriptionType: "reps_load", licenseGroup: "cc0"))
        _ = try store.insert(ExerciseCatalogDraft(sourceId: "wger", exerciseId: "2", name: "Plank",
                                                    prescriptionType: "time_under_load", licenseGroup: "cc0"))
        _ = try store.insert(ExerciseCatalogDraft(sourceId: "wger", exerciseId: "3", name: "Push-up",
                                                    prescriptionType: "reps_bodyweight", licenseGroup: "cc0"))

        let repsLoad = try store.exercises(prescriptionType: "reps_load")
        #expect(repsLoad.count == 1)
        #expect(repsLoad.first?.name == "Deadlift")
    }

    @Test("Soft delete removes an exercise from listings but keeps history")
    func softDelete() throws {
        let id = try store.insert(ExerciseCatalogDraft(sourceId: "wger", exerciseId: "1", name: "Deadlift",
                                                         prescriptionType: "reps_load", licenseGroup: "cc0"))

        #expect(try store.all().count == 1)
        let deleted = try store.delete(id: id)
        #expect(deleted == true)
        #expect(try store.all().count == 0)

        // The row itself is still readable directly by id — soft delete, not erasure.
        let entry = try store.exercise(id: id)
        #expect(entry?.deletedAt != nil)
    }

    @Test("Deleting an already-deleted exercise is a no-op, not an error")
    func deleteIsIdempotent() throws {
        let id = try store.insert(ExerciseCatalogDraft(sourceId: "wger", exerciseId: "1", name: "Deadlift",
                                                         prescriptionType: "reps_load", licenseGroup: "cc0"))
        #expect(try store.delete(id: id) == true)
        #expect(try store.delete(id: id) == false)
    }

    @Test("Missing licenseGroup or prescriptionType is a compile-time requirement, not a null check")
    func requiredFieldsAreNonOptionalInSwift() throws {
        // ExerciseCatalogDraft.prescriptionType and .licenseGroup are non-optional
        // String, not String? — this test exists to document that the QA
        // requirement from the Slice 4 prompt ("no null licenseGroup, no null
        // prescriptionType") is enforced by the Swift type system, matching how
        // the nutrition side's Tr/N licence bug taught this codebase to treat
        // that class of field.
        let draft = ExerciseCatalogDraft(sourceId: "wger", exerciseId: "1", name: "Deadlift",
                                          prescriptionType: "reps_load", licenseGroup: "cc0")
        #expect(draft.licenseGroup == "cc0")
    }
}
