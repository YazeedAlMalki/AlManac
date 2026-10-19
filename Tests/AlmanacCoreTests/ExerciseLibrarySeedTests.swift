import Testing
import Foundation
@testable import AlmanacCore

/// The exercise library from free-exercise-db and wger, merged with
/// workout-guide so each real exercise is one record (owner, 2026-10-19).
/// The matching itself is tested in `tools/exercises/tests`; these pin what the
/// bundled result does to a database.
@Suite("Exercise library seed (free-exercise-db + wger)")
struct ExerciseLibrarySeedTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    private func seedBoth() throws {
        try WorkoutGuideSeed.seed(into: store)
        try ExerciseLibrarySeed.seed(into: store)
    }

    @Test("Seeding adds the 783 new records once")
    func seedsOnce() throws {
        try WorkoutGuideSeed.seed(into: store)
        #expect(try ExerciseLibrarySeed.seed(into: store) == 783)
        #expect(try ExerciseLibrarySeed.seed(into: store) == 0)
        #expect(try store.all().count == 302 + 783)
    }

    @Test("Every exercise, old and new, has a demonstration graphic in the bundle")
    func everyExerciseHasAGraphic() throws {
        try seedBoth()
        try ExerciseGraphicAudit.assertEveryExerciseHasGraphic(try store.all())
    }

    @Test("Every source row is stored once and points at a live record")
    func sourcesBelongToOneRecord() throws {
        try seedBoth()
        let live = Set(try store.all().map(\.id))
        let sources = try store.sources()
        #expect(!sources.isEmpty)
        #expect(Set(sources.map { "\($0.sourceId):\($0.sourceExerciseId)" }).count == sources.count)
        for source in sources {
            #expect(live.contains(source.exerciseCatalogId), "\(source.sourceId):\(source.sourceExerciseId)")
            #expect(AttributionCatalog.licenseReference(forGroup: source.licenseGroup) != nil,
                    "\(source.sourceId):\(source.sourceExerciseId) has licence group \(source.licenseGroup)")
        }
    }

    @Test("A shipped workout-guide row keeps its identity and gains the matching sources")
    func mergesIntoWorkoutGuide() throws {
        try seedBoth()
        let bench = try #require(try store.exercise(sourceId: "workout-guide", exerciseId: "exercise-bench-press"))
        let ids = Set(try store.sources(exerciseCatalogId: bench.id).map(\.sourceId))
        #expect(ids == ["workout-guide", "free-exercise-db", "wger"])
        #expect(try store.exercise(sourceId: "free-exercise-db", exerciseId: "Barbell_Bench_Press_-_Medium_Grip") == nil,
                "the same exercise must not also ship as its own row")
    }

    @Test("Where sources disagree, every value is kept")
    func conflictKeepsBothValues() throws {
        try seedBoth()
        let deadlift = try #require(try store.exercise(sourceId: "workout-guide", exerciseId: "exercise-deadlift"))
        let muscles = try store.sources(exerciseCatalogId: deadlift.id).compactMap {
            try JSONDecoder().decode(ExerciseLibrarySeed.Fields.self, from: Data($0.fields.utf8)).primaryMuscle
        }
        #expect(Set(muscles).count > 1, "deadlift's sources name different primary muscles: \(muscles)")
    }

    @Test("wger authors are credited even when their exercise was merged away")
    func mergedAuthorsAreCredited() throws {
        try seedBoth()
        let wger = try store.sources().filter { $0.sourceId == "wger" }
        #expect(!ExerciseAuthorCredits.distinct(from: wger).isEmpty)
        #expect(try store.all().allSatisfy { $0.sourceId != "wger" }, "wger rows have no graphic of their own")
    }
}
