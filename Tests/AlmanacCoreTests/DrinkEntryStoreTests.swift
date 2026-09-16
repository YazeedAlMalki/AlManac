import Testing
import Foundation
@testable import AlmanacCore

@Suite("DrinkEntryStore Tests")
struct DrinkEntryStoreTests {
    let db = try! TestDatabase()
    var store: DrinkEntryStore { DrinkEntryStore(db: db) }
    
    @Test("Log drink entry")
    func logDrink() throws {
        let draft = DrinkEntryDraft(timestamp: Date(), drinkType: "coffee_black",
                                     fluidVolumeMl: 250, caffeineMg: 95)
        let id = try store.log(draft, logicalDay: "2026-09-16")
        
        let entry = try store.entry(id: id)
        #expect(entry?.drinkType == "coffee_black")
        #expect(entry?.caffeineMg == 95)
        #expect(entry?.fluidVolumeMl == 250)
    }
    
    @Test("Total caffeine for day")
    func totalCaffeine() throws {
        try store.log(DrinkEntryDraft(timestamp: Date(), drinkType: "coffee_black", caffeineMg: 95), 
                     logicalDay: "2026-09-16")
        try store.log(DrinkEntryDraft(timestamp: Date(), drinkType: "tea_black", caffeineMg: 50),
                     logicalDay: "2026-09-16")
        try store.log(DrinkEntryDraft(timestamp: Date(), drinkType: "water", caffeineMg: 0),
                     logicalDay: "2026-09-16")
        
        let total = try store.totalCaffeine(for: "2026-09-16")
        #expect(total == 145)
    }
    
    @Test("Fetch entries for day")
    func entriesForDay() throws {
        try store.log(DrinkEntryDraft(timestamp: Date(), drinkType: "coffee_black"),
                     logicalDay: "2026-09-16")
        try store.log(DrinkEntryDraft(timestamp: Date(), drinkType: "water"),
                     logicalDay: "2026-09-16")
        try store.log(DrinkEntryDraft(timestamp: Date(), drinkType: "tea_black"),
                     logicalDay: "2026-09-17")
        
        let day16 = try store.entries(for: "2026-09-16")
        let day17 = try store.entries(for: "2026-09-17")
        
        #expect(day16.count == 2)
        #expect(day17.count == 1)
    }
}
