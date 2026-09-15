import Foundation
import HealthKit
import AlmanacCore

/// The one file in this target allowed to `import HealthKit` — see the doc
/// comment on `HealthProvider` in `AlmanacCore`.
///
/// Only `.water` is wired up. Every other `HealthDomain` case predates this
/// file and has no HKQuantityType/HKCategoryType mapping defined here — per
/// `HealthDomain`'s own doc comment, that mapping is not guessed.
final class HealthKitProvider: HealthProvider, HealthWriter, @unchecked Sendable {
    private let store = HKHealthStore()
    private let waterType = HKQuantityType(.dietaryWater)
    private let millilitersUnit = HKUnit.literUnit(with: .milli)

    func requestAuthorisation(for domains: [HealthDomain]) async throws {
        guard domains.contains(.water) else { return }
        try await store.requestAuthorization(toShare: [waterType], read: [waterType])
    }

    func changes(in domain: HealthDomain, since anchor: [UInt8]?) async throws -> HealthChangeSet {
        guard domain == .water else {
            return HealthChangeSet(added: [], deletedExternalIDs: [], nextAnchor: anchor)
        }
        let previousAnchor = anchor.flatMap { bytes -> HKQueryAnchor? in
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: Data(bytes))
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: waterType, predicate: nil, anchor: previousAnchor,
                                              limit: HKObjectQueryNoLimit) { [millilitersUnit] _, samplesOrNil, deletedOrNil, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                // Filter out this app's own writes — otherwise a manual entry
                // pushed out by HydrationWriteback would echo straight back
                // in as a new inbound row.
                let added = (samplesOrNil as? [HKQuantitySample] ?? [])
                    .filter { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .map { sample in
                        HealthSample(externalID: sample.uuid.uuidString, domain: .water,
                                     start: sample.startDate, end: sample.endDate,
                                     value: sample.quantity.doubleValue(for: millilitersUnit),
                                     unit: "ml", sourceName: sample.sourceRevision.source.name)
                    }
                let deletedIDs = (deletedOrNil ?? []).map { $0.uuid.uuidString }
                let nextAnchorBytes = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }.map { [UInt8]($0) }
                continuation.resume(returning: HealthChangeSet(
                    added: added, deletedExternalIDs: deletedIDs, nextAnchor: nextAnchorBytes))
            }
            store.execute(query)
        }
    }

    func write(_ sample: HealthSample) async throws -> String {
        let quantity = HKQuantity(unit: millilitersUnit, doubleValue: sample.value ?? 0)
        let hkSample = HKQuantitySample(type: waterType, quantity: quantity,
                                        start: sample.start, end: sample.end)
        try await store.save(hkSample)
        return hkSample.uuid.uuidString
    }
}
