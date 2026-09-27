import Testing
import Foundation
@testable import AlmanacCore

/// Spec §7.2's assignment rule, exercised through the two shapes it has to be
/// right in: an entry logged now, and the whole-table rebuild after a restore.
@Suite("NightNutritionWindowAssigner Tests")
struct NightNutritionWindowAssignerTests {
    let db = try! TestDatabase()
    var windows: NutritionWindowStore { NutritionWindowStore(db: db) }
    var assigner: NightNutritionWindowAssigner { NightNutritionWindowAssigner(db: db) }

    // Riyadh, UTC+3. Maghrib(D) = 2026-09-17 17:55 local = 14:55Z.
    // Fajr(D+1)  = 2026-09-18 04:22 local        = 01:22Z.
    private let maghribD = Date(timeIntervalSince1970: 1_789_656_900)
    private let fajrDPlus1 = Date(timeIntervalSince1970: 1_789_694_520)
    private let riyadh = ZoneContext(TimeZone(identifier: "Asia/Riyadh")!)

    private var food: SourceIdentifier { SourceIdentifier(namespace: .usda, localID: "dates") }

    private func openNightWindow() throws -> Int64 {
        try windows.createWindow(date: "2026-09-17", windowType: .nightNutritionWindow,
                                 startTimestamp: maghribD, endTimestamp: fajrDPlus1,
                                 fajrTimestamp: fajrDPlus1, maghribTimestamp: maghribD)
    }

    private func logMeal(at instant: Date, mealType: NutritionMealType? = nil) throws -> String {
        try NutritionLogStore(db: db).record(NutritionLogDraft(
            foodRef: food, grams: 80,
            eatenAt: PartialDateTime(instant: instant, zone: riyadh),
            mealType: mealType)).logID
    }

    private func logWater(at instant: Date) throws -> String {
        try HydrationStore(db: db, zone: riyadh).log(HydrationLogDraft(amount: Milliliters(500), loggedAt: instant))
    }

    /// The stored assignment, read as the raw column so a test is asserting the
    /// database's state and not the assigner's own arithmetic.
    private func assignment(ofLogID id: String) throws -> Int64? {
        try db.query("SELECT nutrition_window_id AS w FROM nutrition_log WHERE id = ?;", [.text(id)])
            .first?.int("w")
    }

    private func assignment(ofHydrationID id: String) throws -> Int64? {
        try db.query("SELECT nutrition_window_id AS w FROM hydration_log WHERE id = ?;", [.text(id)])
            .first?.int("w")
    }

    // MARK: - Resolution

    @Test("An entry before any window exists resolves to no window")
    func resolvesNothingWithoutWindows() throws {
        #expect(try assigner.windowID(containing: maghribD.addingTimeInterval(3600)) == nil)
    }

    @Test("An entry at exactly Maghrib is in the window; one at exactly Fajr is not")
    func boundsAreHalfOpen() throws {
        try openNightWindow()
        // §7.2 writes `Maghrib(D) ≤ timestamp < Fajr(D+1)` — closed at the start,
        // open at the end, so Fajr itself is the first moment of the fast.
        #expect(try assigner.windowID(containing: maghribD) != nil)
        #expect(try assigner.windowID(containing: fajrDPlus1) == nil)
    }

    // MARK: - The spec's defining case

    @Test("A 03:50 suhoor entry on the calendar day after the fast is assigned to the fast's own window")
    func suhoorBeforeFajrLandsInThePreviousDaysWindow() throws {
        let windowID = try openNightWindow()
        // 2026-09-18T00:50:00Z = 03:50 on 18 September, Riyadh local.
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let logID = try logMeal(at: suhoor)

        #expect(try assigner.assign(nutritionLogID: logID, eatenAt: suhoor) == windowID)
        #expect(try assignment(ofLogID: logID) == windowID)
    }

