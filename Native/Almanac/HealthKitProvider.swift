import Foundation
import HealthKit
import AlmanacCore

/// The one file in this target allowed to `import HealthKit` — see the doc
/// comment on `HealthProvider` in `AlmanacCore`.
///
/// Every `HealthDomain` is mapped here now. The mapping is a 1:1 reading of the
/// domain names the core already fixed (`sleep`, `steps`, `hrv`, …) onto Apple's
/// own identifiers, so the units are the one thing here that is a choice: each
/// is the unit the corresponding bridge's metric map already declares, and the
/// one HealthKit hands out by default for that quantity.
///
/// Water and waist circumference also write manually logged entries.
final class HealthKitProvider: HealthProvider, HealthWriter, @unchecked Sendable {
    private let store = HKHealthStore()

    /// Read side for the quantity domains: type, the unit to read in, and the
    /// label that unit is stored under.
    ///
    /// Two of these are not the obvious identifier, and both matter:
    ///
    /// - `.heartRate` reads HealthKit's **resting** heart rate, not raw heart
    ///   rate. `VitalsRecordHealthBridge` files it under the `rhr` metric and
    ///   `ReadinessModel` reads `latestValue(for: "rhr")` as resting heart rate,
    ///   averaged over 28 days as the readiness baseline. Feeding it every
    ///   instantaneous reading all day would report "120 bpm" after a run and
    ///   make every readiness score wrong — strictly worse than reporting none.
    ///   The cost is that a user with no Apple Watch sees no resting heart rate
    ///   at all, which is the honest answer rather than a fabricated one.
    /// - `.restingEnergy` reads `basalEnergyBurned`, which is all HealthKit
    ///   offers. Basal energy and resting metabolic rate are close but not the
    ///   same measurement; there is no resting-energy type to ask for.
    private static let quantities: [HealthDomain: (type: HKQuantityType, unit: HKUnit, label: String)] = [
        .water: (HKQuantityType(.dietaryWater), .literUnit(with: .milli), "ml"),
        .steps: (HKQuantityType(.stepCount), .count(), "count"),
        .heartRate: (HKQuantityType(.restingHeartRate), .count().unitDivided(by: .minute()), "bpm"),
        .hrv: (HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli), "ms"),
        .activeEnergy: (HKQuantityType(.activeEnergyBurned), .kilocalorie(), "kcal"),
        .restingEnergy: (HKQuantityType(.basalEnergyBurned), .kilocalorie(), "kcal"),
        .bodyMass: (HKQuantityType(.bodyMass), .gramUnit(with: .kilo), "kg"),
        .bodyFatPercentage: (HKQuantityType(.bodyFatPercentage), .percent(), "%"),
        .leanBodyMass: (HKQuantityType(.leanBodyMass), .gramUnit(with: .kilo), "kg"),
        .waistCircumference: (HKQuantityType(.waistCircumference), .meterUnit(with: .centi), "cm"),
    ]

    /// Domains delivered as categories rather than quantities. Sleep is the only
    /// one whose data is a vocabulary rather than a measurement.
    private static let categories: [HealthDomain: HKCategoryType] = [
        .sleep: HKCategoryType(.sleepAnalysis),
    ]

    /// Workouts are neither a quantity nor a category: an `HKWorkout` is its own
    /// sample class, carrying time, activity type and optional totals.
    private static let workout = HKObjectType.workoutType()

    private static func sampleType(for domain: HealthDomain) -> HKSampleType? {
        if domain == .workouts { return workout }
        if let quantity = quantities[domain] { return quantity.type }
        return categories[domain]
    }

    /// The domains this build can read: every case of `HealthDomain`. A
    /// workout maps to exactly one session, claimed or created — see
    /// `WorkoutSessionHealthBridge` — so no case is left out.
    static let readableDomains: [HealthDomain] = HealthDomain.allCases

    func requestAuthorisation(for domains: [HealthDomain]) async throws {
        let read = Set(domains.compactMap(Self.sampleType(for:)))
        guard !read.isEmpty else { return }
        let share = Set<HKSampleType>(domains.filter { $0 == .water || $0 == .waistCircumference }
            .compactMap { Self.quantities[$0]?.type })
        try await store.requestAuthorization(toShare: share, read: read)
    }

    func changes(in domain: HealthDomain, since anchor: [UInt8]?) async throws -> HealthChangeSet {
        guard let type = Self.sampleType(for: domain) else {
            return HealthChangeSet(added: [], deletedExternalIDs: [], nextAnchor: anchor)
        }
        let previousAnchor = anchor.flatMap { bytes -> HKQueryAnchor? in
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: Data(bytes))
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: previousAnchor,
                                              limit: HKObjectQueryNoLimit) { _, samplesOrNil, deletedOrNil, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                // Own exports already have local rows. Filtering also prevents
                // an export deleted locally before sync from being resurrected.
                let added = (samplesOrNil ?? [])
                    .filter { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .compactMap { Self.healthSample($0, domain: domain) }
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

    /// Maps one HealthKit sample into the platform-neutral shape. Quantity
    /// samples carry a value in the domain's unit; a sleep category sample has no
    /// quantity at all, so its stage travels in `unit` — which is exactly what
    /// `SleepEpisodeHealthBridge` reads back. A workout carries neither a unit
    /// nor a value, just its window and its activity.
    private static func healthSample(_ sample: HKSample, domain: HealthDomain) -> HealthSample? {
        if let quantity = sample as? HKQuantitySample, let spec = quantities[domain] {
            return HealthSample(externalID: sample.uuid.uuidString, domain: domain,
                                start: sample.startDate, end: sample.endDate,
                                value: quantity.quantity.doubleValue(for: spec.unit),
                                unit: spec.label,
                                sourceName: sample.sourceRevision.source.name)
        }
        if let category = sample as? HKCategorySample, domain == .sleep,
           let stage = sleepStage(category.value) {
            return HealthSample(externalID: sample.uuid.uuidString, domain: .sleep,
                                start: sample.startDate, end: sample.endDate,
                                value: nil, unit: stage.rawValue,
                                sourceName: sample.sourceRevision.source.name)
        }
        if let workout = sample as? HKWorkout, domain == .workouts {
            // Duration comes from the window, so no value is carried. Totals
            // (energy, distance) are deliberately not mapped: `docs/features/
            // training.md` records that calorie estimation is blocked on an
            // unresolved MET/licensing question, and a raw total would invite
            // exactly the inference that is blocked.
            return HealthSample(externalID: workout.uuid.uuidString, domain: .workouts,
                                start: workout.startDate, end: workout.endDate,
                                value: nil, unit: nil,
                                sourceName: workout.sourceRevision.source.name,
                                activity: activityIdentifier(workout.workoutActivityType))
        }
        return nil
    }

    /// `HKWorkoutActivityType.running` → `"running"`.
    ///
    /// `rawValue` is an `NSUInteger` enum index, which is stable but means
    /// nothing to a reader, so the case name is used instead. Safe because the
    /// identifier only ever becomes a *display label* in
    /// `workoutSession.sessionType` — a workout is identified by its UUID, never
    /// by its activity — so a change in how Swift reflects the case could at
    /// worst alter a label, never a stored link.
    private static func activityIdentifier(_ type: HKWorkoutActivityType) -> String {
        String(describing: type)
    }

    /// Apple's sleep vocabulary → Almanac's `SleepStage`.
    ///
    /// `asleepUnspecified` becomes core: it is sleep of unknown depth, and core
    /// is the stage that is always present in a night, so it cannot distort the
    /// deep/REM weighting the readiness score relies on. A value outside the
    /// known set is dropped rather than guessed at — inventing a stage would
    /// write a stage the source never claimed.
    private static func sleepStage(_ value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .asleepUnspecified, .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        case .awake: return .awake
        default: return nil
        }
    }

    func write(_ sample: HealthSample) async throws -> String {
        guard sample.domain == .water || sample.domain == .waistCircumference,
              let spec = Self.quantities[sample.domain], let value = sample.value,
              value.isFinite, value > 0, sample.unit == spec.label else { throw HealthProviderError.unavailable }
        let quantity = HKQuantity(unit: spec.unit, doubleValue: value)
        // Retrying a waist write after interruption must not create a second Health sample.
        let metadata: [String: Any]? = sample.domain == .waistCircumference
            ? [HKMetadataKeySyncIdentifier: sample.externalID, HKMetadataKeySyncVersion: 1] : nil
        let hkSample = HKQuantitySample(type: spec.type, quantity: quantity,
                                        start: sample.start, end: sample.end, metadata: metadata)
        try await store.save(hkSample)
        if sample.domain == .waistCircumference {
            // An equal-version retry can be ignored by HealthKit. Return the
            // stored sample's UUID, not the fresh UUID of the ignored object.
            return try await storedWaistIdentifier(syncIdentifier: sample.externalID, type: spec.type)
        }
        return hkSample.uuid.uuidString
    }

    private func storedWaistIdentifier(syncIdentifier: String, type: HKQuantityType) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                        allowedValues: [syncIdentifier])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) {
                _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else if let id = samples?.first?.uuid.uuidString { continuation.resume(returning: id) }
                else { continuation.resume(throwing: HealthProviderError.unavailable) }
            }
            store.execute(query)
        }
    }
}
