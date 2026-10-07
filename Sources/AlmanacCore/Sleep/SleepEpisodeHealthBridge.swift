import Foundation

/// Turns HealthKit sleep samples into classified `sleep_episode` rows.
///
/// Sleep was the one `HealthDomain` with no writer. `health_sample` had no path
/// into `sleep_episode`, so `SleepClassifier` and `SleepEpisodeStore` both
/// existed fully built and tested with nothing feeding them — the Today
/// dashboard's Sleep row could only ever be filled by hand.
///
/// Two things this deliberately does **not** do, because both were tried and
/// undone (Migration021):
/// - **Persist samples itself.** It composes `HealthSampleStore`, the one tested
///   writer for `health_sample`. A previous `SleepEpisodeHealthBridge`
///   re-implemented that persistence, was a wrong-shaped duplicate, and was
///   deleted rather than fixed.
/// - **Classify one change set into one episode.** Episodes are a property of a
///   *window* of samples — the 30-minute merge rule and primary-sleep selection
///   both need a night's neighbours. A single new stage sample at 03:00 can join
///   an existing episode, split it, or lose primary status to a nap, so every
///   touched day is re-classified from all its live samples.
///
/// The stage travels in `HealthSample.unit` because a HealthKit category sample
/// has no quantity to read; `value` stays nil.
public struct SleepEpisodeHealthBridge: HealthSampleWriting, @unchecked Sendable {
    private let samples: HealthSampleStore
    private let episodes: SleepEpisodeStore
    private let timeModel: TimeModel
    private let zone: ZoneContext
    /// The stage-sample read, shared with `SleepStageBreakdownReader` so the
    /// "a row whose `unit` is not a stage is not a sleep sample" rule has one
    /// home rather than one per reader.
    private let stageSamples: SleepStageSampleStore
    /// §8.4 — the other half of a primary episode landing in storage. This
    /// bridge is the only writer `sleep_episode` has for HealthKit-derived
    /// rows, so it is also the only place that can trigger that half for a
    /// HealthKit sleep close; see this type's own doc comment.
    private let primaryLinking: ReadinessCyclePrimaryLinkingService

    public init(db: Database, clock: any Clock = SystemClock(),
                timeModel: TimeModel = TimeModel(timeZone: .current),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.samples = HealthSampleStore(db: db, healthDomain: .sleep, clock: clock, zone: zone)
        self.stageSamples = SleepStageSampleStore(db: db, sourceSystem: samples.sourceSystem)
        self.episodes = SleepEpisodeStore(db: db, clock: clock)
        self.timeModel = timeModel
        self.zone = zone
        self.primaryLinking = ReadinessCyclePrimaryLinkingService(db: db, timeModel: timeModel, clock: clock)
    }