    @Test("An entry past the 04:00 boundary is still assigned to the fast, because the window does not follow the logical day")
    func assignmentIgnoresTheLogicalDayBoundary() throws {
        let windowID = try openNightWindow()
        // Fajr(D+1) is 04:22 local, so 04:10 on 18 September is the twenty-minute
        // band where the two rules disagree: Almanac's 04:00 boundary has already
        // started logical day D+1, but the fast has not ended. §7.2 settles it
        // for the fast — "the global 04:00 logical-day boundary is never
        // altered" means the window does not move to follow the day.
        //
        // (03:50 suhoor, the spec's own example, is *not* this case: at 03:50 the
        // 04:00 boundary has not passed, so its logical day is D and the window
        // agrees with it. The example is about the calendar day, not the logical
        // one.)
        let lateSuhoor = fajrDPlus1.addingTimeInterval(-12 * 60)  // 04:10 local
        let model = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
        #expect(model.logicalDay(lateSuhoor).value == "2026-09-18")

        let logID = try logMeal(at: lateSuhoor)
        #expect(try assigner.assign(nutritionLogID: logID, eatenAt: lateSuhoor) == windowID)
    }

    @Test("An iftar entry just after Maghrib is assigned, and the next pre-dawn one is not")
    func iftarIsInAndDaytimeBreakfastIsNot() throws {
        let windowID = try openNightWindow()
        let iftar = maghribD.addingTimeInterval(5 * 60)
        let breakfast = fajrDPlus1.addingTimeInterval(3 * 3600)

        let iftarID = try logMeal(at: iftar)
        let breakfastID = try logMeal(at: breakfast)

        #expect(try assigner.assign(nutritionLogID: iftarID, eatenAt: iftar) == windowID)
        #expect(try assigner.assign(nutritionLogID: breakfastID, eatenAt: breakfast) == nil)
        #expect(try assignment(ofLogID: breakfastID) == nil)
    }

    @Test("Water logged during the night is assigned too — a dry fast is opened by a drink")
    func waterDuringTheNightIsAssigned() throws {
        let windowID = try openNightWindow()
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let waterID = try logWater(at: suhoor)

        #expect(try assigner.assign(hydrationLogID: waterID, loggedAt: suhoor) == windowID)
        #expect(try assignment(ofHydrationID: waterID) == windowID)
    }

    // MARK: - Re-resolution

    @Test("Re-resolving an entry moved outside the window clears the assignment")
    func movingAnEntryOutOfTheWindowClearsIt() throws {
        let windowID = try openNightWindow()
        let inside = maghribD.addingTimeInterval(3600)
        let outside = fajrDPlus1.addingTimeInterval(2 * 3600)
        let logID = try logMeal(at: inside)

        #expect(try assigner.assign(nutritionLogID: logID, eatenAt: inside) == windowID)
        #expect(try assignment(ofLogID: logID) == windowID)

        // The value written depends on the current time, not on the first one
        // ever resolved, so an edit that takes the entry out of the fast leaves
        // no stale id behind.
        #expect(try assigner.assign(nutritionLogID: logID, eatenAt: outside) == nil)
        #expect(try assignment(ofLogID: logID) == nil)
    }

    @Test("A soft-deleted entry keeps whatever assignment it had — deleting is not a reassignment")
    func deletingAnEntryDoesNotReassign() throws {
        let windowID = try openNightWindow()
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let logID = try logMeal(at: suhoor)
        try assigner.assign(nutritionLogID: logID, eatenAt: suhoor)

        try db.run("UPDATE nutrition_log SET deleted_at = '2026-09-19T00:00:00Z' WHERE id = ?;", [.text(logID)])
        #expect(try assignment(ofLogID: logID) == windowID)
    }

    // MARK: - The rebuild pass

    @Test("The rebuild assigns every entry already inside the window, with no caller having asked")
    func rebuildAssignsWhatItFinds() throws {
        let windowID = try openNightWindow()
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let iftar = maghribD.addingTimeInterval(5 * 60)
        let breakfast = fajrDPlus1.addingTimeInterval(3 * 3600)
        let suhoorID = try logMeal(at: suhoor)
        let iftarID = try logMeal(at: iftar)
        let breakfastID = try logMeal(at: breakfast)
        let waterID = try logWater(at: suhoor)

        let counts = try assigner.assignUnassigned()

        #expect(try assignment(ofLogID: suhoorID) == windowID)
        #expect(try assignment(ofLogID: iftarID) == windowID)
        #expect(try assignment(ofLogID: breakfastID) == nil)
        #expect(try assignment(ofHydrationID: waterID) == windowID)
        #expect(counts.assigned == 3)
    }

