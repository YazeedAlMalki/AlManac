import Testing
import Foundation
@testable import AlmanacCore

@Suite("VitalsRecordStore Tests")
struct VitalsRecordStoreTests {
    let db = try! TestDatabase()
    var store: VitalsRecordStore { VitalsRecordStore(db: db) }
    
    @Test("Record vitals metric")
    func recordVitals() throws {
        let draft = VitalsRecordDraft(metric: "rhr", value: 62.0, unit: "bpm",
                                       timestamp: Date(), source: "manual")
        let id = try store.record(draft, logicalDay: "2026-09-16")
        
        let record = try store.record(id: id)
        #expect(record?.metric == "rhr")
        #expect(record?.value == 62.0)
        #expect(record?.unit == "bpm")
        #expect(record?.source == "manual")
    }
    
    @Test("Record multiple metrics in one day")
    func multipleMetricsOneDay() throws {
        try store.record(VitalsRecordDraft(metric: "rhr", value: 62.0, unit: "bpm",
                                            timestamp: Date(), source: "manual"), logicalDay: "2026-09-16")
        try store.record(VitalsRecordDraft(metric: "hrv", value: 45.0, unit: "ms",
                                            timestamp: Date(), source: "manual"), logicalDay: "2026-09-16")
        try store.record(VitalsRecordDraft(metric: "spo2", value: 97.0, unit: "%",
                                            timestamp: Date(), source: "device"), logicalDay: "2026-09-16")
        
        let records = try store.records(for: "2026-09-16")
        #expect(records.count == 3)
    }
    
    @Test("Fetch latest value for metric")
    func latestValue() throws {
        let time1 = Date(timeIntervalSince1970: 1000)
        let time2 = Date(timeIntervalSince1970: 2000)
        let time3 = Date(timeIntervalSince1970: 3000)
        
        try store.record(VitalsRecordDraft(metric: "rhr", value: 65.0, unit: "bpm",
                                            timestamp: time1, source: "manual"), logicalDay: "2026-09-15")
        try store.record(VitalsRecordDraft(metric: "rhr", value: 62.0, unit: "bpm",
                                            timestamp: time2, source: "manual"), logicalDay: "2026-09-16")
        try store.record(VitalsRecordDraft(metric: "rhr", value: 60.0, unit: "bpm",
                                            timestamp: time3, source: "manual"), logicalDay: "2026-09-17")
        
        let latest = try store.latestValue(for: "rhr")
        #expect(latest?.value == 60.0)
    }
    
    @Test("Fetch records by metric across date range")
    func recordsByMetricRange() throws {
        try store.record(VitalsRecordDraft(metric: "rhr", value: 65.0, unit: "bpm",
                                            timestamp: Date(), source: "manual"), logicalDay: "2026-09-15")
        try store.record(VitalsRecordDraft(metric: "rhr", value: 62.0, unit: "bpm",
                                            timestamp: Date(), source: "manual"), logicalDay: "2026-09-16")
        try store.record(VitalsRecordDraft(metric: "rhr", value: 60.0, unit: "bpm",
                                            timestamp: Date(), source: "manual"), logicalDay: "2026-09-17")
        
        let records = try store.records(metric: "rhr", from: "2026-09-16", to: "2026-09-18")
        #expect(records.count == 2)
    }
}
