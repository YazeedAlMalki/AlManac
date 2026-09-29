import SwiftUI
import AlmanacCore

/// Owns the readiness dashboard's state, the same pattern as `HydrationModel`
/// — one shared `Database` connection, configured once from `AlmanacApp`.
///
/// `refresh()` is the one place that assembles `ReadinessInputs`/
/// `ReadinessContext` from the other Slice 2/7 stores, calls
/// `ReadinessEngine.evaluate`, and persists the result via
/// `ReadinessRecordStore` — nothing else in the app does this yet, so this is
/// also where several deliberately-simple stand-ins live until their real
/// tasks are built:
///
/// - **Cycle:** `ReadinessCycleStore.ensureCycle` makes a bare cycle for
///   today if the primary-sleep-linking task (§8.4) hasn't created one yet.
/// - **Baseline:** averaged here from `VitalsRecordStore`'s last 28 days of
///   readings, not from a persisted `readiness_baseline` row — no store
///   builds/maintains that table yet (§9.8).
/// - **Context:** only active, training-affecting injuries are wired in
///   (`InjuryNoteStore`, precedence rule §9.6.1). Manual recovery, rest/
///   deload days, religious fasting, and shift transitions all depend on
///   modules Slice 2 doesn't own (Training, Fasting's religious half,
///   Circadian) and stay at their `false`/`nil` defaults. Calibration-day
///   counting (§9.7's "Day X of 21") is not built either — `calibrationDay`
///   stays nil, so the UI never shows a preliminary-estimate label yet.
/// - **Stages:** the primary episode's stage split *is* wired
///   (`SleepStageBreakdownReader`). It was not, and §9.2's "no stage data → 50"
///   was therefore the score on every single run rather than the fallback: 20%
///   of every readiness score was a constant. **This changes scores users have
///   already seen** — for any night with HealthKit stage data the sleep-quality
///   term now moves off 50, usually upward, since a real night scores above
///   neutral. Historical `readiness_record` rows are not rewritten (§9.9), so
///   only newly-computed scores are affected, and a user comparing today's
///   score to last week's will see a step that is a correction, not a change in
///   their recovery.
@MainActor
final class ReadinessModel: ObservableObject {
    @Published private(set) var displayName = "User"
    @Published private(set) var outcome: ReadinessOutcome?
    @Published private(set) var cycleId: Int64?
    @Published private(set) var latestRHR: Double?
    @Published private(set) var latestHRV: Double?
    @Published private(set) var sleepDurationMinutes: Int?
    @Published private(set) var todayMood: MoodLogEntry?
    @Published private(set) var todaySoreness: SorenessLogEntry?
    /// A past cycle with a real score and no feedback yet — §9.10 requires
    /// the 👍/👎 prompt to wait until "the start of the next cycle" rather
    /// than showing right under the score that produced it, so this is
    /// always about a *previous* day's outcome, never today's.
    @Published private(set) var pendingFeedback: StoredReadinessRecord?
    /// Set when a read from the database failed, cleared the moment one
    /// succeeds. Distinct from an empty result: "nothing logged yet" and "could
    /// not read the log" are different claims, and a screen that shows the
    /// first when the second is true is as wrong as one that renders a missing
    /// reading as zero.
    @Published private(set) var readProblem: String?
    /// Set when today's score was worked out but could not be written down.
    /// Separate from `readProblem` because the two are not the same event and
    /// the user cannot act on them the same way: a failed read means today's
    /// number is missing, a failed save means it is correct on screen and will
    /// be gone by morning. One message for both would misdescribe one of them.
    @Published private(set) var saveProblem: String?

    private var db: Database?
    private var profileStore: ProfileStore?
    private var vitalsStore: VitalsRecordStore?
    private var moodStore: MoodLogStore?
    private var sorenessStore: SorenessLogStore?
    private var sleepStore: SleepEpisodeStore?
    private var injuryStore: InjuryNoteStore?
    private var cycleStore: ReadinessCycleStore?
    private var recordStore: ReadinessRecordStore?
    private var stageReader: SleepStageBreakdownReader?
    private let timeModel = TimeModel(timeZone: .current)

    func configure(db: Database?) {
        guard let db, self.db == nil else { return }
        self.db = db
        profileStore = ProfileStore(db: db)
        vitalsStore = VitalsRecordStore(db: db)
        moodStore = MoodLogStore(db: db)
        sorenessStore = SorenessLogStore(db: db)
        sleepStore = SleepEpisodeStore(db: db)
        injuryStore = InjuryNoteStore(db: db)
        cycleStore = ReadinessCycleStore(db: db)
        recordStore = ReadinessRecordStore(db: db)
        stageReader = SleepStageBreakdownReader(db: db)
        refresh()
    }

