import Testing
import Foundation
@testable import AlmanacCore

@Suite("VitalsRecordHealthBridge Tests")
struct VitalsRecordHealthBridgeTests {
    let db = try! TestDatabase()
    var bridge: VitalsRecordHealthBridge { VitalsRecordHealthBridge(db: db) }
    
    @Test("Insert RHR sample from HealthKit")
    func insertRHRSample() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        
        let sample = HealthSample(externalID: "hk-rhr-001", domain: .heartRate,
                                  start: timestamp, end: timestamp, value: 62.0, unit: "bpm")
        let changeSet = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        
        let counts = try bridge.apply(changeSet, in: db)
        
        #expect(counts.inserted == 1)
    }
    
    @Test("Insert multiple vitals domains")
    func insertMultipleDomains() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        
        let rhr = HealthSample(externalID: "hk-rhr-001", domain: .heartRate,
                               start: timestamp, end: timestamp, value: 62.0, unit: "bpm")
        let hrv = HealthSample(externalID: "hk-hrv-001", domain: .hrv,
                               start: timestamp, end: timestamp, value: 45.0, unit: "ms")
        let steps = HealthSample(externalID: "hk-steps-001", domain: .steps,
                                 start: timestamp, end: timestamp, value: 8234.0, unit: "count")
        
        let changeSet = HealthChangeSet(added: [rhr, hrv, steps], deletedExternalIDs: [], nextAnchor: nil)
        let counts = try bridge.apply(changeSet, in: db)
        
        #expect(counts.inserted == 3)
    }
    
    @Test("Update existing vitals sample")
    func updateVitalsSample() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        
        let sample1 = HealthSample(externalID: "hk-rhr-001", domain: .heartRate,
                                   start: timestamp, end: timestamp, value: 62.0, unit: "bpm")
        let changeSet1 = HealthChangeSet(added: [sample1], deletedExternalIDs: [], nextAnchor: nil)
        try bridge.apply(changeSet1, in: db)
        
        // Update with different value
        let timestamp2 = Date(timeIntervalSince1970: 2000)
        let sample2 = HealthSample(externalID: "hk-rhr-001", domain: .heartRate,
                                   start: timestamp2, end: timestamp2, value: 58.0, unit: "bpm")
        let changeSet2 = HealthChangeSet(added: [sample2], deletedExternalIDs: [], nextAnchor: nil)
        let counts = try bridge.apply(changeSet2, in: db)
        
        #expect(counts.updated == 1)
    }
    
    @Test("Handle samples without values")
    func samplesWithoutValues() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        
        // Sample with nil value should not be inserted
        let sample = HealthSample(externalID: "hk-rhr-001", domain: .heartRate,
                                  start: timestamp, end: timestamp, value: nil, unit: "bpm")
        let changeSet = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        
        let counts = try bridge.apply(changeSet, in: db)
        
        #expect(counts.inserted == 0)
    }
    
    @Test("Soft delete vitals sample")
    func softDeleteVitals() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        
        let sample = HealthSample(externalID: "hk-rhr-001", domain: .heartRate,
                                  start: timestamp, end: timestamp, value: 62.0, unit: "bpm")
        let changeSet1 = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)
        try bridge.apply(changeSet1, in: db)
        
        // Delete it
        let changeSet2 = HealthChangeSet(added: [], deletedExternalIDs: ["hk-rhr-001"], nextAnchor: nil)
        let counts = try bridge.apply(changeSet2, in: db)
        
        #expect(counts.deleted == 1)
    }
}
