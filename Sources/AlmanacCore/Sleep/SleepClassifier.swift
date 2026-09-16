import Foundation

/// Turns raw HealthKit sleep samples into classified episodes, and picks the
/// primary one. Technical Specification v1.0 §8.
///
/// Pure and synchronous on purpose: every rule here is a decision about data
/// the caller already holds, so the whole of §8 is testable without a database,
/// without HealthKit, and on Linux. Persistence is the caller's job.
///
/// The one rule this type does **not** implement is §8.4 readiness-cycle
/// linking, which writes to two tables and therefore belongs in a store.
public enum SleepClassifier {

    /// §8.1 — consecutive samples with a gap of this many minutes or less merge
    /// into one episode. A longer gap starts a new one.
    public static let episodeGapMinutes: Double = 30

    /// §8.2 — the shortest episode that can be chosen as primary by the
    /// duration-based rules.
    public static let minimumPrimaryMinutes: Int = 120

    /// §8.2 — an episode starting within this long of a shift ending is sleep
    /// *caused by* that shift, so it is `post_shift` rather than `nap`.
    public static let postShiftWindowMinutes: Double = 90

    /// §8.3 — at or above this, a non-primary episode is a `split`; below it, a `nap`.
    public static let splitThresholdMinutes: Int = 90

    /// §8.2 step 3a — width of the window the general algorithm searches.
    public static let generalWindowHours: Double = 26

    // MARK: - §8.1 Episode detection

