import Testing
import Foundation
@testable import AlmanacCore

/// The requirement's per-row obligation: an exercise source licenses each row
/// separately and names an author per row, so that data must survive every
/// processing stage into the app database, and remain readable so the
/// Attributions page can list each author individually.
@Suite("Exercise licence author persistence")
struct ExerciseAttributionPersistenceTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    @Test("Migration 034 adds the licenseAuthor column")
    func columnExists() throws {
        let columns = try db.query("PRAGMA table_info(exerciseCatalog);")
        #expect(columns.contains { $0.string("name") == "licenseAuthor" },
                "exerciseCatalog must keep a per-row licenseAuthor")
    }

    @Test("A row's licence author survives insert and read")
    func authorSurvivesRoundTrip() throws {
        let id = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "445", name: "Pause Bench",
            prescriptionType: "reps_load", licenseGroup: "cc_by_sa_4",
            licenseAuthor: "Mens Fitness"))

        let entry = try store.exercise(id: id)
        #expect(entry?.licenseAuthor == "Mens Fitness")
        #expect(entry?.licenseGroup == "cc_by_sa_4")
    }

    @Test("Fetching by (sourceId, exerciseId) keeps the author too")
    func authorSurvivesNaturalKeyRead() throws {
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "490", name: "Renegade Row",
            prescriptionType: "reps_load", licenseGroup: "cc0", licenseAuthor: "fletchgraham"))

        #expect(try store.exercise(sourceId: "wger", exerciseId: "490")?.licenseAuthor == "fletchgraham")
    }

    @Test("A row may carry no author without losing anything")
    func authorIsOptional() throws {
        let id = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "999", name: "Unattributed",
            prescriptionType: "reps_load", licenseGroup: "cc0"))
        #expect(try store.exercise(id: id)?.licenseAuthor == nil)
    }

    @Test("The shipped catalog keeps a real author on every row")
    func seedCarriesAuthors() throws {
        try WorkoutGuideSeed.seed(into: store)
        let all = try store.all()
        #expect(all.count == 302)
        for entry in all {
            #expect((entry.licenseAuthor ?? "").isEmpty == false,
                    "\(entry.name) must keep its license author")
        }
    }

    @Test("The Attributions page can list the shipped authors individually")
    func seededAuthorsAreListable() throws {
        try WorkoutGuideSeed.seed(into: store)
        let authors = Set(try store.all().compactMap(\.licenseAuthor))
        #expect(authors == ["Bryl Lim"])
    }
}
