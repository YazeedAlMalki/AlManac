import Testing
import Foundation
@testable import AlmanacCore

@Suite("IFSuggestionService Tests")
struct IFSuggestionServiceTests {
    let db = try! TestDatabase()
    var log: NutritionLogStore { NutritionLogStore(db: db) }
    var service: IFSuggestionService { IFSuggestionService(db: db) }

    private let food = SourceIdentifier(namespace: .usda, localID: "test-food")
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func logMeal(hoursAgo: Double, grams: Double? = 200) throws {
        try log.record(NutritionLogDraft(
            foodRef: food, grams: grams,
            eatenAt: PartialDateTime(instant: now.addingTimeInterval(-hoursAgo * 3600),
                                     zone: ZoneContext(TimeZone(identifier: "UTC")!))))
    }

    @Test("No food logged at all is at least the threshold — always suggest")
    func noEntriesSuggestsFast() throws {
        #expect(try service.shouldSuggestFast(at: now, thresholdHours: 14) == true)
    }

    @Test("Recent meal within the threshold does not suggest")
    func recentMealDoesNotSuggest() throws {
        try logMeal(hoursAgo: 10)
        #expect(try service.shouldSuggestFast(at: now, thresholdHours: 14) == false)
    }

    @Test("A meal older than the threshold, with nothing more recent, suggests")
    func oldMealSuggests() throws {
        try logMeal(hoursAgo: 15)
        #expect(try service.shouldSuggestFast(at: now, thresholdHours: 14) == true)
    }

    @Test("Takes the most recent qualifying meal, not the oldest")
    func usesMostRecentMeal() throws {
        try logMeal(hoursAgo: 20)
        try logMeal(hoursAgo: 5)
        let hours = try service.hoursSinceLastCalorieEntry(before: now)
        #expect(hours == 5)
    }

    @Test("An entry with no stated amount does not reset the gap")
    func unstatedAmountDoesNotCount() throws {
        try logMeal(hoursAgo: 20)
        try logMeal(hoursAgo: 1, grams: nil)  // "some rice, amount not stated"

        let hours = try service.hoursSinceLastCalorieEntry(before: now)
        #expect(hours == 20)
    }

    @Test("Threshold is configurable through to the service")
    func configurableThreshold() throws {
        try logMeal(hoursAgo: 13)
        #expect(try service.shouldSuggestFast(at: now, thresholdHours: 12) == true)
        #expect(try service.shouldSuggestFast(at: now, thresholdHours: 14) == false)
    }
}
