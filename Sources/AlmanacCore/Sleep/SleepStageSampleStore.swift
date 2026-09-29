import Foundation

/// Reads the sleep **stage** samples out of `health_sample`, and nothing else.
///
/// This exists because two callers needed the same read and the only version of
/// it was `private` to `SleepEpisodeHealthBridge`:
///
/// - `SleepEpisodeHealthBridge.reclassify` loads every live sample to re-run
///   §8.1–§8.3.
/// - `SleepStageBreakdownReader` loads one episode's window to produce §9.2's
///   sleep-quality input.
///
/// The alternative — a second, windowed copy of the query inside the reader —
/// is the wrong-shaped duplicate this repo has already built and deleted once.
/// The `unit`-is-a-stage contract in particular is a contract *with*
/// `HealthKitProvider`, and two readers of it are two places to disagree about
/// what to do with a row that breaks it.
///
/// **Deliberately a reader, not a writer.** `HealthSampleStore` owns persistence
/// for `health_sample` and is the only thing that writes to it; this type
/// composes nothing and mutates nothing.
public struct SleepStageSampleStore: @unchecked Sendable {

    let db: Database
    /// The source whose samples are read. Matches `HealthSampleStore`'s, so an
    /// episode classified from one source is described from the same one.
    public let sourceSystem: String

    public init(db: Database, sourceSystem: String = "healthkit") {
        self.db = db
        self.sourceSystem = sourceSystem
    }

    /// Every live stage sample overlapping the half-open window `from..<to`,
    /// ordered by start.
    ///
    /// Half-open, and matched as an overlap (`start_at < to AND end_at > from`),
    /// because a sleep stage routinely straddles a boundary — the first stage of
    /// a night starts before midnight — and an episode's own window is what is
    /// being asked about, not which day a sample's start time rounds to.
    public func samples(from: Date, to: Date) throws -> [SleepStageSample] {
        let iso = ISO8601DateFormatter()
        return try liveSamples(
            where: "AND start_at < ? AND end_at > ?",
            bindings: [.text(iso.string(from: to)), .text(iso.string(from: from))])
    }

    /// Every live stage sample, ordered by start. What re-classification needs:
    /// episodes are a property of a *window* of samples (§8.1's 30-minute merge
    /// rule chains them), so classifying one day correctly needs its neighbours.
    public func allLiveSamples() throws -> [SleepStageSample] {
        try liveSamples(where: "", bindings: [])
    }

    // MARK: - Private

    private func liveSamples(where clause: String, bindings: [SQLValue]) throws -> [SleepStageSample] {
        // Normalised to UTC before it reaches SQL. `start_at` is stored as a UTC
        // `...Z` string, so comparing it lexically against a local-offset text
        // would be wrong by the offset — and silently so.
        let rows = try db.query("""
        SELECT external_id, start_at, end_at, unit, source_name
        FROM health_sample
        WHERE source_system = ? AND domain = 'sleep' AND deleted_at IS NULL
        \(clause)
        ORDER BY start_at;
        """, [.text(sourceSystem)] + bindings)

        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            // A row whose `unit` is not a `SleepStage` is not a sleep sample and
            // is skipped rather than guessed at — the encoding is a contract
            // with `HealthKitProvider`, and a mismatch should drop a row, not
            // invent a stage for it.
            guard let id = row.string("external_id"),
                  let stageText = row.string("unit"),
                  let stage = SleepStage(rawValue: stageText),
                  let startText = row.string("start_at"),
                  let endText = row.string("end_at"),
                  let start = iso.date(from: startText),
                  let end = iso.date(from: endText) else { return nil }
            return SleepStageSample(start: start, end: end, stage: stage,
                                    sourceApp: row.string("source_name"),
                                    healthKitUUID: id)
        }
    }
}
