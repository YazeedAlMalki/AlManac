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

    private var db: Database?
    private var profileStore: ProfileStore?
    private var vitalsStore: VitalsRecordStore?
    private var moodStore: MoodLogStore?
    private var sorenessStore: SorenessLogStore?
    private var sleepStore: SleepEpisodeStore?
    private var injuryStore: InjuryNoteStore?
    private var cycleStore: ReadinessCycleStore?
    private var recordStore: ReadinessRecordStore?
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
        refresh()
    }

    func refresh() {
        guard let profileStore, let vitalsStore, let moodStore, let sorenessStore,
              let sleepStore, let injuryStore, let cycleStore, let recordStore else { return }
        do {
            let now = Date()
            let today = timeModel.logicalDay(now)

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

            let cycle = try cycleStore.ensureCycle(anchorDate: today.value, at: now)
            cycleId = cycle

            let inputs = ReadinessInputs(
                sleepDurationMinutes: sleepDurationMinutes,
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
            let result = ReadinessEngine.evaluate(state: state, inputs: inputs, baseline: baseline, context: context)
            outcome = result
            try recordStore.record(result, cycleId: cycle, anchorDate: today.value)

            pendingFeedback = try recordStore.latestUnratedRecord(before: today.value)
        } catch {
            // A read/compute failure here should not crash the dashboard; it
            // simply keeps showing whatever was last successfully computed.
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
