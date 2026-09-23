import Testing
import Foundation
@testable import AlmanacCore

/// "Every exercise shipped in Almanac must include a demonstration graphic."
///
/// workout-guide is bundled wholesale rather than matched exercise-by-exercise
/// against another catalogue: its illustrations were drawn for its own
/// exercises, so a graphic is correct for the row it ships with by
/// construction. Matching by name across sources was measured first and
/// rejected — several wger exercises only fuzzy-match the *wrong* movement
/// ("Wall Squat" → "Squat"), and a wrong demonstration is worse than none.
@Suite("workout-guide exercise seed (graphic per exercise)")
struct WorkoutGuideSeedTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    @Test("Migration 035 adds the graphic column")
    func graphicColumnExists() throws {
        let columns = try db.query("PRAGMA table_info(exerciseCatalog);")
        #expect(columns.contains { $0.string("name") == "graphicPath" })
    }

    @Test("Seeding inserts all 302 workout-guide exercises")
    func seedsEveryExercise() throws {
        #expect(try WorkoutGuideSeed.seed(into: store) == 302)
        #expect(try store.all().count == 302)
    }

    @Test("EVERY shipped exercise has a demonstration graphic file in the bundle")
    func everyExerciseHasAGraphicFile() throws {
        try WorkoutGuideSeed.seed(into: store)
        let all = try store.all()
        #expect(all.count == 302)
        for entry in all {
            #expect(entry.graphicPath != nil, "\(entry.name) ships without a graphic")
        }
        // The build-gate form of the same rule, checked against the real bundle.
        try ExerciseGraphicAudit.assertEveryExerciseHasGraphic(all)
    }

    @Test("Every seeded row is CC BY-SA 4.0 credited to the frame's creator")
    func licenceAndAuthorSurvive() throws {
        try WorkoutGuideSeed.seed(into: store)
        for entry in try store.all() {
            #expect(entry.licenseGroup == "cc_by_sa_4", "\(entry.name): \(entry.licenseGroup)")
            #expect(entry.licenseAuthor == "Bryl Lim", "\(entry.name): \(entry.licenseAuthor ?? "nil")")
        }
    }

    @Test("Seeding twice does not duplicate rows")
    func idempotent() throws {
        #expect(try WorkoutGuideSeed.seed(into: store) == 302)
        #expect(try WorkoutGuideSeed.seed(into: store) == 0)
        #expect(try store.all().count == 302)
    }

    @Test("The build guard fails when a shipped exercise has no graphic")
    func guardFailsOnMissingGraphic() throws {
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "workout-guide", exerciseId: "exercise-nothing", name: "Nothing",
            prescriptionType: "reps_load", licenseGroup: "cc_by_sa_4", licenseAuthor: "Bryl Lim"))
        #expect(throws: MissingExerciseGraphic.self) {
            try ExerciseGraphicAudit.assertEveryExerciseHasGraphic(try store.all())
        }
    }

    @Test("The guard also fails when the row names a graphic that is not bundled")
    func guardFailsOnUnbundledGraphic() throws {
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "workout-guide", exerciseId: "exercise-ghost", name: "Ghost",
            prescriptionType: "reps_load", licenseGroup: "cc_by_sa_4",
            licenseAuthor: "Bryl Lim", graphicPath: "does-not-exist.png"))
        #expect(throws: MissingExerciseGraphic.self) {
            try ExerciseGraphicAudit.assertEveryExerciseHasGraphic(try store.all())
        }
    }

    @Test("Upgrading withdraws the old wger rows, which have no compliant graphic")
    func upgradeWithdrawsLegacyRows() throws {
        // A database migrated only as far as 34, holding what the 21-row wger
        // catalogue used to write. Without this, the launch-time graphic guard
        // would refuse to open an upgraded app.
        let legacy = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all.filter { $0.version <= 34 }).migrate(legacy)
        let legacyStore = ExerciseCatalogStore(db: legacy)
        // Raw SQL, because today's store already writes columns that migration
        // 35 has not added yet — this row is written as the old seed wrote it.
        try legacy.run("""
        INSERT INTO exerciseCatalog
            (sourceId, exerciseId, name, prescriptionType, licenseGroup, licenseAuthor, createdAt, updatedAt)
        VALUES ('wger', '445', 'Pause Bench', 'reps_load', 'cc0', 'BFad07',
                '2026-09-16T00:00:00Z', '2026-09-16T00:00:00Z');
        """)
        #expect(try legacyStore.all().count == 1)

        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(legacy)

        #expect(try legacyStore.all().isEmpty, "an undemonstrable exercise must not stay in the catalogue")
        // Withdrawn, not erased: a bout logged against it still has its row.
        let survivors = try legacy.query("SELECT deletedAt FROM exerciseCatalog WHERE sourceId = 'wger';")
        #expect(survivors.count == 1)
        #expect(survivors.first?.string("deletedAt") != nil)
    }
}

/// The prescription model is Almanac's own (`docs/features/training.md` §2), so
/// the mapping from workout-guide's five `exerciseType` values is decided here
/// and pinned, rather than left to each row.
@Suite("workout-guide prescription mapping")
struct WorkoutGuidePrescriptionMappingTests {
    @Test("Loaded strength work is reps against an external load")
    func loadedWork() {
        #expect(WorkoutGuideSeed.prescriptionType(exerciseType: "weight_reps", isStretch: false, name: "Bench Press") == "reps_load")
    }

    @Test("Bodyweight work — assisted or not — is reps without a load")
    func bodyweightWork() {
        for type in ["bodyweight_reps", "assisted_bodyweight"] {
            #expect(WorkoutGuideSeed.prescriptionType(exerciseType: type, isStretch: false, name: "Push-up") == "reps_bodyweight")
        }
    }

    @Test("Cardio with a distance target maps to distance")
    func cardio() {
        #expect(WorkoutGuideSeed.prescriptionType(exerciseType: "distance_duration", isStretch: false, name: "Running") == "distance")
    }

    @Test("Timed work maps to duration")
    func timedWork() {
        #expect(WorkoutGuideSeed.prescriptionType(exerciseType: "duration", isStretch: false, name: "Jumping Jack") == "duration")
    }

    @Test("Static holds map to time_under_load, matching the model's own table")
    func staticHolds() {
        for name in ["Plank", "Wall Sit", "Dead Hang", "Hollow Body Hold", "Cable Pallof Hold"] {
            #expect(WorkoutGuideSeed.prescriptionType(exerciseType: "duration", isStretch: false, name: name) == "time_under_load",
                    "\(name) is a static hold")
        }
    }

    @Test("Stretches map to hold_stretch regardless of exerciseType")
    func stretches() {
        #expect(WorkoutGuideSeed.prescriptionType(exerciseType: "duration", isStretch: true, name: "Child's Pose") == "hold_stretch")
        #expect(WorkoutGuideSeed.prescriptionType(exerciseType: "weight_reps", isStretch: true, name: "Leg Swings") == "hold_stretch")
    }

    @Test("Every mapped type is one of the model's twelve")
    func mappedTypesAreInTheEnum() {
        for type in ["weight_reps", "bodyweight_reps", "duration", "distance_duration", "assisted_bodyweight"] {
            let mapped = WorkoutGuideSeed.prescriptionType(exerciseType: type, isStretch: false, name: "Sample")
            #expect(Migration016_TrainingSchema.prescriptionTypes.contains(mapped), "\(type) → \(mapped)")
        }
    }
}
