import Testing
import Foundation
@testable import AlmanacCore

@Suite("Readiness Cycle Linking Tests")
struct ReadinessCycleLinkingTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
        // All three tests below link against readiness_cycle id 1;
        // readinessCycleId is a real FK (§5.6/§5.7), so it must exist first.
        try db.run("INSERT INTO readiness_cycle (id, anchorDate, createdAt, updatedAt) VALUES (1, '2026-09-16', '2026-09-16T00:00:00Z', '2026-09-16T00:00:00Z');")
    }
    
    @Test("Link mood and soreness logs to readiness cycle within time window")
    func linkLogsWithinWindow() throws {
        let moodStore = MoodLogStore(db: db)
        let sorenessStore = SorenessLogStore(db: db)
        let linkingService = ReadinessCycleLinkingService(db: db)
        
        let cycleStart = Date(timeIntervalSince1970: 1000)
        let cycleEnd = Date(timeIntervalSince1970: 5000)
        let beforeStart = Date(timeIntervalSince1970: 500)
        let afterEnd = Date(timeIntervalSince1970: 6000)
        let withinWindow = Date(timeIntervalSince1970: 3000)
        
        // Log entries at various times
        let moodBefore = try moodStore.log(MoodLogDraft(score: 5, timestamp: beforeStart), logicalDay: "2026-09-15")
        let moodWithin = try moodStore.log(MoodLogDraft(score: 7, timestamp: withinWindow), logicalDay: "2026-09-16")
        let moodAfter = try moodStore.log(MoodLogDraft(score: 6, timestamp: afterEnd), logicalDay: "2026-09-17")
        
        let sorBefore = try sorenessStore.log(SorenessLogDraft(overallScore: 3, timestamp: beforeStart), logicalDay: "2026-09-15")
        let sorWithin = try sorenessStore.log(SorenessLogDraft(overallScore: 4, timestamp: withinWindow), logicalDay: "2026-09-16")
        let sorAfter = try sorenessStore.log(SorenessLogDraft(overallScore: 2, timestamp: afterEnd), logicalDay: "2026-09-17")
        
        // Link logs within the cycle window
        try linkingService.linkLogsToReadinessCycle(cycleId: 1, 
                                                    cycleStartTimestamp: cycleStart,
                                                    cycleEndTimestamp: cycleEnd)
        
        // Check which entries were linked
        let moodBeforeEntry = try moodStore.entry(id: moodBefore)
        let moodWithinEntry = try moodStore.entry(id: moodWithin)
        let moodAfterEntry = try moodStore.entry(id: moodAfter)
        
        let sorBeforeEntry = try sorenessStore.entry(id: sorBefore)
        let sorWithinEntry = try sorenessStore.entry(id: sorWithin)
        let sorAfterEntry = try sorenessStore.entry(id: sorAfter)
        
        // Only entries within the window should be linked
        #expect(moodBeforeEntry?.readinessCycleId == nil)
        #expect(moodWithinEntry?.readinessCycleId == 1)
        #expect(moodAfterEntry?.readinessCycleId == nil)
        
        #expect(sorBeforeEntry?.readinessCycleId == nil)
        #expect(sorWithinEntry?.readinessCycleId == 1)
        #expect(sorAfterEntry?.readinessCycleId == nil)
    }
    
    @Test("Link logs to current cycle (no end timestamp)")
    func linkToCurrentCycle() throws {
        let moodStore = MoodLogStore(db: db)
        let linkingService = ReadinessCycleLinkingService(db: db)
        
        let cycleStart = Date(timeIntervalSince1970: 1000)
        let withinWindow = Date(timeIntervalSince1970: 3000)
        let afterStart = Date(timeIntervalSince1970: 5000)
        
        // Log entries
        let moodBefore = try moodStore.log(MoodLogDraft(score: 5, timestamp: Date(timeIntervalSince1970: 500)), logicalDay: "2026-09-15")
        let moodWithin1 = try moodStore.log(MoodLogDraft(score: 7, timestamp: withinWindow), logicalDay: "2026-09-16")
        let moodWithin2 = try moodStore.log(MoodLogDraft(score: 8, timestamp: afterStart), logicalDay: "2026-09-16")
        
        // Link logs for current cycle (no end timestamp)
        try linkingService.linkLogsToReadinessCycle(cycleId: 1,
                                                    cycleStartTimestamp: cycleStart,
                                                    cycleEndTimestamp: nil)
        
        // Check results
        let moodBeforeEntry = try moodStore.entry(id: moodBefore)
        let moodWithin1Entry = try moodStore.entry(id: moodWithin1)
        let moodWithin2Entry = try moodStore.entry(id: moodWithin2)
        
        #expect(moodBeforeEntry?.readinessCycleId == nil)
        #expect(moodWithin1Entry?.readinessCycleId == 1)
        #expect(moodWithin2Entry?.readinessCycleId == 1)
    }
    
    @Test("Relink logs after cycle adjustment")
    func relinkAfterAdjustment() throws {
        let moodStore = MoodLogStore(db: db)
        let linkingService = ReadinessCycleLinkingService(db: db)
        
        let original = Date(timeIntervalSince1970: 1000)
        let adjusted = Date(timeIntervalSince1970: 2000)
        let logTime = Date(timeIntervalSince1970: 1500)
        
        // Log entry
        let moodId = try moodStore.log(MoodLogDraft(score: 7, timestamp: logTime), logicalDay: "2026-09-16")
        
        // Initial link
        try linkingService.linkLogsToReadinessCycle(cycleId: 1,
                                                    cycleStartTimestamp: original,
                                                    cycleEndTimestamp: Date(timeIntervalSince1970: 3000))
        
        var entry = try moodStore.entry(id: moodId)
        #expect(entry?.readinessCycleId == 1)
        
        // Relink with adjusted start time that now excludes the log
        try linkingService.relinkLogsToReadinessCycle(cycleId: 1,
                                                      cycleStartTimestamp: adjusted,
                                                      cycleEndTimestamp: Date(timeIntervalSince1970: 3000))
        
        entry = try moodStore.entry(id: moodId)
        #expect(entry?.readinessCycleId == nil)
    }
}
