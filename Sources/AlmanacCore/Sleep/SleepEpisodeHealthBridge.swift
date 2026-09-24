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

    public init(db: Database, clock: any Clock = SystemClock(),
                timeModel: TimeModel = TimeModel(timeZone: .current),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.samples = HealthSampleStore(db: db, healthDomain: .sleep, clock: clock, zone: zone)
        self.episodes = SleepEpisodeStore(db: db, clock: clock)
        self.timeModel = timeModel
        self.zone = zone
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
    private func reclassify(_ touched: Set<LogicalDay>, in db: Database) throws {
        guard !touched.isEmpty else { return }
        var days = touched
        for day in touched {
            if let next = timeModel.day(after: day) { days.insert(next) }
        }

        let grouped = SleepClassifier.groupIntoEpisodes(try liveStageSamples(in: db))
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
                try episodes.upsert(episode,
                                     timezoneOffset: zone.offsetMinutes ?? 0,
                                     logicalDay: day.value)
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

    /// Live sleep samples as the classifier wants them. A row whose `unit` is not
    /// a `SleepStage` is not a sleep sample and is skipped rather than guessed
    /// at — the encoding is a contract with `HealthKitProvider`, and a mismatch
    /// should drop a row, not invent a stage for it.
    private func liveStageSamples(in db: Database) throws -> [SleepStageSample] {
        try db.query("""
        SELECT external_id, start_at, end_at, unit, source_name
        FROM health_sample
        WHERE source_system = ? AND domain = 'sleep' AND deleted_at IS NULL
        ORDER BY start_at;
        """, [.text(samples.sourceSystem)]).compactMap { row in
            guard let id = row.string("external_id"),
                  let stageText = row.string("unit"),
                  let stage = SleepStage(rawValue: stageText),
                  let startText = row.string("start_at"),
                  let endText = row.string("end_at"),
                  let start = parse(startText), let end = parse(endText) else { return nil }
            return SleepStageSample(start: start, end: end, stage: stage,
                                    sourceApp: row.string("source_name"),
                                    healthKitUUID: id)
        }
    }

    private func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
