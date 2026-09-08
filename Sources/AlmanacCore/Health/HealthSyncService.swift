import Foundation

public struct SyncOutcome: Sendable, Hashable {
    public let counts: HealthApplyCounts
    public let advancedTo: [UInt8]?
}

/// One incremental sync, with the property that matters: **the imported rows
/// and the cursor advance commit together.**
///
/// The read from the provider happens outside the transaction; only the write
/// is inside it. If the write throws, the transaction rolls back and the anchor
/// keeps its previous value, so the next run re-reads the same range. An anchor
/// that advanced past rows that were never persisted would skip them for good.
public struct HealthSyncService: Sendable {
    private let db: Database
    private let provider: any HealthProvider
    private let anchors: SyncAnchorStore
    private let writer: any HealthSampleWriting
    private let healthDomain: HealthDomain
    private let anchorKey: String

    public init(db: Database, provider: any HealthProvider, writer: any HealthSampleWriting,
                healthDomain: HealthDomain = .bodyMass, clock: any Clock = SystemClock(),
                anchorKey: String? = nil) {
        self.db = db
        self.provider = provider
        self.writer = writer
        self.healthDomain = healthDomain
        self.anchors = SyncAnchorStore(db: db, clock: clock)
        self.anchorKey = anchorKey ?? healthDomain.rawValue
    }

    public func currentAnchor() throws -> [UInt8]? {
        try anchors.load(anchorKey)?.token
    }

    @discardableResult
    public func syncOnce() async throws -> SyncOutcome {
        let previous = try anchors.load(anchorKey)?.token
        let changeSet = try await provider.changes(in: healthDomain, since: previous)
        do {
            return try db.transaction {
                let counts = try writer.apply(changeSet, in: db)
                try anchors.save(domain: anchorKey, token: changeSet.nextAnchor)
                return SyncOutcome(counts: counts, advancedTo: changeSet.nextAnchor)
            }
        } catch {
            // The rows and the advance both rolled back. Record why, without
            // clearing the last good anchor.
            try? anchors.recordFailure(domain: anchorKey, message: String(describing: error))
            throw error
        }
    }
}
