import XCTest
@testable import AlmanacCore

/// The food log: what was eaten, when, how much.
///
/// Written against a database that is closed and reopened, like
/// `ManualEntryTests`, because an in-memory one would pass even if nothing
/// reached disk.
final class NutritionLogTests: XCTestCase {

    private var path = ""
    private let clock = FixedClock(Date(timeIntervalSince1970: 1_773_500_000))  // 2026-03-14

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "almanac-nutrition-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func open() throws -> (Database, NutritionLogStore) {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return (db, NutritionLogStore(db: db, clock: clock,
                                      zone: ZoneContext(offsetMinutes: 180, identifier: "Asia/Riyadh")))
    }

    private let rice = SourceIdentifier(namespace: .usda, localID: "1105904")
    private let bulgur = SourceIdentifier(namespace: .cofid, localID: "13-145")

    private func lunch(_ grams: Double?) -> NutritionLogDraft {
        NutritionLogDraft(
            foodRef: rice, grams: grams,
            eatenAt: PartialDateTime(text: "2026-03-14T12:30:00+03:00", precision: .instant,
                                     zone: ZoneContext(offsetMinutes: 180, identifier: "Asia/Riyadh")),
            foodNameText: "Rice, white, cooked",
            quantityText: grams == nil ? nil : "1 cup")
    }

    // MARK: - Writing and reading back

    func testRecordsAMealAndReadsItBackFromDisk() throws {
        let logID: String
        do {
            let (_, log) = try open()
            let outcome = try log.record(lunch(150))
            guard case .inserted(let id) = outcome else {
                return XCTFail("expected an insert, got \(outcome)")
            }
            logID = id
        }

        let (_, log) = try open()
        let held = try XCTUnwrap(try log.entry(id: logID))
        XCTAssertEqual(held.foodRef, rice)
        XCTAssertEqual(held.foodRef.description, "usda:1105904",
                       "the publisher's identifier survives the round trip, not an internal key")
        XCTAssertEqual(held.grams, 150)
        XCTAssertEqual(held.quantityText, "1 cup", "what the person typed is kept verbatim")
        XCTAssertEqual(held.eatenAt.precision, .instant)
        XCTAssertEqual(held.eatenAt.zone.identifier, "Asia/Riyadh",
                       "the zone the meal was eaten in is not normalised away")
        XCTAssertEqual(held.sourceSystem, "manual")
        XCTAssertNil(held.externalID)
        XCTAssertFalse(held.isDeleted)
    }

    /// The distinction `NutrientQualifier` draws for nutrients, applied to the
    /// amount: nobody stated it is not the same as zero.
    func testAnUnquantifiedMealIsNotAZeroGramMeal() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(nil)).logID
        XCTAssertNil(try XCTUnwrap(try log.entry(id: id)).grams)

        let entries = try log.entries(from: "2026-03-14", to: "2026-03-15")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].value, .missing(reason: "amount not stated"),
                       "an unstated amount must not present as a quantity of zero")
    }

    func testRejectsAnImpossibleAmount() throws {
        let (_, log) = try open()
        for bad in [0.0, -5.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try log.record(lunch(bad)), "grams \(bad) must be refused") { error in
                guard case NutritionLogError.invalidGrams = error else {
                    return XCTFail("expected invalidGrams, got \(error)")
                }
            }
        }
        XCTAssertEqual(try log.entries(from: "2026-03-01", to: "2026-04-01").count, 0)
    }

    // MARK: - Identity

    func testTwoHelpingsOfTheSameFoodAreTwoMeals() throws {
        let (_, log) = try open()
        let first = try log.record(lunch(150)).logID
        let second = try log.record(lunch(150)).logID
        XCTAssertNotEqual(first, second,
                          "a manual entry carries no external id, so eating the same thing twice is two meals")
        XCTAssertEqual(try log.entries(from: "2026-03-14", to: "2026-03-15").count, 2)
    }

    func testReimportingAnEntryRevisesItRatherThanDuplicatingIt() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.sourceSystem = "myfitnesspal"
        draft.externalID = "mfp-9912"
        let id = try log.record(draft).logID

        // Same source, same external id, corrected amount.
        draft.grams = 180
        draft.quantityText = "1.2 cups"
        let again = try log.record(draft)
        guard case .revised(let sameID, _, let number, let changed) = again else {
            return XCTFail("expected a revision, got \(again)")
        }
        XCTAssertEqual(sameID, id, "one meal identity throughout")
        XCTAssertEqual(number, 1)
        XCTAssertEqual(Set(changed), ["grams", "quantity_text"])
        XCTAssertEqual(try log.entries(from: "2026-03-14", to: "2026-03-15").count, 1,
                       "a re-import is not a second meal")
        XCTAssertEqual(try XCTUnwrap(try log.entry(id: id)).grams, 180)

        // A byte-identical re-send changes nothing and writes no revision.
        guard case .unchanged = try log.record(draft) else {
            return XCTFail("a replay must be recognised as a replay")
        }
        XCTAssertEqual(try log.revisions(of: id).count, 1)
    }

    func testTheSameExternalIdFromADifferentSourceIsADifferentMeal() throws {
        let (_, log) = try open()
        var a = lunch(150); a.sourceSystem = "myfitnesspal"; a.externalID = "shared-id"
        var b = lunch(200); b.sourceSystem = "cronometer";   b.externalID = "shared-id"
        XCTAssertNotEqual(try log.record(a).logID, try log.record(b).logID)
    }

    // MARK: - Revisions

    func testCorrectingAMealKeepsThePreviousValuesWithTheReason() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(150)).logID

        clock.advance(by: 3600)
        var edit = NutritionLogEdit()
        edit.foodRef = .set(bulgur)
        edit.foodNameText = .set("Bulgur wheat, cooked")
        edit.grams = .set(200)
        edit.reasonText = "It was bulgur, not rice"
        let outcome = try log.update(id: id, edit)
        guard case .revised(_, _, let number, let changed) = outcome else {
            return XCTFail("expected a revision, got \(outcome)")
        }
        XCTAssertEqual(number, 1)
        XCTAssertEqual(Set(changed), ["food_ref", "food_name_text", "grams"])

        let current = try XCTUnwrap(try log.entry(id: id))
        XCTAssertEqual(current.foodRef, bulgur)
        XCTAssertEqual(current.grams, 200)

        // The revision holds what it *was*, so the correction is auditable.
        let history = try log.revisions(of: id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].foodRef, rice)
        XCTAssertEqual(history[0].grams, 150)
        XCTAssertEqual(history[0].reasonText, "It was bulgur, not rice")
        XCTAssertEqual(history[0].actor, "user")
        XCTAssertEqual(Set(history[0].changedFields), ["food_ref", "food_name_text", "grams"])
    }

    func testAnEditThatChangesNothingWritesNoRevision() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(150)).logID

        var untouched = NutritionLogEdit()
        guard case .unchanged = try log.update(id: id, untouched) else {
            return XCTFail("an empty edit is not a change")
        }

        // Setting a field to the value it already holds is also not a change.
        untouched.grams = .set(150)
        guard case .unchanged = try log.update(id: id, untouched) else {
            return XCTFail("setting the held value is not a change")
        }
        XCTAssertEqual(try log.revisions(of: id).count, 0)
    }

    func testClearingAnAmountIsDistinctFromLeavingItAlone() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(150)).logID

        var clear = NutritionLogEdit()
        clear.grams = .clear
        XCTAssertEqual(try log.update(id: id, clear).changedFields, ["grams"])
        XCTAssertNil(try XCTUnwrap(try log.entry(id: id)).grams,
                     "clear erases the amount; leaveUnchanged would have kept it")
        XCTAssertEqual(try log.revisions(of: id)[0].grams, 150)
    }

    func testAMealIsAlwaysOfSomeFood() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(150)).logID
        var edit = NutritionLogEdit()
        edit.foodRef = .clear
        XCTAssertThrowsError(try log.update(id: id, edit)) { error in
            guard case NutritionLogError.foodRefRequired = error else {
                return XCTFail("expected foodRefRequired, got \(error)")
            }
        }
    }

    func testEditingAnEntryThatIsNotThere() throws {
        let (_, log) = try open()
        var edit = NutritionLogEdit()
        edit.grams = .set(10)
        XCTAssertThrowsError(try log.update(id: "no-such-entry", edit)) { error in
            guard case NutritionLogError.entryNotFound = error else {
                return XCTFail("expected entryNotFound, got \(error)")
            }
        }
    }

    // MARK: - Deletion

    func testDeletingHidesTheMealWithoutErasingIt() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(150)).logID
        XCTAssertTrue(try log.delete(id: id))
        XCTAssertFalse(try log.delete(id: id), "a second delete changes nothing")

        XCTAssertEqual(try log.entries(from: "2026-03-14", to: "2026-03-15").count, 0,
                       "a deleted meal stops counting")
        let held = try XCTUnwrap(try log.entry(id: id))
        XCTAssertTrue(held.isDeleted, "the row is still there, so a mistaken delete is recoverable")
        XCTAssertEqual(held.grams, 150)
    }

    func testASourceReassertingAWithdrawnEntryRevivesIt() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.sourceSystem = "myfitnesspal"
        draft.externalID = "mfp-9912"
        let id = try log.record(draft).logID
        XCTAssertTrue(try log.delete(id: id))

        draft.grams = 160
        _ = try log.record(draft)
        XCTAssertFalse(try XCTUnwrap(try log.entry(id: id)).isDeleted)
        XCTAssertEqual(try log.entries(from: "2026-03-14", to: "2026-03-15").count, 1)
    }

    func testRevivingAnUnchangedEntryReportsUnchangedButStillRevivesIt() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.sourceSystem = "myfitnesspal"
        draft.externalID = "mfp-9912"
        let id = try log.record(draft).logID
        XCTAssertTrue(try log.delete(id: id))

        // Identical re-send: no value changed, so no revision — but the source
        // has re-asserted the entry, so it is live again. Pinned because a
        // caller reading `.unchanged` as "nothing happened" would be wrong.
        guard case .unchanged = try log.record(draft) else {
            return XCTFail("no value changed, so there is nothing to revise")
        }
        XCTAssertEqual(try log.revisions(of: id).count, 0)
        XCTAssertFalse(try XCTUnwrap(try log.entry(id: id)).isDeleted)
        XCTAssertEqual(try log.entries(from: "2026-03-14", to: "2026-03-15").count, 1)
    }

    // MARK: - Timeline

    func testTheMealReachesTheSharedTimeline() throws {
        let (db, log) = try open()
        _ = try log.record(lunch(150))

        let timeline = Timeline(providers: [log, HealthSampleStore(db: db, clock: clock)])
        let entries = try timeline.entries(from: "2026-03-14", to: "2026-03-15")
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.domain, "nutrition")
        XCTAssertEqual(entry.kind, "food")
        XCTAssertEqual(entry.recordTable, "nutrition_log")
        XCTAssertEqual(entry.title, "Rice, white, cooked")
        XCTAssertEqual(entry.detail, "1 cup")
        XCTAssertEqual(entry.value, .quantity(text: "150.0", unit: "g"))
        XCTAssertEqual(entry.basis, .occurrence)
        XCTAssertEqual(entry.rangeFit, .definite)
    }

    /// A meal logged without a time is still a meal. It is placed by when it
    /// was recorded and says so, rather than vanishing.
    func testAMealWithNoEatenTimeIsPlacedByWhenItWasRecorded() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.eatenAt = .unknown
        _ = try log.record(draft)

        let entries = try log.entries(from: "2026-03-14", to: "2026-03-15")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].basis, .recorded,
                       "the weaker placement travels with the entry")
    }

    /// A day-precision meal overlaps a narrower range rather than disappearing
    /// from it — the same `RangeFit` contract Laboratory follows.
    func testACoarselyDatedMealOverlapsRatherThanVanishes() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.eatenAt = PartialDateTime(text: "2026-03-14", precision: .day)
        _ = try log.record(draft)

        let entries = try log.entries(from: "2026-03-14T12:00:00Z", to: "2026-03-14T13:00:00Z")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].rangeFit, .potential)
    }

    /// The log points at the reference database by namespaced identifier and
    /// holds no foreign key into it. Removing a source — which
    /// `SourceIdentifier` exists to keep to a one-line delete — must not erase
    /// what the user recorded eating.
    // MARK: - Meal type

    /// Not stated is the default and a real state, same as `grams` — a meal
    /// logged before this field existed reads back this way, not as an error.
    func testAMealWithNoStatedTypeReadsBackNil() throws {
        let (_, log) = try open()
        let id = try log.record(lunch(150)).logID
        XCTAssertNil(try XCTUnwrap(try log.entry(id: id)).mealType)
    }

    func testAMealTypeIsRecordedAndReadBack() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.mealType = .lunch
        let id = try log.record(draft).logID
        XCTAssertEqual(try XCTUnwrap(try log.entry(id: id)).mealType, .lunch)
    }

    func testCorrectingTheMealTypeIsTrackedLikeAnyOtherField() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.mealType = .breakfast
        let id = try log.record(draft).logID

        var edit = NutritionLogEdit()
        edit.mealType = .set(.snack)
        let outcome = try log.update(id: id, edit)
        guard case .revised(_, _, _, let changed) = outcome else {
            return XCTFail("expected a revision, got \(outcome)")
        }
        XCTAssertEqual(changed, ["meal_type"])
        XCTAssertEqual(try XCTUnwrap(try log.entry(id: id)).mealType, .snack)
        XCTAssertEqual(try log.revisions(of: id)[0].mealType, .breakfast,
                       "the revision holds what the meal type *was*")
    }

    func testClearingTheMealTypeIsDistinctFromLeavingItAlone() throws {
        let (_, log) = try open()
        var draft = lunch(150)
        draft.mealType = .dinner
        let id = try log.record(draft).logID

        var clear = NutritionLogEdit()
        clear.mealType = .clear
        XCTAssertEqual(try log.update(id: id, clear).changedFields, ["meal_type"])
        XCTAssertNil(try XCTUnwrap(try log.entry(id: id)).mealType)
    }

    func testRemovingAReferenceSourceDoesNotEraseTheUsersMeals() throws {
        let (db, log) = try open()
        let id = try log.record(lunch(150)).logID

        // The device holds a reference row for `rice`, as it would after a
        // bundle import; the source is then withdrawn the way a reimport
        // without it would remove it (NutritionReferenceImporter's own delete
        // step, exercised directly for NutritionBundleImportTests).
        try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
            VALUES ('usda', 'usda', 'USDA', '2026', 'CC0', 'A', '', '');
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES ('usda:1105904', 'usda', '1105904', 'A', '', '', 'fixture');
            """)
        let catalog = NutritionCatalog(db: db)
        XCTAssertNotNil(try catalog.food(rice))
        try db.execute("DELETE FROM nutrition_food WHERE namespace = 'usda';")
        XCTAssertNil(try catalog.food(rice))

        let held = try XCTUnwrap(try log.entry(id: id))
        XCTAssertEqual(held.foodRef, rice)
        XCTAssertEqual(try log.entries(from: "2026-03-14", to: "2026-03-15")[0].title,
                       "Rice, white, cooked",
                       "the name logged at the time keeps an orphaned entry readable")
    }
}
