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
public enum HealthDomain: String, Codable, Sendable, CaseIterable, Hashable {
    case sleep, workouts, activeEnergy, restingEnergy, steps, heartRate, hrv, bodyMass
}

public struct HealthSample: Sendable, Hashable {
    public let externalID: String
    public let domain: HealthDomain
    public let start: Date
    public let end: Date
    public let value: Double?
    public let unit: String?
    public let sourceName: String?

    public init(externalID: String, domain: HealthDomain, start: Date, end: Date,
                value: Double?, unit: String?, sourceName: String? = nil) {
        self.externalID = externalID
        self.domain = domain
        self.start = start
        self.end = end
        self.value = value
        self.unit = unit
        self.sourceName = sourceName
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
