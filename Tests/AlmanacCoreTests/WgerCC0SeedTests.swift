import Testing
import Foundation
@testable import AlmanacCore

/// Task 3 QA checklist, verified mechanically rather than by eyeballing the
/// 21-row table in WgerCC0Seed.swift:
///   - no null licenseGroup
///   - all 21 have a valid prescriptionType (one of the 12-type enum)
///   - a handful of specific mappings are sensible, not just non-null
///   - seeding twice doesn't duplicate rows (the (sourceId, exerciseId) guard)
@Suite("WgerCC0Seed Tests")
struct WgerCC0SeedTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    @Test("Seeding inserts exactly the 21 real wger CC0 exercises")
    func seedsExactlyTwentyOne() throws {
        let inserted = try WgerCC0Seed.seed(into: store)
        #expect(inserted == 21)
        #expect(WgerCC0Seed.rows.count == 21)

        let all = try store.all()
        #expect(all.count == 21)
    }

    @Test("Every seeded row has a non-null licenseGroup of cc0")
    func noNullLicenseGroup() throws {
        try WgerCC0Seed.seed(into: store)
        let all = try store.all()
        for entry in all {
            #expect(entry.licenseGroup == "cc0", "\(entry.name) must carry licenseGroup=cc0, got \(entry.licenseGroup)")
        }
    }

    @Test("Every seeded row has a valid prescriptionType from the 12-type enum")
    func allPrescriptionTypesValid() throws {
        let validTypes = Set(Migration016_TrainingSchema.prescriptionTypes)
        #expect(validTypes.count == 12)

        try WgerCC0Seed.seed(into: store)
        let all = try store.all()
        #expect(all.count == 21)
        for entry in all {
            #expect(validTypes.contains(entry.prescriptionType),
                     "\(entry.name) has prescriptionType='\(entry.prescriptionType)', not in the 12-type enum")
        }
    }

    @Test("Every row in the source table itself has a valid prescriptionType")
    func sourceTableTypesValid() {
        // Belt-and-suspenders: check WgerCC0Seed.rows directly too, not just
        // what made it into the database, so a future edit to the table is
        // caught even before seed() runs.
        let validTypes = Set(Migration016_TrainingSchema.prescriptionTypes)
        for row in WgerCC0Seed.rows {
            #expect(validTypes.contains(row.prescriptionType),
                     "\(row.name) (wger id \(row.wgerId)) has invalid prescriptionType '\(row.prescriptionType)'")
        }
    }

    @Test("Spot check: mappings are sensible, not just non-null")
    func spotCheckMappingsAreSensible() throws {
        try WgerCC0Seed.seed(into: store)

        func type(forWgerId id: String) throws -> String? {
            try store.exercise(sourceId: "wger", exerciseId: id)?.prescriptionType
        }

        // Barbell/dumbbell strength work loaded externally -> reps_load.
        #expect(try type(forWgerId: "445") == "reps_load")   // Pause Bench
        #expect(try type(forWgerId: "650") == "reps_load")   // Thruster (Barbell)
        #expect(try type(forWgerId: "599") == "reps_load")   // Snatch (Barbell)

        // Bodyweight calisthenics -> reps_bodyweight, not reps_load or duration.
        #expect(try type(forWgerId: "194") == "reps_bodyweight")  // Dips
        #expect(try type(forWgerId: "282") == "reps_bodyweight")  // Handstand Pushup
        #expect(try type(forWgerId: "152") == "reps_bodyweight")  // Chin Up (override case)

        // Steady-state cardio -> duration, not reps_load.
        #expect(try type(forWgerId: "177") == "duration")  // Cycling

        // Static holds -> time_under_load, not reps_bodyweight or duration.
        #expect(try type(forWgerId: "718") == "time_under_load")  // Wall Squat (override case)
        #expect(try type(forWgerId: "297") == "time_under_load")  // Hollow Hold (override case)
    }

    @Test("Seeding twice does not duplicate rows")
    func idempotent() throws {
        let first = try WgerCC0Seed.seed(into: store)
        let second = try WgerCC0Seed.seed(into: store)
        #expect(first == 21)
        #expect(second == 0, "re-seeding must skip rows already present, not duplicate them")

        let all = try store.all()
        #expect(all.count == 21)
    }

    @Test("Every medium-confidence row documents an override reason")
    func mediumConfidenceRowsExplainThemselves() {
        for row in WgerCC0Seed.rows where row.confidence == "medium" {
            #expect(row.overrideReason != nil && !(row.overrideReason?.isEmpty ?? true),
                     "\(row.name) is medium confidence but has no recorded override reason")
        }
        for row in WgerCC0Seed.rows where row.confidence == "high" {
            #expect(row.overrideReason == nil,
                     "\(row.name) is high confidence but carries an override reason — that's a contradiction")
        }
    }
}
