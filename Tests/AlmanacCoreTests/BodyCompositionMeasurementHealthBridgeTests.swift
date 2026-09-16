import Testing
import Foundation
@testable import AlmanacCore

@Suite("BodyCompositionMeasurementHealthBridge Tests")
struct BodyCompositionMeasurementHealthBridgeTests {
    let db = try! TestDatabase()
    var bridge: BodyCompositionMeasurementHealthBridge { BodyCompositionMeasurementHealthBridge(db: db) }

    @Test("Insert weight sample from HealthKit")
    func insertWeightSample() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)

        let sample = HealthSample(externalID: "hk-weight-001", domain: .bodyMass,
                                  start: timestamp, end: timestamp, value: 82.4, unit: "kg")
        let changeSet = HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil)

        let counts = try bridge.apply(changeSet, in: db)

        #expect(counts.inserted == 1)

        let store = BodyCompositionMeasurementStore(db: db)
        let latest = try store.latestValue(for: "weight")
        #expect(latest?.value == 82.4)
        #expect(latest?.source == "apple_health")
        #expect(latest?.conditions == "unknown")
    }

    @Test("Insert body fat and lean mass samples")
    func insertMultipleDomains() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)

        let bodyFat = HealthSample(externalID: "hk-bf-001", domain: .bodyFatPercentage,
                                   start: timestamp, end: timestamp, value: 18.0, unit: "%")
        let leanMass = HealthSample(externalID: "hk-lbm-001", domain: .leanBodyMass,
                                    start: timestamp, end: timestamp, value: 65.0, unit: "kg")

        let changeSet = HealthChangeSet(added: [bodyFat, leanMass], deletedExternalIDs: [], nextAnchor: nil)
        let counts = try bridge.apply(changeSet, in: db)

        #expect(counts.inserted == 2)

        let store = BodyCompositionMeasurementStore(db: db)
        #expect(try store.latestValue(for: "body_fat_pct")?.value == 18.0)
        #expect(try store.latestValue(for: "lean_mass_kg")?.value == 65.0)
    }

    @Test("Update existing body composition sample")
    func updateSample() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)

        let sample1 = HealthSample(externalID: "hk-weight-001", domain: .bodyMass,
                                   start: timestamp, end: timestamp, value: 82.4, unit: "kg")
        try bridge.apply(HealthChangeSet(added: [sample1], deletedExternalIDs: [], nextAnchor: nil), in: db)

        let timestamp2 = Date(timeIntervalSince1970: 2000)
        let sample2 = HealthSample(externalID: "hk-weight-001", domain: .bodyMass,
                                   start: timestamp2, end: timestamp2, value: 81.9, unit: "kg")
        let counts = try bridge.apply(HealthChangeSet(added: [sample2], deletedExternalIDs: [], nextAnchor: nil), in: db)

        #expect(counts.updated == 1)
    }

    @Test("Soft delete body composition sample")
    func softDelete() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let sample = HealthSample(externalID: "hk-weight-001", domain: .bodyMass,
                                  start: timestamp, end: timestamp, value: 82.4, unit: "kg")
        try bridge.apply(HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil), in: db)

        let counts = try bridge.apply(HealthChangeSet(added: [], deletedExternalIDs: ["hk-weight-001"], nextAnchor: nil), in: db)

        #expect(counts.deleted == 1)

        let store = BodyCompositionMeasurementStore(db: db)
        #expect(try store.latestValue(for: "weight") == nil)
    }

    @Test("Samples without values are not inserted")
    func samplesWithoutValues() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let sample = HealthSample(externalID: "hk-weight-001", domain: .bodyMass,
                                  start: timestamp, end: timestamp, value: nil, unit: "kg")
        let counts = try bridge.apply(HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil), in: db)

        #expect(counts.inserted == 0)
    }
}
