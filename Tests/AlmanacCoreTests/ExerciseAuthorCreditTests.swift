import Testing
import Foundation
@testable import AlmanacCore

/// The requirement allows the Attributions page to list each author
/// individually instead of a per-exercise detail screen. This pins that list:
/// distinct authors, each with the licence their rows carry, nil authors
/// dropped, deterministic order.
@Suite("Exercise author credits")
struct ExerciseAuthorCreditTests {
    let db = try! TestDatabase()
    var store: ExerciseCatalogStore { ExerciseCatalogStore(db: db) }

    @Test("A repeated author is listed once, with its licence")
    func distinctAuthors() throws {
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "1", name: "A",
            prescriptionType: "reps_load", licenseGroup: "cc0", licenseAuthor: "BFad07"))
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "2", name: "B",
            prescriptionType: "reps_load", licenseGroup: "cc0", licenseAuthor: "BFad07"))
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "3", name: "C",
            prescriptionType: "reps_load", licenseGroup: "cc_by_sa_4", licenseAuthor: "Behrooz"))
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "4", name: "D",
            prescriptionType: "reps_load", licenseGroup: "cc0"))

        let credits = ExerciseAuthorCredits.distinct(from: try store.all())
        #expect(credits.count == 2)
        #expect(Set(credits.map(\.author)) == ["BFad07", "Behrooz"])
        #expect(credits.first { $0.author == "Behrooz" }?.license?.name == "CC BY-SA 4.0")
        #expect(credits.first { $0.author == "BFad07" }?.license?.name == "CC0 1.0")
    }

    @Test("The same author under two licences is two credits, not one")
    func authorUnderTwoLicences() throws {
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "1", name: "A",
            prescriptionType: "reps_load", licenseGroup: "cc0", licenseAuthor: "BFad07"))
        _ = try store.insert(ExerciseCatalogDraft(
            sourceId: "wger", exerciseId: "2", name: "B",
            prescriptionType: "reps_load", licenseGroup: "cc_by_sa_4", licenseAuthor: "BFad07"))

        let credits = ExerciseAuthorCredits.distinct(from: try store.all())
        #expect(credits.count == 2)
        #expect(credits.allSatisfy { $0.author == "BFad07" })
    }

    @Test("The shipped catalog lists its real authors individually")
    func seededAuthorList() throws {
        try WorkoutGuideSeed.seed(into: store)
        let credits = ExerciseAuthorCredits.distinct(from: try store.all())
        #expect(credits.count == 1)
        #expect(credits.first?.author == "Bryl Lim")
        #expect(credits.first?.license?.name == "CC BY-SA 4.0")
    }
}
