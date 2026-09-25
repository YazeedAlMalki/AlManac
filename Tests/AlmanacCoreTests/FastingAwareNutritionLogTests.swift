import Testing
import Foundation
@testable import AlmanacCore

@Suite("FastingAwareNutritionLog Tests")
struct FastingAwareNutritionLogTests {
    let db = try! TestDatabase()
    let clock = FixedClock(Date(timeIntervalSince1970: 2_000_000))
    var bridge: FastingAwareNutritionLog { FastingAwareNutritionLog(db: db, clock: clock) }
    var sessions: FastingSessionStore { FastingSessionStore(db: db, clock: clock) }

    private let knownFood = SourceIdentifier(namespace: .usda, localID: "known-food")
    private let unknownFood = SourceIdentifier(namespace: .usda, localID: "never-seeded")

    /// 200 kcal / 100g, published directly (not derived from macros) — the
    /// simplest fixture `EnergyEstimate.preferred` will accept.
    private func seedKnownFood() throws {
        try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group, attribution, url)
            VALUES ('usda', 'usda', 'USDA', '2026', 'CC0', 'A', '', '');
            INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
            VALUES ('energy_kcal', 'ENERC_KCAL', 'Energy', 'kcal', 'Energy');
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code, food_group_name, source_record)
            VALUES ('usda:known-food', 'usda', 'known-food', 'A', '', '', 'fixture');
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                                         source_value, source_nutrient_id, source_unit, licence_group)
            VALUES ('usda:known-food', 'energy_kcal', 'per_100g', 200, 'measured', NULL, '200',
                    'ENERC_KCAL', 'kcal', 'A');
            """)
    }

    private func startSession(at start: TimeInterval) throws -> Int64 {
        try sessions.start(FastingSessionDraft(startTimestamp: Date(timeIntervalSince1970: start),
                                                sessionType: .ifConfirmedSuggestion),
                            logicalDay: "2026-09-16")
    }

    private func meal(_ ref: SourceIdentifier, grams: Double?, eatenAt: Date) -> NutritionLogDraft {
        NutritionLogDraft(foodRef: ref, grams: grams,
                           eatenAt: PartialDateTime(instant: eatenAt, zone: ZoneContext(TimeZone(identifier: "UTC")!)))
    }

    @Test("Logging a real calorie-bearing meal breaks the active fast")
    func realCalorieEntryBreaksFast() throws {
        try seedKnownFood()
        let id = try startSession(at: 1_000_000)

        let result = try bridge.record(meal(knownFood, grams: 200, eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)))

        #expect(result.fastingOutcome == .ended(sessionId: id, durationMinutes: 60))
        #expect(try sessions.activeSession() == nil)
    }

    @Test("An entry with no stated amount does not break the fast")
    func noStatedAmountDoesNotBreak() throws {
        try seedKnownFood()
        try startSession(at: 1_000_000)

        let result = try bridge.record(meal(knownFood, grams: nil, eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)))

        #expect(result.fastingOutcome == .noOp)
        #expect(try sessions.activeSession()?.isActive == true)
    }

    @Test("An entry against an unseeded, uncomputable food does not break the fast")
    func unknownFoodDoesNotBreak() throws {
        try startSession(at: 1_000_000)

        let result = try bridge.record(meal(unknownFood, grams: 200, eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)))

        #expect(result.fastingOutcome == .noOp)
        #expect(try sessions.activeSession()?.isActive == true)
    }

    @Test("A backdated meal entry uses its own eatenAt, not the logging time")
    func usesEatenAtForBackdating() throws {
        try seedKnownFood()
        let id = try startSession(at: 1_000_000)

        // Logged "now" (clock.now = 2_000_000) but eaten before the fast even started.
        let result = try bridge.record(meal(knownFood, grams: 200, eatenAt: Date(timeIntervalSince1970: 900_000)))

        #expect(result.fastingOutcome == .invalidated(sessionId: id))
    }

    @Test("Editing a logged meal reconciles its edited timestamp")
    func editingMealReconcilesFastingState() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        let recorded = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)
        ))

        var edit = NutritionLogEdit()
        edit.eatenAt = .set(PartialDateTime(
            instant: Date(timeIntervalSince1970: 900_000),
            zone: ZoneContext(TimeZone(identifier: "UTC")!)
        ))
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .invalidated(sessionId: sessionID))
        #expect(try sessions.session(id: sessionID)?.isInvalidated == true)
    }

    @Test("Editing a meal's amount recomputes its energy before reconciling fasting")
    func editingAmountRecomputesEnergy() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        let recorded = try bridge.record(meal(
            knownFood,
            grams: nil,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)
        ))

        var edit = NutritionLogEdit()
        edit.grams = .set(200)
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .ended(sessionId: sessionID, durationMinutes: 60))
        #expect(try sessions.activeSession() == nil)
    }

    @Test("Removing a meal's calories restores the fast it had ended")
    func removingCaloriesRestoresEndedFast() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        let recorded = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)
        ))

        var edit = NutritionLogEdit()
        edit.grams = .clear
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .restored(sessionId: sessionID))
        #expect(try sessions.activeSession()?.id == sessionID)
    }

    @Test("Moving an invalidated meal into the fast reopens and re-breaks it")
    func movingInvalidatedMealReconcilesAgain() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        let recorded = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 900_000)
        ))
        #expect(try sessions.session(id: sessionID)?.isInvalidated == true)

        var edit = NutritionLogEdit()
        edit.eatenAt = .set(PartialDateTime(
            instant: Date(timeIntervalSince1970: 1_000_000 + 3600),
            zone: ZoneContext(TimeZone(identifier: "UTC")!)
        ))
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .ended(sessionId: sessionID, durationMinutes: 60))
        #expect(try sessions.session(id: sessionID)?.isInvalidated == false)
        #expect(try sessions.activeSession() == nil)
    }

    @Test("Removing a shortened meal restores the previous end")
    func removingShortenedMealRestoresPreviousEnd() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        _ = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 7200)
        ))
        let shortened = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)
        ))

        var edit = NutritionLogEdit()
        edit.grams = .clear
        let result = try bridge.update(id: shortened.outcome.logID, edit)

        #expect(result.fastingOutcome == .restored(sessionId: sessionID))
        #expect(try sessions.session(id: sessionID)?.endTimestamp == Date(timeIntervalSince1970: 1_000_000 + 7200))
        #expect(try sessions.session(id: sessionID)?.isActive == false)
    }

    @Test("Moving a shortened meal later extends the restored end")
    func movingShortenedMealLaterExtendsEnd() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        _ = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 7200)
        ))
        let shortened = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)
        ))

        var edit = NutritionLogEdit()
        edit.eatenAt = .set(PartialDateTime(
            instant: Date(timeIntervalSince1970: 1_000_000 + 10_800),
            zone: ZoneContext(TimeZone(identifier: "UTC")!)
        ))
        _ = try bridge.update(id: shortened.outcome.logID, edit)

        #expect(try sessions.session(id: sessionID)?.endTimestamp == Date(timeIntervalSince1970: 1_000_000 + 10_800))
        #expect(try sessions.session(id: sessionID)?.correctionHistory.last?.action == .extended)

        var clear = NutritionLogEdit()
        clear.grams = .clear
        let restored = try bridge.update(id: shortened.outcome.logID, clear)
        #expect(restored.fastingOutcome == .restored(sessionId: sessionID))
        #expect(try sessions.session(id: sessionID)?.endTimestamp == Date(timeIntervalSince1970: 1_000_000 + 7200))
        #expect(try sessions.session(id: sessionID)?.isActive == false)
    }

    @Test("An old meal edit does not reopen over a newer active fast")
    func oldMealEditDoesNotConflictWithNewActiveFast() throws {
        try seedKnownFood()
        let oldSession = try startSession(at: 1_000_000)
        let recorded = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 3600)
        ))
        let newSession = try sessions.start(FastingSessionDraft(
            startTimestamp: Date(timeIntervalSince1970: 1_000_000 + 7200),
            sessionType: .ifPlanned
        ), logicalDay: "2026-09-16")

        var edit = NutritionLogEdit()
        edit.grams = .clear
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .noOp)
        #expect(try sessions.session(id: oldSession)?.isActive == false)
        #expect(try sessions.activeSession()?.id == newSession)
    }

    @Test("Moving an invalidated meal after an ended fast does not extend it")
    func movingInvalidatedMealAfterEndedFastDoesNotExtend() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        _ = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 1_000_000 + 7200)
        ))
        let invalidated = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 900_000)
        ))

        var edit = NutritionLogEdit()
        edit.eatenAt = .set(PartialDateTime(
            instant: Date(timeIntervalSince1970: 1_000_000 + 10_800),
            zone: ZoneContext(TimeZone(identifier: "UTC")!)
        ))
        let result = try bridge.update(id: invalidated.outcome.logID, edit)

        #expect(result.fastingOutcome == .noOp)
        #expect(try sessions.session(id: sessionID)?.isInvalidated == false)
        #expect(try sessions.session(id: sessionID)?.endTimestamp == Date(timeIntervalSince1970: 1_000_000 + 7200))
    }

    @Test("An unknown eaten time uses the original recorded time when edited")
    func unknownEatenTimeUsesRecordedTime() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        let recorded = try bridge.record(NutritionLogDraft(
            foodRef: knownFood, grams: 200, eatenAt: .unknown
        ))
        #expect(try sessions.session(id: sessionID)?.isActive == false)
        clock.advance(by: 3600)

        var edit = NutritionLogEdit()
        edit.grams = .clear
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .restored(sessionId: sessionID))
        #expect(try sessions.activeSession()?.id == sessionID)
    }

    @Test("A metadata-only meal edit does not reconcile fasting state")
    func metadataOnlyEditDoesNotTouchFasting() throws {
        try seedKnownFood()
        let sessionID = try startSession(at: 1_000_000)
        let recorded = try bridge.record(meal(
            knownFood,
            grams: 200,
            eatenAt: Date(timeIntervalSince1970: 900_000)
        ))
        #expect(try sessions.session(id: sessionID)?.isInvalidated == true)

        var edit = NutritionLogEdit()
        edit.foodNameText = .set("Corrected label only")
        edit.grams = .set(200)
        let result = try bridge.update(id: recorded.outcome.logID, edit)

        #expect(result.fastingOutcome == .noOp)
        #expect(try sessions.session(id: sessionID)?.isInvalidated == true)
    }
}
