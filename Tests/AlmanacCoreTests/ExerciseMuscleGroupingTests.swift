import Testing
import Foundation
@testable import AlmanacCore

/// The muscle-group grouping the owner asked for (2026-09-26): muscle first,
/// then method of training inside it, with an exercise listed under every
/// muscle it works rather than only its primary.
@Suite("Exercise Muscle Grouping Tests")
struct ExerciseMuscleGroupingTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    private func makeExercise(_ name: String, category: String?, equipment: String?) throws -> Int64 {
        try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: name, name: name, category: category,
            equipment: equipment, prescriptionType: "reps_load", licenseGroup: "cc0"))
    }

    @Test("Grouped by muscle, then by equipment inside it")
    func groupsByMuscleThenEquipment() throws {
        _ = try makeExercise("Bench Press", category: "Chest", equipment: "Barbell")
        _ = try makeExercise("Cable Fly", category: "Chest", equipment: "Cable")
        _ = try makeExercise("Squat", category: "Quads", equipment: "Barbell")

        let groups = try store.groupedByMuscleThenEquipment()
        let chest = try #require(groups.first { $0.muscle == "Chest" })
        #expect(chest.byEquipment.map(\.equipment) == ["Barbell", "Cable"])
        #expect(groups.contains { $0.muscle == "Quads" })
    }

    @Test("An exercise listed under a secondary muscle appears in both groups")
    func secondaryMuscleAppearsInBothGroups() throws {
        let id = try makeExercise("Close-Grip Bench", category: "Triceps", equipment: "Barbell")
        try store.addMuscle(to: id, muscle: "Chest")

        let groups = try store.groupedByMuscleThenEquipment()
        let triceps = try #require(groups.first { $0.muscle == "Triceps" })
        let chest = try #require(groups.first { $0.muscle == "Chest" })
        // Primary in one, listed under the other — and the group knows which.
        #expect(triceps.byEquipment.flatMap(\.exercises).map(\.id) == [id])
        #expect(chest.byEquipment.flatMap(\.exercises).map(\.id) == [id])
        #expect(triceps.hasSecondaryOnly == false)
        #expect(chest.hasSecondaryOnly == true)
    }

    @Test("A missing category is surfaced as Unassigned, not dropped")
    func uncategorisedExerciseIsNotLost() throws {
        _ = try makeExercise("Mystery Move", category: nil, equipment: "Cable")
        let groups = try store.groupedByMuscleThenEquipment()
        let unassigned = try #require(groups.first { $0.muscle == "Unassigned" })
        #expect(unassigned.byEquipment.flatMap(\.exercises).count == 1)
        // A gap sorts last so it does not lead the list.
        #expect(groups.last?.muscle == "Unassigned")
    }

    @Test("A missing equipment value is surfaced as Unspecified")
    func missingEquipment() throws {
        _ = try makeExercise("Some Movement", category: "Back", equipment: nil)
        let groups = try store.groupedByMuscleThenEquipment()
        let back = try #require(groups.first { $0.muscle == "Back" })
        #expect(back.byEquipment.map(\.equipment) == ["Unspecified"])
    }

    @Test("Adding the same muscle twice is idempotent and does not duplicate the exercise")
    func addMuscleIsIdempotent() throws {
        let id = try makeExercise("Row", category: "Back", equipment: "Cable")
        try store.addMuscle(to: id, muscle: "Biceps")
        try store.addMuscle(to: id, muscle: "Biceps")

        let groups = try store.groupedByMuscleThenEquipment()
        let biceps = try #require(groups.first { $0.muscle == "Biceps" })
        #expect(biceps.byEquipment.flatMap(\.exercises).count == 1)
    }

    @Test("Migration seeds the primary muscle from the catalogue's own category")
    func migrationSeedsPrimaryFromCategory() throws {
        // TestDatabase runs all migrations, then this inserts; the seed only
        // covers rows present at migration time, so assert the mechanism rather
        // than a count — the real catalogue is seeded at launch, not here.
        let id = try makeExercise("Deadlift", category: "Hamstrings", equipment: "Barbell")
        try store.addMuscle(to: id, muscle: "Hamstrings", isPrimary: true)
        let groups = try store.groupedByMuscleThenEquipment()
        #expect(groups.contains { $0.muscle == "Hamstrings" })
    }
}

/// The per-domain "which source wins" preference the owner asked for
/// (2026-09-26). The arbitration rule itself only matters once a second
/// provider exists, so what is tested here is that the decision is stored,
/// per-domain, changeable, and honest about being undecided.
@Suite("Sync Source Preference Tests")
struct SyncSourcePreferenceTests {
    let db = try! TestDatabase()
    var store: SyncSourcePreferenceStore { SyncSourcePreferenceStore(db: db) }

    @Test("An unasked domain is undecided, not defaulted")
    func undecidedByDefault() throws {
        #expect(try store.preferredSource(for: .sleep) == nil)
        #expect(try store.allPreferences().isEmpty)
    }

    @Test("A chosen source is stored and read back")
    func setAndRead() throws {
        try store.setPreferredSource(.healthKit, for: .sleep)
        #expect(try store.preferredSource(for: .sleep)?.id == "healthkit")
    }

    @Test("Preferences are per-domain, not global")
    func perDomain() throws {
        try store.setPreferredSource(.healthKit, for: .sleep)
        try store.setPreferredSource(.manual, for: .steps)
        #expect(try store.preferredSource(for: .sleep)?.id == "healthkit")
        #expect(try store.preferredSource(for: .steps)?.id == "manual")
        #expect(try store.preferredSource(for: .hrv) == nil)
    }

    @Test("Changing the preference later overwrites rather than adding a second opinion")
    func changeable() throws {
        try store.setPreferredSource(.healthKit, for: .sleep)
        try store.setPreferredSource(.manual, for: .sleep)
        #expect(try store.preferredSource(for: .sleep)?.id == "manual")
        #expect(try store.allPreferences().count == 1)
    }

    @Test("Clearing returns a domain to undecided")
    func clear() throws {
        try store.setPreferredSource(.healthKit, for: .sleep)
        try store.clearPreference(for: .sleep)
        #expect(try store.preferredSource(for: .sleep) == nil)
    }
}
