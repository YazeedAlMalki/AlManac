import Testing
import Foundation
@testable import AlmanacCore

@Suite("CaffeineLogStore Tests")
struct CaffeineLogStoreTests {
    let db = try! TestDatabase()
    var store: CaffeineLogStore { CaffeineLogStore(db: db) }
    
    @Test("Log caffeine entry without sleep time")
    func logWithoutSleepTime() throws {
        let draft = CaffeineLogDraft(timestamp: Date(), drinkType: "coffee_black", caffeineMg: 95)
        let id = try store.log(draft, logicalDay: "2026-09-16")
        
        let entry = try store.entry(id: id)
        #expect(entry?.caffeineMg == 95)
        #expect(entry?.caffeineContext == nil)
    }
    
    @Test("Compute early caffeine context (>6 hours before sleep)")
    func earlyContext() throws {
        let drinkTime = Date(timeIntervalSince1970: 1000)
        let sleepTime = Date(timeIntervalSince1970: 1000 + (7 * 3600))  // 7 hours later
        
        let draft = CaffeineLogDraft(timestamp: drinkTime, drinkType: "coffee_black",
                                      caffeineMg: 95, intendedSleepTimestamp: sleepTime)
        let id = try store.log(draft, logicalDay: "2026-09-16")
        
        let entry = try store.entry(id: id)
        #expect(entry?.caffeineContext == "early")
        #expect((entry?.hoursBeforeIntendedSleep ?? 0) > 6)
    }
    
    @Test("Compute late caffeine context (<1 hour before sleep)")
    func lateContext() throws {
        let drinkTime = Date(timeIntervalSince1970: 1000)
        let sleepTime = Date(timeIntervalSince1970: 1000 + (30 * 60))  // 30 minutes later
        
        let draft = CaffeineLogDraft(timestamp: drinkTime, drinkType: "coffee_black",
                                      caffeineMg: 95, intendedSleepTimestamp: sleepTime)
        let id = try store.log(draft, logicalDay: "2026-09-16")
        
        let entry = try store.entry(id: id)
        #expect(entry?.caffeineContext == "very_late")
        #expect((entry?.hoursBeforeIntendedSleep ?? 0) < 1)
    }
    
    @Test("Total caffeine for day")
    func totalCaffeine() throws {
        let time1 = Date(timeIntervalSince1970: 1000)
        let time2 = Date(timeIntervalSince1970: 2000)
        
        try store.log(CaffeineLogDraft(timestamp: time1, drinkType: "coffee_black", caffeineMg: 95),
                     logicalDay: "2026-09-16")
        try store.log(CaffeineLogDraft(timestamp: time2, drinkType: "tea_black", caffeineMg: 50),
                     logicalDay: "2026-09-16")
        
        let total = try store.totalCaffeine(for: "2026-09-16")
        #expect(total == 145)
    }
    
    @Test("Fetch entries by context")
    func entriesByContext() throws {
        let sleepTime = Date(timeIntervalSince1970: 10000)
        
        let earlyTime = Date(timeIntervalSince1970: 10000 - (8 * 3600))
        let lateTime = Date(timeIntervalSince1970: 10000 - (30 * 60))
        
        try store.log(CaffeineLogDraft(timestamp: earlyTime, drinkType: "coffee_black",
                                        caffeineMg: 95, intendedSleepTimestamp: sleepTime),
                     logicalDay: "2026-09-16")
        try store.log(CaffeineLogDraft(timestamp: lateTime, drinkType: "coffee_latte",
                                        caffeineMg: 75, intendedSleepTimestamp: sleepTime),
                     logicalDay: "2026-09-16")
        
        let early = try store.entries(context: "early", for: "2026-09-16")
        let veryLate = try store.entries(context: "very_late", for: "2026-09-16")
        
        #expect(early.count == 1)
        #expect(veryLate.count == 1)
    }
}
