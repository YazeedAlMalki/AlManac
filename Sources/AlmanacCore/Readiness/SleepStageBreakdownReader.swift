import Foundation

/// Turns one sleep episode's stage samples into the §9.2 breakdown that
/// `ReadinessFormula.sleepQualityScore` scores.
///
/// **Why this type exists.** §9.1 gives sleep quality a 20% weight, and §9.2
/// says "if no stage data → 50, flagged as missing". The 50 was reached every
/// single time, not because stage data was missing but because nothing ever
/// read it: `ReadinessModel.refresh()` built `ReadinessInputs` without the
/// `stages` field, so the input was permanently absent and a fifth of every
/// readiness score was a constant the app presented with the same confidence as
/// the four-fifths it had measured. The samples were never missing — they are in
/// `health_sample` and `SleepClassifier` had been reading them since the sleep
/// bridge landed. Only the path from there to the readiness input was absent.
///
/// ## The two decisions §9.2 leaves open
///
/// **The denominator is the episode's span, not its asleep time.** §9.2 writes
/// `deepPct`/`remPct`/`corePct` without saying "percent of what", and
/// `SleepStageBreakdown`'s own doc comment already fixed it — "fractions of the
/// episode (0...1)" — so this follows that rather than inventing a second
/// reading. It is the reading that makes awake time cost something: the same two
/// hours of deep sleep scores higher in a four-hour episode than in an
/// eight-hour one. Summed asleep time as the denominator would make the score
/// blind to exactly the fragmentation a stage breakdown exists to detect.
///
/// **Samples are clipped to the window before they are counted.** A stage that
/// overhangs the episode contributes only its overlap, so fractions cannot
/// exceed 1.0 from a sample that runs long.
///
/// ## What is not here
///
/// No baseline, no score, no window beyond the episode's own: the job is to
/// answer "what were the stages", and `ReadinessFormula` answers "what is that
/// worth". A per-day or per-cycle aggregate belongs to the caller, which
/// already knows which episode it means.
public struct SleepStageBreakdownReader: @unchecked Sendable {

    let db: Database
    private let samples: SleepStageSampleStore

    public init(db: Database, sourceSystem: String = "healthkit") {
        self.db = db
        self.samples = SleepStageSampleStore(db: db, sourceSystem: sourceSystem)
    }

    /// The stage split of `episode`, or nil when its window holds no asleep
    /// stage samples.
    ///
    /// Nil is the honest answer in three distinct cases, all of which §9.2
    /// routes to "50, flagged as missing" rather than to a score: a manual
    /// episode (no HealthKit samples at all), a device that reports only
    /// `inBed`/`awake`, and a night the app has not synced yet. None of them is
    /// evidence of bad sleep, so none of them may become a number.
    public func breakdown(forEpisode episode: StoredSleepEpisode) throws -> SleepStageBreakdown? {
        let span = episode.end.timeIntervalSince(episode.start)
        guard span > 0 else { return nil }

        var deep: TimeInterval = 0
        var rem: TimeInterval = 0
        var core: TimeInterval = 0

        for sample in try samples.samples(from: episode.start, to: episode.end) {
            // `inBed` is bed occupancy, not sleep: on a device that emits both it
            // spans the whole night and would count every stage twice.
            guard sample.stage.isAsleep else { continue }

            let clippedStart = max(sample.start, episode.start)
            let clippedEnd = min(sample.end, episode.end)
            guard clippedEnd > clippedStart else { continue }
            let seconds = clippedEnd.timeIntervalSince(clippedStart)

            switch sample.stage {
            case .asleepDeep: deep += seconds
            case .asleepREM: rem += seconds
            case .asleepCore: core += seconds
            case .inBed, .awake: break
            }
        }

        // No asleep stage in the window is *no data*, not a night of zero
        // quality. A breakdown of three zeros would score 0 and tell the user
        // they slept terribly on a night the app never observed — the exact
        // substitution R-RDY forbids, reached by the opposite route.
        guard deep + rem + core > 0 else { return nil }

        return SleepStageBreakdown(
            deep: Swift.min(1, deep / span),
            rem: Swift.min(1, rem / span),
            core: Swift.min(1, core / span))
    }
}
