import Testing
import Foundation
@testable import AlmanacCore

@Suite("MoodLogStore Tests")
struct MoodLogStoreTests {
    let db = try! TestDatabase()
    var store: MoodLogStore { MoodLogStore(db: db) }
    
    @Test("Log mood entry")
    func logMood() throws {
        let draft = MoodLogDraft(score: 7, timestamp: Date(), notes: "Feeling good")
        let id = try store.log(draft, logicalDay: "2026-09-16")
        
        let entry = try store.entry(id: id)
        #expect(entry?.score == 7)
        #expect(entry?.notes == "Feeling good")
        #expect(entry?.logicalDay == "2026-09-16")
    }
    
    @Test("Score clamping to 1-10")
    func scoreClamping() throws {
        let draftLow = MoodLogDraft(score: 0, timestamp: Date())
        let draftHigh = MoodLogDraft(score: 15, timestamp: Date())
        
        let idLow = try store.log(draftLow, logicalDay: "2026-09-16")
        let idHigh = try store.log(draftHigh, logicalDay: "2026-09-16")
        
        let entryLow = try store.entry(id: idLow)
        let entryHigh = try store.entry(id: idHigh)
        
        #expect(entryLow?.score == 1)
        #expect(entryHigh?.score == 10)
    }
    
    @Test("Fetch logs for logical day")
    func logsForDay() throws {
        try store.log(MoodLogDraft(score: 5, timestamp: Date()), logicalDay: "2026-09-16")
        try store.log(MoodLogDraft(score: 7, timestamp: Date()), logicalDay: "2026-09-16")
        try store.log(MoodLogDraft(score: 8, timestamp: Date()), logicalDay: "2026-09-17")
        
        let logsDay16 = try store.logs(for: "2026-09-16")
        let logsDay17 = try store.logs(for: "2026-09-17")
        
        #expect(logsDay16.count == 2)
        #expect(logsDay17.count == 1)
    }
    
    @Test("Link mood to readiness cycle")
    func linkToReadinessCycle() throws {
        let id = try store.log(MoodLogDraft(score: 6, timestamp: Date()), logicalDay: "2026-09-16")
        
        try store.linkToReadinessCycle(id: id, cycleId: 42)
        
        let entry = try store.entry(id: id)
        #expect(entry?.readinessCycleId == 42)
    }
    
    @Test("Update mood score")
    func updateScore() throws {
        let id = try store.log(MoodLogDraft(score: 5, timestamp: Date()), logicalDay: "2026-09-16")
        
        try store.updateScore(id: id, to: 8)
        
        let entry = try store.entry(id: id)
        #expect(entry?.score == 8)
    }
}
