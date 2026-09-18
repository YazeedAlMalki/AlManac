import Foundation

/// Closes the gap `ReadinessCycleStore`'s own doc comment flags: given a
/// primary sleep episode that has just been stored
/// (`SleepEpisodeStore.upsert`/`upsertManualWake`, `effectiveType == .primary`),
/// determines its readiness cycle per §7.3/§8.4 — creating or updating the
/// `readiness_cycle` row, fixing up whichever cycles are chronologically
/// adjacent to it, computing and attaching its circadian context (§13), and
/// re-linking wellness logs (via `ReadinessCycleLinkingService`) to
/// everything that changed.
///
/// **What this deliberately does not do:** decide *which* episode is
/// primary. §8.2's priority order (user correction, shift-aware, general
/// longest-episode, none) runs earlier, inside `SleepClassifier`, before an
/// episode is ever persisted — by the time a row's `effectiveType` reads
/// `.primary`, that decision has already been made. This is purely the
/// "now that we know which episode is primary, what does that mean for
/// `readiness_cycle` and everything downstream of it" piece.
///
/// It also does not repair a correction that reorders a cycle across more
/// than one existing neighbor in a single move (e.g. moving a wake time so
/// far that it jumps past two other cycles at once, not just the one
/// immediately beside it) — `link` below only ever touches the cycle being
/// linked and its two immediate chronological neighbors, which is enough
/// for out-of-order backfill and for a correction that reaches back past an
/// already-closed boundary (see `link`'s own comment), but a multi-hop
/// reorder would need to walk every affected cycle's own neighbors in turn.
/// Nothing in this repo produces that shape of correction yet, so it is
/// flagged rather than built.
public struct ReadinessCyclePrimaryLinkingService: @unchecked Sendable {
    let db: Database
    private let timeModel: TimeModel
    private let cycleStore: ReadinessCycleStore
    private let sleepStore: SleepEpisodeStore
    private let shiftStore: ShiftScheduleStore
    private let circadianContextStore: CircadianContextStore
    private let linkingService: ReadinessCycleLinkingService

    public init(db: Database, timeModel: TimeModel, clock: any Clock = SystemClock()) {
        self.db = db
        self.timeModel = timeModel
        self.cycleStore = ReadinessCycleStore(db: db, clock: clock)
        self.sleepStore = SleepEpisodeStore(db: db, clock: clock)
        self.shiftStore = ShiftScheduleStore(db: db)
        self.circadianContextStore = CircadianContextStore(db: db, clock: clock)
        self.linkingService = ReadinessCycleLinkingService(db: db, clock: clock,
                                                            zone: ZoneContext(timeModel.timeZone))
    }

    public struct LinkResult: Sendable, Hashable {
        public let cycleId: Int64
        /// The cycle immediately before this one chronologically, if any —
        /// regardless of whether this run actually changed its end (a
        /// reprocess that finds nothing to correct still reports it, since
        /// the name is "the previous cycle", not "a cycle this run closed
        /// for the first time").
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
        let circadianContextId = try linkCircadianContext(anchor: LogicalDay(anchorDate))

        let existingForAnchor = try cycleStore.cycle(anchorDate: anchorDate)
        let cycleId: Int64
        if let existing = existingForAnchor {
            cycleId = existing.id
            try cycleStore.linkPrimaryEpisode(id: cycleId, primarySleepEpisodeId: episode.id,
                                               primaryWakeTimestamp: wake, cycleStartTimestamp: wake,
                                               circadianContextId: circadianContextId)
        } else {
            cycleId = try cycleStore.createCycle(anchorDate: anchorDate, primaryWakeTimestamp: wake,
                                                  cycleStartTimestamp: wake, primarySleepEpisodeId: episode.id,
                                                  circadianContextId: circadianContextId)
        }