    func refresh() {
        guard let profileStore, let vitalsStore, let moodStore, let sorenessStore,
              let sleepStore, let injuryStore, let cycleStore, let recordStore,
              let stageReader else { return }
        // Hoisted out of the `do` so the save below can run on its own. Reading
        // and saving fail for different reasons and the user can do different
        // things about them, so they get different words — see below.
        var cycle: Int64?
        var result: ReadinessOutcome?
        let today = timeModel.logicalDay(Date())

        do {
            let now = Date()

            displayName = try profileStore.profile().displayName

            let episodes = try sleepStore.episodes(for: today.value)
            let primary = episodes.first { $0.effectiveType == .primary }
            sleepDurationMinutes = primary?.durationMinutes
            let totalSleep = episodes.isEmpty ? nil : episodes.reduce(0) { $0 + $1.durationMinutes }

            latestRHR = try vitalsStore.latestValue(for: "rhr")?.value
            latestHRV = try vitalsStore.latestValue(for: "hrv")?.value
            let baseline = try recentBaseline(vitalsStore: vitalsStore, today: today)

            todayMood = try moodStore.logs(for: today.value).last
            todaySoreness = try sorenessStore.logs(for: today.value).last

            let injuries = try injuryStore.injuriesAffectingTraining()

            cycle = try cycleStore.ensureCycle(anchorDate: today.value, at: now)
            cycleId = cycle

            let inputs = ReadinessInputs(
                sleepDurationMinutes: sleepDurationMinutes,
                // Read from the same primary episode the duration came from: a
                // duration from one night and a quality from another would be a
                // score about no night at all. Nil is the ordinary case for a
                // manual entry or a device that reports no stages, and §9.2
                // scores that 50 and flags it missing rather than excluding it.
                stages: try primary.flatMap { try stageReader.breakdown(forEpisode: $0) },
                restingHeartRate: latestRHR,
                hrv: latestHRV,
                mood: todayMood?.score,
                soreness: todaySoreness?.overallScore,
                totalSleepAcrossEpisodesMinutes: totalSleep
            )
            let context = ReadinessContext(
                activeInjuryBodyArea: injuries.first?.bodyArea,
                injuryAffectsTraining: !injuries.isEmpty
            )
            let state: ReadinessState = (todayMood != nil && todaySoreness != nil) ? .final : .provisional
            result = ReadinessEngine.evaluate(state: state, inputs: inputs, baseline: baseline, context: context)
            outcome = result
            readProblem = nil
        } catch {
            // Not crashing is the easy half. The old comment said it "simply
            // keeps showing whatever was last successfully computed", which
            // describes the worst case honestly: on a first run that is
            // nothing, so the dashboard shows the empty state that goes with
            // "we don't know yet" — and a read failure and a missing baseline
            // are indistinguishable to the user. Say which one it is.
            readProblem = "Could not read today's readiness data."
        }

        // Saving is separate from reading, and deliberately so. The score is
        // already assigned above, so if only the *save* fails then the number on
        // screen is correct and "could not read today's readiness data" would be
        // a fresh falsehood — in a change whose entire purpose is to stop the
        // app making exactly those. What the user needs to know then is that
        // their history is not being kept, which is a different and more
        // alarming sentence, so it gets its own.
        if let result, let cycle {
            do {
                try recordStore.record(result, cycleId: cycle, anchorDate: today.value)
                pendingFeedback = try recordStore.latestUnratedRecord(before: today.value)
                saveProblem = nil
            } catch {
                saveProblem = "Today's readiness was worked out, but Almanac could not save it."
            }
        }
    }

    /// Naive 28-day average, computed on the fly rather than read from a
    /// maintained `readiness_baseline` row (see the type-level doc comment).
    /// `validDayCount` counts distinct logical days with an RHR or HRV
    /// reading — an approximation of §9.7's "valid day" (which also counts a
    /// sleep-only day), good enough to feed the calibration-vs-personalised
    /// distinction without building the full baseline pipeline.
    private func recentBaseline(vitalsStore: VitalsRecordStore, today: LogicalDay) throws -> ReadinessBaseline {
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -28, to: Date()) else {
            return ReadinessBaseline()
        }
        let from = timeModel.logicalDay(windowStart).value
        let to = timeModel.day(after: today)?.value ?? today.value

        let rhrHistory = try vitalsStore.records(metric: "rhr", from: from, to: to)
        let hrvHistory = try vitalsStore.records(metric: "hrv", from: from, to: to)
        let avgRHR = rhrHistory.isEmpty ? nil : rhrHistory.map(\.value).reduce(0, +) / Double(rhrHistory.count)
        let avgHRV = hrvHistory.isEmpty ? nil : hrvHistory.map(\.value).reduce(0, +) / Double(hrvHistory.count)
        let validDays = Set((rhrHistory + hrvHistory).map(\.logicalDay)).count

        return ReadinessBaseline(restingHeartRate: avgRHR, hrv: avgHRV, validDayCount: validDays)
    }

    /// Logs mood and soreness together (spec §17's `MoodSorenessScreen` is
    /// one combined check-in, not two), links both to today's cycle, and
    /// refreshes so the score becomes final.
    func logMoodAndSoreness(moodScore: Int, moodNotes: String?,
                             sorenessScore: Int, bodyAreas: [String], sorenessNotes: String?) throws {
        guard let moodStore, let sorenessStore, let cycleId else {
            throw EditorFailure(message: "The database is unavailable.")
        }
        let now = Date()
        let moodID = try moodStore.log(MoodLogDraft(score: moodScore, timestamp: now, notes: moodNotes),
                                        logicalDay: timeModel.logicalDay(now).value)
        try moodStore.linkToReadinessCycle(id: moodID, cycleId: cycleId)

        let sorenessID = try sorenessStore.log(
            SorenessLogDraft(overallScore: sorenessScore, timestamp: now, bodyAreas: bodyAreas, notes: sorenessNotes),
            logicalDay: timeModel.logicalDay(now).value)
        try sorenessStore.linkToReadinessCycle(id: sorenessID, cycleId: cycleId)

        refresh()
    }

    /// `value` is `"thumbs_up"` or `"thumbs_down"` (§5.23).
    func submitFeedback(_ value: String) throws {
        guard let recordStore, let pendingFeedback else {
            throw EditorFailure(message: "The database is unavailable.")
        }
        try recordStore.setFeedback(cycleId: pendingFeedback.readinessCycleId, value: value)
        refresh()
    }
}
