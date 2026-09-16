import Testing
import Foundation
@testable import AlmanacCore

@Suite("SorenessLogStore Tests")
struct SorenessLogStoreTests {
    let db = try! TestDatabase()
    var store: SorenessLogStore { SorenessLogStore(db: db) }
    
    @Test("Log soreness entry with body areas")
    func logSoreness() throws {
        let bodyAreas = ["left shoulder", "right knee"]
        let draft = SorenessLogDraft(overallScore: 6, timestamp: Date(), 
                                     bodyAreas: bodyAreas, notes: "Post-training soreness")
        let id = try store.log(draft, logicalDay: "2026-09-16")
        
        let entry = try store.entry(id: id)
        #expect(entry?.overallScore == 6)
        #expect(entry?.bodyAreas == bodyAreas)
        #expect(entry?.logicalDay == "2026-09-16")
    }
    
    @Test("Fetch soreness logs for logical day")
    func logsForDay() throws {
        try store.log(SorenessLogDraft(overallScore: 4, timestamp: Date()), logicalDay: "2026-09-16")
        try store.log(SorenessLogDraft(overallScore: 5, timestamp: Date()), logicalDay: "2026-09-16")
        try store.log(SorenessLogDraft(overallScore: 3, timestamp: Date()), logicalDay: "2026-09-17")
        
        let logsDay16 = try store.logs(for: "2026-09-16")
        let logsDay17 = try store.logs(for: "2026-09-17")
        
        #expect(logsDay16.count == 2)
        #expect(logsDay17.count == 1)
    }
    
    @Test("Link soreness to readiness cycle")
    func linkToReadinessCycle() throws {
        let id = try store.log(SorenessLogDraft(overallScore: 5, timestamp: Date()), logicalDay: "2026-09-16")
        
        try store.linkToReadinessCycle(id: id, cycleId: 99)
        
        let entry = try store.entry(id: id)
        #expect(entry?.readinessCycleId == 99)
    }
    
    @Test("Update body areas")
    func updateBodyAreas() throws {
        let id = try store.log(SorenessLogDraft(overallScore: 5, timestamp: Date(),
                                                bodyAreas: ["neck"]), logicalDay: "2026-09-16")
        
        try store.updateBodyAreas(id: id, to: ["back", "legs"])
        
        let entry = try store.entry(id: id)
        #expect(entry?.bodyAreas == ["back", "legs"])
    }
}
