import Testing
import Foundation
@testable import AlmanacCore

@Suite("SleepEpisodeHealthBridge Tests")
struct SleepEpisodeHealthBridgeTests {
    let db = try! TestDatabase()
    var bridge: SleepEpisodeHealthBridge { SleepEpisodeHealthBridge(db: db) }
    
    @Test("Insert sleep sample from HealthKit")
    func insertSleepSample() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 30000)
        
        let sample = HealthSample(externalID: "hk-sleep-123", domain: .sleep,
                                  start: start, end: end, value: nil, unit: nil)
        let changeSet = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        
        let counts = try bridge.apply(changeSet, in: db)
        
        #expect(counts.inserted == 1)
        #expect(counts.updated == 0)
        #expect(counts.deleted == 0)
    }
    
    @Test("Update existing sleep sample")
    func updateSleepSample() throws {
        let start1 = Date(timeIntervalSince1970: 1000)
        let end1 = Date(timeIntervalSince1970: 30000)
        let sample1 = HealthSample(externalID: "hk-sleep-123", domain: .sleep,
                                   start: start1, end: end1, value: nil, unit: nil)
        let changeSet1 = HealthChangeSet(added: [sample1], deletedExternalIDs: [], nextAnchor: nil)
        
        try bridge.apply(changeSet1, in: db)
        
        // Update with new times
        let start2 = Date(timeIntervalSince1970: 2000)
        let end2 = Date(timeIntervalSince1970: 31000)
        let sample2 = HealthSample(externalID: "hk-sleep-123", domain: .sleep,
                                   start: start2, end: end2, value: nil, unit: nil)
        let changeSet2 = HealthChangeSet(added: [sample2], deletedExternalIDs: [], nextAnchor: nil)
        
        let counts = try bridge.apply(changeSet2, in: db)
        
        #expect(counts.inserted == 0)
        #expect(counts.updated == 1)
    }
    
    @Test("Soft delete sleep sample")
    func softDeleteSleep() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 30000)
        let sample = HealthSample(externalID: "hk-sleep-123", domain: .sleep,
                                  start: start, end: end, value: nil, unit: nil)
        let changeSet1 = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        
        try bridge.apply(changeSet1, in: db)
        
        // Delete it
        let changeSet2 = HealthChangeSet(added: [], deletedExternalIDs: ["hk-sleep-123"], nextAnchor: nil)
        let counts = try bridge.apply(changeSet2, in: db)
        
        #expect(counts.deleted == 1)
    }
    
    @Test("Do not resurrect deleted sleep sample")
    func doNotResurrectDeleted() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 30000)
        let sample = HealthSample(externalID: "hk-sleep-123", domain: .sleep,
                                  start: start, end: end, value: nil, unit: nil)
        
        // Insert and delete
        let changeSet1 = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        try bridge.apply(changeSet1, in: db)
        
        let changeSet2 = HealthChangeSet(added: [], deletedExternalIDs: ["hk-sleep-123"], nextAnchor: nil)
        try bridge.apply(changeSet2, in: db)
        
        // Try to re-insert the same sample
        let changeSet3 = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        let counts = try bridge.apply(changeSet3, in: db)
        
        // Should not resurrect
        #expect(counts.inserted == 0)
        #expect(counts.updated == 0)
    }
}
