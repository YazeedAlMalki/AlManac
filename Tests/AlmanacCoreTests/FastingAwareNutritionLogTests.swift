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
}