    @Test("The rebuild re-resolves already-assigned entries, so a moved window boundary is picked up")
    func rebuildReresolvesExistingAssignments() throws {
        let windowID = try openNightWindow()
        let inside = maghribD.addingTimeInterval(3600)
        let logID = try logMeal(at: inside)
        try assigner.assign(nutritionLogID: logID, eatenAt: inside)
        #expect(try assignment(ofLogID: logID) == windowID)

        // Prayer times recalculated: this window now opens an hour later, so the
        // entry is no longer inside it. The entry is not findable from the new
        // span — it is not in it — so only clearing the window's own assignments
        // first can see that it has to go.
        try windows.createWindow(date: "2026-09-17", windowType: .nightNutritionWindow,
                                 startTimestamp: maghribD.addingTimeInterval(2 * 3600),
                                 endTimestamp: fajrDPlus1)
        let counts = try assigner.assignUnassigned()

        #expect(try assignment(ofLogID: logID) == nil)
        #expect(counts.cleared == 1)
        #expect(counts.assigned == 0)
    }

    @Test("The rebuild is idempotent — a second pass reaches the same state")
    func rebuildIsIdempotent() throws {
        let windowID = try openNightWindow()
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let logID = try logMeal(at: suhoor)
        _ = try logWater(at: suhoor)

        _ = try assigner.assignUnassigned()
        let second = try assigner.assignUnassigned()

        // The second pass clears the two rows it assigned and puts them back, so
        // the numbers repeat; what has to hold is that the state they describe
        // is the same state.
        #expect(second.assigned == 2)
        #expect(try assignment(ofLogID: logID) == windowID)
    }

    @Test("The rebuild with no windows at all touches nothing")
    func rebuildWithNoWindowsIsANoOp() throws {
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let logID = try logMeal(at: suhoor)
        _ = try logWater(at: suhoor)

        let counts = try assigner.assignUnassigned()

        #expect(counts.total == 0)
        #expect(try assignment(ofLogID: logID) == nil)
    }

    @Test("A window-scoped rebuild leaves other windows' assignments alone")
    func scopedRebuildTouchesOnlyItsOwnWindow() throws {
        let dWindow = try openNightWindow()
        // A second fast the following evening, so both windows exist at once.
        let nextMaghrib = maghribD.addingTimeInterval(24 * 3600)
        let nextFajr = fajrDPlus1.addingTimeInterval(24 * 3600)
        let tomorrowWindow = try windows.createWindow(date: "2026-09-18", windowType: .nightNutritionWindow,
                                                      startTimestamp: nextMaghrib, endTimestamp: nextFajr)
        let tomorrowIftar = nextMaghrib.addingTimeInterval(10 * 60)
        let tomorrowEntry = try logMeal(at: tomorrowIftar)
        try assigner.assign(nutritionLogID: tomorrowEntry, eatenAt: tomorrowIftar)
        #expect(try assignment(ofLogID: tomorrowEntry) == tomorrowWindow)

        // Rebuilding only D's window must not clear D+1's entry, even though the
        // scoped pass clears every assignment naming the window it is filling.
        _ = try assigner.assignUnassigned(inWindow: dWindow)

        #expect(try assignment(ofLogID: tomorrowEntry) == tomorrowWindow)
    }

    @Test("A window-scoped rebuild on an id that names no window is a no-op")
    func scopedRebuildOnMissingWindowIsANoOp() throws {
        let suhoor = Date(timeIntervalSince1970: 1_789_692_600)
        let logID = try logMeal(at: suhoor)

        let counts = try assigner.assignUnassigned(inWindow: 9999)

        #expect(counts.total == 0)
        #expect(try assignment(ofLogID: logID) == nil)
    }

    // MARK: - Coarse timestamps

    @Test("A month-precision entry is not assigned, because it has no timestamp to test")
    func coarseEntryIsNotAssigned() throws {
        try openNightWindow()
        // "2026-09" spans the window on paper. Whether the meal was eaten during
        // the fast is a different question, and the only honest stored value is
        // "not assigned" — the alternative is a guess that reads as a fact.
        let coarse = try #require(PartialDateTime(storedText: "2026-09", precision: .month, zone: riyadh))
        let id = try NutritionLogStore(db: db).record(NutritionLogDraft(
            foodRef: food, grams: 100, eatenAt: coarse)).logID

        let counts = try assigner.assignUnassigned()

        #expect(counts.total == 0)
        #expect(try assignment(ofLogID: id) == nil)
    }
}