        // This cycle's true chronological neighbors, re-derived fresh from
        // every OTHER cycle's own `cycleStartTimestamp` rather than assumed
        // from "whichever cycle happens to be open" — that assumption is
        // what let out-of-order backfill (processing an earlier night after
        // a later one already exists) and reach-back corrections (moving
        // this wake time earlier or later than it used to be, including
        // past an already-closed neighbor's boundary) corrupt a cycle's
        // boundaries before. Bare cycles with no `cycleStartTimestamp` yet
        // (`ensureCycle`, primary sleep not classified) sort as neither a
        // predecessor nor a successor of anything, since their true
        // position in time isn't known yet.
        let others = try cycleStore.allCycles().filter { $0.id != cycleId }

        var closedPreviousCycleId: Int64? = nil
        if let predecessor = others
            .filter({ ($0.cycleStartTimestamp ?? .distantFuture) < wake })
            .max(by: { ($0.cycleStartTimestamp ?? .distantPast) < ($1.cycleStartTimestamp ?? .distantPast) }) {
            try cycleStore.closeCycle(id: predecessor.id, cycleEndTimestamp: wake)
            if let predecessorStart = predecessor.cycleStartTimestamp {
                try linkingService.relinkLogsToReadinessCycle(cycleId: predecessor.id,
                                                               cycleStartTimestamp: predecessorStart,
                                                               cycleEndTimestamp: wake)
            }
            closedPreviousCycleId = predecessor.id
        }

        // This cycle's own end is its successor's start — or nil (open) if
        // there is no successor yet. Always written, not just when a
        // successor exists, so a correction that removes what used to be
        // this cycle's successor correctly reopens it again rather than
        // leaving a stale end behind.
        let successor = others
            .filter({ ($0.cycleStartTimestamp ?? .distantPast) > wake })
            .min(by: { ($0.cycleStartTimestamp ?? .distantFuture) < ($1.cycleStartTimestamp ?? .distantFuture) })
        try cycleStore.closeCycle(id: cycleId, cycleEndTimestamp: successor?.cycleStartTimestamp)
        try linkingService.relinkLogsToReadinessCycle(cycleId: cycleId, cycleStartTimestamp: wake,
                                                       cycleEndTimestamp: successor?.cycleStartTimestamp)

        return LinkResult(cycleId: cycleId, closedPreviousCycleId: closedPreviousCycleId)
    }

    /// §13 — recomputes and persists the circadian context for `anchor`,
    /// returning its row id to attach to the cycle. Runs on every link, not
    /// just brand-new cycles: a corrected primary episode can land on a
    /// different anchor date than before, or a later-arriving shift entry
    /// can change what an already-processed date's context should have
    /// been, and `CircadianContextStore.upsert` replaces one row per date
    /// regardless of how many times this runs.
    ///
    /// History is built by walking backward day by day through
    /// `ShiftScheduleStore.occurrence(for:)` rather than a single ranged
    /// query — that store has no such query, and the lookback here is small
    /// and bounded (`stableRunDays + transitionWindowDays`, plus two days of
    /// margin), so one query per day is not a real cost. A day with no
    /// occurrence at all is simply absent from `history`, exactly like
    /// `CircadianContextEngine.determine`'s own "a missing day ends a run"
    /// contract expects.
    private func linkCircadianContext(anchor: LogicalDay) throws -> Int64 {
        var history: [LogicalDay: ShiftType] = [:]
        var day: LogicalDay? = anchor
        let lookbackDays = CircadianContextEngine.stableRunDays + CircadianContextEngine.transitionWindowDays + 2
        for _ in 0..<lookbackDays {
            guard let d = day else { break }
            if let occurrence = try shiftStore.occurrence(for: d.value) {
                history[d] = occurrence.shiftType
            }
            day = timeModel.day(before: d)
        }
        let context = CircadianContextEngine.determine(anchor: anchor, history: history, timeModel: timeModel)
        return try circadianContextStore.upsert(context)
    }
}