    @discardableResult
    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        // Which days a withdrawal touches has to be read before the soft delete
        // hides the row's timestamps.
        let days = try affectedDays(changeSet, in: db)
        let counts = try samples.apply(changeSet, in: db)
        try reclassify(days, in: db)
        return counts
    }

    /// The logical days a change set can touch, before the day-after widening
    /// `reclassify` does.
    ///
    /// Both the start and end day of every touched sample: an episode belongs to
    /// the day it *wakes*, so a night starting at 23:00 lands on the next day,
    /// and a sample's own day is only a hint about where its episode ends.
    private func affectedDays(_ changeSet: HealthChangeSet, in db: Database) throws -> Set<LogicalDay> {
        var days: Set<LogicalDay> = []
        for sample in changeSet.added {
            days.insert(timeModel.logicalDay(sample.start))
            days.insert(timeModel.logicalDay(sample.end))
        }
        guard !changeSet.deletedExternalIDs.isEmpty else { return days }
        for externalID in changeSet.deletedExternalIDs {
            let row = try db.query("""
            SELECT start_at, end_at FROM health_sample WHERE source_system = ? AND external_id = ?;
            """, [.text(samples.sourceSystem), .text(externalID)]).first
            guard let startText = row?.string("start_at"), let start = parse(startText) else { continue }
            days.insert(timeModel.logicalDay(start))
            if let endText = row?.string("end_at"), let end = parse(endText) {
                days.insert(timeModel.logicalDay(end))
            }
        }
        return days
    }

    /// `health_sample` stores instants as UTC `...Z` text. Needed only to find
    /// which logical days a withdrawal touches; the stage rows themselves are
    /// read by `SleepStageSampleStore`, which owns that parsing.
    private func parse(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    /// Re-runs §8.1–§8.3 for each touched day and writes the episodes belonging
    /// to it. Grouping happens once and is shared; only primary selection is
    /// per-day, because that is the part anchored to a day.
    ///
    /// Each touched day is widened by the day after it. A change cannot move an
    /// episode's end arbitrarily far — the merge rule chains samples no more than
    /// 30 minutes apart — but it *can* move it from before the 04:00 boundary to
    /// after it, which is exactly the previous day. Withdrawing the 23:00–03:00
    /// stage of a night, for instance, leaves the remaining stages to end at
    /// 07:00, on a day the withdrawn sample never mentioned. ponytail: a day of
    /// widening covers real sleep data; widen further only if a sample chain ever
    /// spans two boundaries.
    ///
    /// A first sync imports every historical night, so this loads all live sleep
    /// samples and re-selects a primary for each of ~1,000 days. Pure and fast
    /// enough at that size; if it ever shows up, narrow the load to the primary's
    /// 26-hour window per day.
    ///
    /// ponytail: `primaryLinking.linkPrimaryEpisode` below runs once per day
    /// that resolves a primary, and `ReadinessCyclePrimaryLinkingService.link`
    /// scans every existing cycle to find chronological neighbours — fine for
    /// one new night, O(days²) across a ~1,000-day first-time backfill. Narrow
    /// it (e.g. skip the call when the day's primary episode id is unchanged
    /// from what is already stored) only if a first HealthKit connect is
    /// measured to be slow.
    private func reclassify(_ touched: Set<LogicalDay>, in db: Database) throws {
        guard !touched.isEmpty else { return }
        var days = touched
        for day in touched {
            if let next = timeModel.day(after: day) { days.insert(next) }
        }

        let grouped = SleepClassifier.groupIntoEpisodes(try stageSamples.allLiveSamples())
        guard !grouped.isEmpty else { return }

        for day in days.sorted() {
            let decision = SleepClassifier.determinePrimary(
                episodes: grouped, anchor: day, timeModel: timeModel)
            let typed = SleepClassifier.assignTypes(episodes: grouped, primary: decision)
            // Only episodes waking on this day are written, and only from this
            // day's own selection — an episode is persisted once, by the day it
            // belongs to, so a neighbouring day's window cannot retype it.
            let mine = typed.filter { timeModel.logicalDay($0.end) == day }
            for episode in mine {
                let id = try episodes.upsert(episode,
                                              timezoneOffset: zone.offsetMinutes ?? 0,
                                              logicalDay: day.value)
                // §8.4: a HealthKit sleep close that classifies as primary is
                // exactly this service's trigger condition — create or update
                // this day's readiness cycle and re-link its wellness logs.
                // Idempotent, so re-classifying an unchanged night is a no-op.
                if episode.type == .primary {
                    try primaryLinking.linkPrimaryEpisode(episodeId: id)
                }
            }
            try retireSuperseded(on: day,
                                 keeping: Set(mine.compactMap { $0.healthKitUUIDs.first }),
                                 in: db)
        }
    }

    /// Drops this day's HealthKit-derived episodes that the fresh classification
    /// did not reproduce.
    ///
    /// An episode is identified by its first sample's UUID, so withdrawing that
    /// one sample re-identifies an otherwise unchanged night. The upsert cannot
    /// see that — the new identity is a different key — and the dashboard sums
    /// every episode on the day, so leaving the old row behind would double the
    /// night. Deleted outright rather than soft-deleted because `sleep_episode`
    /// has no `deletedAt` column and these rows are purely derived from samples
    /// the source has withdrawn. Rows with no `healthKitUUID` are manual entries
    /// and are never touched.
    private func retireSuperseded(on day: LogicalDay, keeping written: Set<String>,
                                  in db: Database) throws {
        let stale = try db.query("""
        SELECT id, healthKitUUID FROM sleep_episode
        WHERE logicalDay = ? AND healthKitUUID IS NOT NULL;
        """, [.text(day.value)]).compactMap { row -> Int64? in
            guard let id = row.int("id"),
                  let uuid = row.string("healthKitUUID"),
                  !written.contains(uuid) else { return nil }
            return id
        }
        for id in stale {
            try db.run("DELETE FROM sleep_episode WHERE id = ?;", [.integer(id)])
        }
    }
}
