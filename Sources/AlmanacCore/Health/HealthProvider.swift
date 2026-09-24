import Foundation

/// The seam where HealthKit will sit.
///
/// HealthKit does not exist on Linux, so it cannot be imported by this target
/// at all. That constraint is useful rather than annoying: it forces the sync
/// algorithm to be written against a protocol and tested against a fake, and
/// keeps `HKHealthStore` confined to one iOS-only file in the app target.
///
/// The concrete `HealthKitProvider` belongs in the iOS target and is the only
/// place `import HealthKit` may appear.
public protocol HealthProvider: Sendable {
    func requestAuthorisation(for domains: [HealthDomain]) async throws
    /// Returns samples changed since `anchor`, plus the anchor to store next.
    func changes(in domain: HealthDomain, since anchor: [UInt8]?) async throws -> HealthChangeSet
}

/// Domains Almanac syncs. Names are Almanac's, not HealthKit's — the mapping
/// to HKQuantityType/HKCategoryType lives in the iOS adapter, per the spec's
/// HealthKit map (which is not available here and must not be guessed).
///
/// `.water` is the first domain Almanac also *originates* rather than only
/// reading — see `HealthWriter` below.
public enum HealthDomain: String, Codable, Sendable, CaseIterable, Hashable {
    case sleep, workouts, activeEnergy, restingEnergy, steps, heartRate, hrv, bodyMass, water
    case bodyFatPercentage, leanBodyMass
}

public struct HealthSample: Sendable, Hashable {
    public let externalID: String
    public let domain: HealthDomain
    public let start: Date
    public let end: Date
    public let value: Double?
    public let unit: String?
    public let sourceName: String?
    /// The platform's activity identifier, for workout samples only —
    /// `"running"`, `"traditionalStrengthTraining"`, and so on.
    ///
    /// Deliberately an opaque string rather than a cross-platform enum. This is
    /// the one platform-neutral type any HealthKit sync passes through, and
    /// `AlmanacCore` cannot import HealthKit, so an enum here could only ever
    /// mirror HealthKit's own list — about eighty values whose spelling Apple
    /// controls. Carrying the identifier and *deciding* what it means in core
    /// keeps the mapping testable on Linux and keeps an unrecognised activity
    /// from failing to decode: `WorkoutActivity` turns one into a label, with a
    /// fallback, rather than the sample being dropped.
    public let activity: String?

    public init(externalID: String, domain: HealthDomain, start: Date, end: Date,
                value: Double?, unit: String?, sourceName: String? = nil,
                activity: String? = nil) {
        self.externalID = externalID
        self.domain = domain
        self.start = start
        self.end = end
        self.value = value
        self.unit = unit
        self.sourceName = sourceName
        self.activity = activity
    }
}

public struct HealthChangeSet: Sendable {
    public let added: [HealthSample]
    public let deletedExternalIDs: [String]
    public let nextAnchor: [UInt8]?

    public init(added: [HealthSample], deletedExternalIDs: [String], nextAnchor: [UInt8]?) {
        self.added = added
        self.deletedExternalIDs = deletedExternalIDs
        self.nextAnchor = nextAnchor
    }
}

public enum HealthProviderError: Error, Sendable {
    case authorisationDenied(HealthDomain)
    case unavailable
}

/// The write half of the HealthKit seam.
///
/// Kept separate from `HealthProvider` because every other domain here is a
/// read-only sync from HealthKit; hydration is the first domain Almanac also
/// originates and needs to push back out. The concrete adapter is the same
/// iOS-only file that implements `HealthProvider` — this protocol does not
/// widen where `import HealthKit` may appear.
public protocol HealthWriter: Sendable {
    /// Writes a sample and returns the identifier HealthKit assigned it.
    func write(_ sample: HealthSample) async throws -> String
}

/// In-memory writer used by tests and by any non-iOS host.
public final class FakeHealthWriter: HealthWriter, @unchecked Sendable {
    public struct WriteFailure: Error, Sendable {}

    private let lock = NSLock()
    private var _written: [HealthSample] = []
    public var written: [HealthSample] {
        lock.lock(); defer { lock.unlock() }
        return _written
    }
    /// When set, `write(_:)` throws instead of recording — for exercising
    /// "a failed push leaves the row pending" behaviour.
    public var shouldFail = false
    public var nextID: @Sendable () -> String = { UUID().uuidString }

    public init() {}

    public func write(_ sample: HealthSample) async throws -> String {
        try record(sample)
    }

    // The lock is taken only in this synchronous helper, never held across
    // a suspension — same discipline as FakeHealthProvider below.
    private func record(_ sample: HealthSample) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if shouldFail { throw WriteFailure() }
        _written.append(sample)
        return nextID()
    }
}

/// In-memory provider used by tests and by any non-iOS host.
public final class FakeHealthProvider: HealthProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [HealthDomain: [HealthChangeSet]] = [:]
    public private(set) var authorisedDomains: Set<HealthDomain> = []

    public init() {}

    public func enqueue(_ set: HealthChangeSet, for domain: HealthDomain) {
        lock.lock(); defer { lock.unlock() }
        batches[domain, default: []].append(set)
    }

    public func requestAuthorisation(for domains: [HealthDomain]) async throws {
        authorise(domains)
    }

    public func changes(in domain: HealthDomain, since anchor: [UInt8]?) async throws -> HealthChangeSet {
        try nextChangeSet(domain, anchor)
    }

    // Locks are taken only in synchronous helpers, never held across a suspension.
    private func authorise(_ domains: [HealthDomain]) {
        lock.lock(); defer { lock.unlock() }
        authorisedDomains.formUnion(domains)
    }

    private func nextChangeSet(_ domain: HealthDomain, _ anchor: [UInt8]?) throws -> HealthChangeSet {
        lock.lock(); defer { lock.unlock() }
        guard authorisedDomains.contains(domain) else {
            throw HealthProviderError.authorisationDenied(domain)
        }
        guard var queue = batches[domain], !queue.isEmpty else {
            return HealthChangeSet(added: [], deletedExternalIDs: [], nextAnchor: anchor)
        }
        let next = queue.removeFirst()
        batches[domain] = queue
        return next
    }
}