    /// Groups samples into episodes, merging any two whose gap is ≤ 30 minutes.
    ///
    /// Samples are sorted by start before grouping, so the caller may hand them
    /// over in any order. Overlapping samples (two apps describing the same
    /// night) are merged into the same episode rather than producing two — the
    /// choice of *which* source describes it is made by `preferredSource`,
    /// not by pretending the user slept twice.
    ///
    /// Every episode comes back `.nap`; nothing here knows which is primary.
    /// That is `determinePrimary`'s decision, and running it is what makes the
    /// types meaningful.
    public static func groupIntoEpisodes(_ samples: [SleepStageSample]) -> [SleepEpisode] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.start < $1.start }
        let gap = episodeGapMinutes * 60

        var groups: [[SleepStageSample]] = []
        var current: [SleepStageSample] = [sorted[0]]
        var currentEnd = sorted[0].end

        for sample in sorted.dropFirst() {
            // Measured against the running end of the group, not the previous
            // sample's end: a short sample fully inside a long one must not
            // look like a 6-hour gap to whatever follows it.
            if sample.start.timeIntervalSince(currentEnd) <= gap {
                current.append(sample)
                currentEnd = max(currentEnd, sample.end)
            } else {
                groups.append(current)
                current = [sample]
                currentEnd = sample.end
            }
        }
        groups.append(current)

        return groups.map { group in
            let start = group.map(\.start).min()!
            let end = group.map(\.end).max()!
            let winner = preferredSource(in: group)
            return SleepEpisode(
                start: start,
                end: end,
                type: .nap,
                source: .healthkit,
                asleepMinutes: asleepMinutes(of: group, from: winner),
                sourceApp: winner,
                sourceDevice: group.first(where: { $0.sourceApp == winner })?.sourceDevice,
                healthKitUUIDs: group.compactMap(\.healthKitUUID)
            )
        }
    }

    /// §8.5 — which app's samples describe an episode for summary purposes.
    ///
    /// Priority: Apple Watch native, then the third-party app with the longest
    /// continuous coverage, then anything else. Losing samples are not
    /// discarded by this type — the caller keeps them with their provenance —
    /// they simply do not contribute duration, because overlapping sources
    /// must never sum.
    public static func preferredSource(in samples: [SleepStageSample]) -> String? {
        let apple = samples.first { sample in
            guard let app = sample.sourceApp?.lowercased() else { return false }
            return app.contains("com.apple.health") || app.contains("apple watch")
        }
        if let apple { return apple.sourceApp }

        var coverage: [String: TimeInterval] = [:]
        for sample in samples {
            guard let app = sample.sourceApp else { continue }
            coverage[app, default: 0] += sample.duration
        }
        // Ties broken by name so the choice is deterministic across runs —
        // an episode that changed its mind between two syncs would look to
        // the user like their sleep data was being rewritten.
        return coverage.max { a, b in
            a.value == b.value ? a.key > b.key : a.value < b.value
        }?.key
    }

    /// Minutes actually asleep, counting only the designated source's samples
    /// and merging their overlaps so nothing is counted twice.
    static func asleepMinutes(of samples: [SleepStageSample], from source: String?) -> Int {
        let relevant = samples.filter {
            $0.stage.isAsleep && (source == nil || $0.sourceApp == source || $0.sourceApp == nil)
        }
        guard !relevant.isEmpty else { return 0 }

        var total: TimeInterval = 0
        var cursor = Date.distantPast
        for sample in relevant.sorted(by: { $0.start < $1.start }) {
            let from = max(sample.start, cursor)
            guard sample.end > from else { continue }
            total += sample.end.timeIntervalSince(from)
            cursor = sample.end
        }
        return Int((total / 60).rounded())
    }

    // MARK: - §8.2 Primary sleep determination

    public struct PrimaryDecision: Sendable, Hashable {
        /// Index into the episodes array. Nil when no episode qualifies —
        /// §8.2 step 4, where readiness waits for the user instead.
        public let primaryIndex: Int?
        /// Which rule decided, for the audit trail and for tests.
        public let rule: Rule

        public enum Rule: String, Sendable, Hashable {
            case userCorrection = "user_correction"
            case shiftAware = "shift_aware"
            case general = "general"
            case postShift = "post_shift"
            case none = "none"
        }
    }

    /// Picks the primary episode in the strict priority order of §8.2.
    ///
    /// `anchor` is the logical day being evaluated; `timeModel` supplies the
    /// 04:00 boundary. `shift` is the shift context for that day, when the user
    /// keeps a schedule.
    public static func determinePrimary(
        episodes: [SleepEpisode],
        anchor: LogicalDay,
        timeModel: TimeModel,
        shift: ShiftContext? = nil
    ) -> PrimaryDecision {
        guard !episodes.isEmpty else { return PrimaryDecision(primaryIndex: nil, rule: .none) }

        // 1. User correction — honoured unconditionally, before any algorithm runs.
        if let i = episodes.firstIndex(where: { $0.userCorrectedType == .primary }) {
            return PrimaryDecision(primaryIndex: i, rule: .userCorrection)
        }

        let onDay = episodes.indices.filter {
            timeModel.logicalDay(episodes[$0].end) == anchor
        }

        // 2. Shift-aware: the episode ending nearest the expected wake time,
        //    provided it is long enough to be a real sleep.
        if let shift, let expectedWake = shift.expectedWake {
            let candidates = onDay.filter { episodes[$0].spanMinutes >= minimumPrimaryMinutes }
            if let best = candidates.min(by: {
                abs(episodes[$0].end.timeIntervalSince(expectedWake))
                    < abs(episodes[$1].end.timeIntervalSince(expectedWake))
            }) {
                return PrimaryDecision(primaryIndex: best, rule: .shiftAware)
            }
        }

        // 2b. Post-shift elevation: sleep that began just after a night shift
        //     ended is the user's real sleep, and is promoted when it is the
        //     longest of the day — the case A8 exists to protect, where a
        //     daytime sleep would otherwise be dismissed as a nap.
        if let shift, let shiftEnd = shift.shiftEnd {
            let postShift = onDay.filter {
                let delta = episodes[$0].start.timeIntervalSince(shiftEnd)
                return delta >= 0 && delta <= postShiftWindowMinutes * 60
            }
            if let longestPostShift = postShift.max(by: { episodes[$0].spanMinutes < episodes[$1].spanMinutes }),
               let longestOfDay = onDay.max(by: { episodes[$0].spanMinutes < episodes[$1].spanMinutes }),
               episodes[longestPostShift].spanMinutes == episodes[longestOfDay].spanMinutes {
                return PrimaryDecision(primaryIndex: longestPostShift, rule: .postShift)
            }
        }

        // 3. General: longest episode ending inside a 26-hour window centred on
        //    04:00 of the anchor day, preferring one of at least two hours.
        let window = generalWindow(anchor: anchor, timeModel: timeModel)
        let inWindow = episodes.indices.filter {
            let end = episodes[$0].end
            return end >= window.start && end < window.end
        }
        if !inWindow.isEmpty {
            let longEnough = inWindow.filter { episodes[$0].spanMinutes >= minimumPrimaryMinutes }
            let pool = longEnough.isEmpty ? inWindow : longEnough
            if let best = pool.max(by: { episodes[$0].spanMinutes < episodes[$1].spanMinutes }) {
                return PrimaryDecision(primaryIndex: best, rule: .general)
            }
        }

        // 4. Nothing qualifies. Readiness is triggered by app-open with a prompt.
        return PrimaryDecision(primaryIndex: nil, rule: .none)
    }

    /// The 26-hour search window, centred on 04:00 local of the anchor day.
    ///
    /// Centred, not "the logical day": a night-shift worker's sleep can end at
    /// 17:00, well outside the 04:00-to-04:00 span, and the whole point of §8
    /// is that such sleep is still their primary sleep.
    static func generalWindow(anchor: LogicalDay, timeModel: TimeModel) -> (start: Date, end: Date) {
        let centre = timeModel.start(of: anchor) ?? Date.distantPast
        let half = generalWindowHours * 3600 / 2
        return (centre.addingTimeInterval(-half), centre.addingTimeInterval(half))
    }

    // MARK: - §8.3 Episode type assignment

    /// Assigns every episode its type once primary is known.
    ///
    /// Order matters and follows the spec: primary first, then post-shift
    /// (which outranks the duration rules — a two-hour sleep after a night
    /// shift is not a nap), then split, then nap. A user correction on any
    /// episode survives untouched.
    public static func assignTypes(
        episodes: [SleepEpisode],
        primary: PrimaryDecision,
        shift: ShiftContext? = nil
    ) -> [SleepEpisode] {
        var result = episodes
        for i in result.indices {
            if result[i].userCorrectedType != nil { continue }

            if i == primary.primaryIndex {
                result[i].type = .primary
                continue
            }

            if let shift, let shiftEnd = shift.shiftEnd {
                let delta = result[i].start.timeIntervalSince(shiftEnd)
                if delta >= 0 && delta <= postShiftWindowMinutes * 60 {
                    result[i].type = .postShift
                    continue
                }
            }

            result[i].type = result[i].spanMinutes >= splitThresholdMinutes ? .split : .nap
        }
        return result
    }

    /// §8.1-§8.3 end to end: samples in, classified episodes out.
    public static func classify(
        samples: [SleepStageSample],
        anchor: LogicalDay,
        timeModel: TimeModel,
        shift: ShiftContext? = nil
    ) -> (episodes: [SleepEpisode], primary: PrimaryDecision) {
        let grouped = groupIntoEpisodes(samples)
        let decision = determinePrimary(episodes: grouped, anchor: anchor,
                                        timeModel: timeModel, shift: shift)
        return (assignTypes(episodes: grouped, primary: decision, shift: shift), decision)
    }
}
