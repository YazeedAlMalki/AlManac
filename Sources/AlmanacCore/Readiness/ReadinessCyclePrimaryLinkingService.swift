import Foundation

/// Closes the gap `ReadinessCycleStore`'s own doc comment flags: given a
/// primary sleep episode that has just been stored
/// (`SleepEpisodeStore.upsert`/`upsertManualWake`, `effectiveType == .primary`),
/// determines its readiness cycle per §7.3/§8.4 — creating or updating the
/// `readiness_cycle` row, closing whichever cycle was open before it, and
/// re-linking wellness logs (via `ReadinessCycleLinkingService`) to both.
///
/// **What this deliberately does not do:** decide *which* episode is
/// primary. §8.2's priority order (user correction, shift-aware, general
/// longest-episode, none) runs earlier, inside `SleepClassifier`, before an
/// episode is ever persisted — by the time a row's `effectiveType` reads
/// `.primary`, that decision has already been made. This is purely the
/// "now that we know which episode is primary, what does that mean for
/// `readiness_cycle` and everything downstream of it" piece.
public struct ReadinessCyclePrimaryLinkingService: @unchecked Sendable {
    let db: Database
    private let timeModel: TimeModel
    private let cycleStore: ReadinessCycleStore
    private let sleepStore: SleepEpisodeStore
    private let linkingService: ReadinessCycleLinkingService

    public init(db: Database, timeModel: TimeModel, clock: any Clock = SystemClock()) {
        self.db = db
        self.timeModel = timeModel
        self.cycleStore = ReadinessCycleStore(db: db, clock: clock)
        self.sleepStore = SleepEpisodeStore(db: db, clock: clock)
        self.linkingService = ReadinessCycleLinkingService(db: db, clock: clock,
                                                            zone: ZoneContext(timeModel.timeZone))
    }

    public struct LinkResult: Sendable, Hashable {
        public let cycleId: Int64
        /// The cycle that was open before this one, if this run closed it.
        public let closedPreviousCycleId: Int64?
    }

    /// Looks up `logicalDay`'s primary episode (§8's own grouping — "a
    /// night plus any naps") and links it. `nil` when that day has no
    /// primary episode at all (§8.2 case 4 — nothing to link yet, e.g. no
    /// sleep data and no manual entry).
    @discardableResult
    public func linkPrimaryEpisode(for logicalDay: String) throws -> LinkResult? {
        // The classifier (SleepClassifier.determinePrimary) guarantees at
        // most one `.primary` per day; `.first` is a defensive fallback for
        // a shape that should not occur, not a real selection rule — see
        // `episodes(for:)`'s own "ordered by start" doc comment for why
        // `.first` is deterministic if it ever did.
        guard let primary = try sleepStore.episodes(for: logicalDay)
            .first(where: { $0.effectiveType == .primary }) else { return nil }
        return try link(primary)
    }

    /// Same, addressing the episode directly by id — convenient right after
    /// `upsert`/`upsertManualWake` hands one back. `nil` when the episode
    /// isn't (or is no longer, after a correction) the primary one.
    @discardableResult
    public func linkPrimaryEpisode(episodeId: Int64) throws -> LinkResult? {
        guard let episode = try sleepStore.episode(id: episodeId), episode.effectiveType == .primary
        else { return nil }
        return try link(episode)
    }

    // MARK: - Private

    private func link(_ episode: StoredSleepEpisode) throws -> LinkResult {
        let wake = episode.end
        // §8.4: "anchorDate = logical day of the wake time" — deliberately
        // recomputed from the wake instant via TimeModel, not reused from
        // `episode.logicalDay` (the night's own logical-day label, which a
        // caller chose when storing the episode and which this service has
        // no way to verify follows the same rule). The spec names the wake
        // time itself as the source of truth for which cycle an episode
        // belongs to.
        let anchorDate = timeModel.logicalDay(wake).value

        // Capture whichever cycle exists for this anchor date, and whichever
        // cycle is open, *before* creating or touching anything below.
        // `openCycle()` orders by id descending — if we asked after
        // `createCycle` ran, a brand-new row for `anchorDate` would already
        // outrank and mask the real previous cycle, and the self-exclusion
        // check below would never even see it. Reading both first avoids
        // that entirely, rather than working around ordering after the fact.
        let existingForAnchor = try cycleStore.cycle(anchorDate: anchorDate)
        let previousOpenCycle = try cycleStore.openCycle().flatMap { candidate in
            candidate.id == existingForAnchor?.id ? nil : candidate
        }

        let cycleId: Int64
        if let existing = existingForAnchor {
            cycleId = existing.id
            try cycleStore.linkPrimaryEpisode(id: cycleId, primarySleepEpisodeId: episode.id,
                                               primaryWakeTimestamp: wake, cycleStartTimestamp: wake)
        } else {
            cycleId = try cycleStore.createCycle(anchorDate: anchorDate, primaryWakeTimestamp: wake,
                                                  cycleStartTimestamp: wake, primarySleepEpisodeId: episode.id)
        }

        // §7.3: the *previous* open cycle's end is this cycle's start.
        // `openCycle()`'s own doc comment already flags "at most one,
        // assumes chronological processing, nothing enforces it at the
        // schema level" — this reuses exactly that assumption rather than
        // inventing a stricter one. Out-of-order backfill (linking an old
        // day's primary sleep after a more recent cycle already exists —
        // `previousStart >= wake`) is deliberately left alone rather than
        // guessed at: flagged here, not silently mishandled.
        var closedPreviousCycleId: Int64? = nil
        if let previous = previousOpenCycle,
           let previousStart = previous.cycleStartTimestamp, previousStart < wake {
            try cycleStore.closeCycle(id: previous.id, cycleEndTimestamp: wake)
            try linkingService.relinkLogsToReadinessCycle(cycleId: previous.id,
                                                           cycleStartTimestamp: previousStart,
                                                           cycleEndTimestamp: wake)
            closedPreviousCycleId = previous.id
        }

        // Re-fetch this cycle's own `cycleEndTimestamp` rather than assume
        // it's still open-ended: reprocessing an already-closed cycle (a
        // correction reached after a later cycle was already linked) must
        // not blow away a real end by relinking as if nothing bounds it.
        // A correction that reaches back far enough to invalidate an
        // *already-processed* next cycle's own boundary is the same class
        // of not-handled edge case as the out-of-order note above.
        let currentEnd = try cycleStore.cycle(id: cycleId)?.cycleEndTimestamp
        try linkingService.relinkLogsToReadinessCycle(cycleId: cycleId, cycleStartTimestamp: wake,
                                                       cycleEndTimestamp: currentEnd)

        return LinkResult(cycleId: cycleId, closedPreviousCycleId: closedPreviousCycleId)
    }
}
