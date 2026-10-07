import SwiftUI
import AlmanacCore

/// Owns the readiness dashboard's state, the same pattern as `HydrationModel`
/// — one shared `Database` connection, configured once from `AlmanacApp`.
///
/// `refresh()` is the one place that assembles `ReadinessInputs`/
/// `ReadinessContext` from the other Slice 2/7 stores, calls
/// `ReadinessEngine.evaluate`, and persists the result via
/// `ReadinessRecordStore` — nothing else in the app does this.
///
/// **What is built now, and what is still a stand-in:**
///
/// - **Cycle:** `ReadinessCycleStore.ensureCycle` makes a bare cycle for
///   today if the primary-sleep-linking task (§8.4) hasn't created one yet.
/// - **Baseline:** `ReadinessBaselineService` supplies §9.7's calibration
///   counting and §9.8's general / shift-specific / Ramadan baselines, and
///   `ReadinessBaselineStore` records the result in the `readiness_baseline`
///   table that Migration014 created and nothing had ever written. This
///   replaced an on-the-fly 28-day average that counted *days* rather than
///   §9.7 valid days and never counted calibration at all, so the "Preliminary
///   estimate" label §9.7 requires could not appear.
/// - **Context:** injuries (§9.6.1), religious fast days, a session planned
///   before iftar, and the day's circadian transition are all read from the
///   stores that own them. Manual recovery days, planned rest days and planned
///   deload weeks stay `false`, and the reason is a missing data model rather
///   than a missing call: nothing in this repo records a deload week or a
///   recovery day, so there is nothing to read. Recorded in
///   `docs/features/readiness.md` rather than invented here.
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
    /// §9.7 — "Calibrating — Day X of 21 valid days", nil once calibration is
    /// complete. Distinct from the score being provisional: a user can be fully
    /// calibrated and still have only today's automatic inputs.
    @Published private(set) var calibrationDay: Int?
    /// §9.8's "limited comparable shift data" / "Ramadan context —
    /// calibrating", shown alongside the score. Its own property rather than a
    /// `ReadinessContext` flag, because the context flag of the nearest name
    /// means a circadian *transition*, which is a different fact.
    @Published private(set) var baselineNotice: ReadinessBaselineNotice?
    /// §13's circadian context for today, read from the stored
    /// `circadian_context` row. Nil when there is no row, or when the context is
    /// `.unknown` — with no shift schedule there is nothing to say, and a line
    /// reading "no schedule recorded" on every day would be noise.
    @Published private(set) var circadianLine: String?

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
        var baseline = ReadinessBaseline()
        let today = timeModel.logicalDay(Date())

        do {
            let now = Date()

            displayName = try profileStore.profile().displayName

            let episodes = try sleepStore.episodes(for: today.value)
            let primary = episodes.first { $0.effectiveType == .primary }
            // `measuredDurationMinutes`, not `durationMinutes`: a manual wake
            // marker is a zero-duration row, and zero is a real reading of the
            // worst possible night rather than the absence of a measurement.
            sleepDurationMinutes = primary?.measuredDurationMinutes
            let totalSleep = episodes.isEmpty ? nil : episodes.reduce(0) { $0 + $1.durationMinutes }

            // **Bounded to the day being scored**, and the bound is the last
            // primary episode's start when there is one. `latestValue(for:)`
            // would answer with the newest row in the table, which before manual
            // entry was the same thing — a HealthKit sample is always today's or
            // last night's. It is not any more: a reading typed in this morning
            // about last night is timestamped yesterday, so the unbounded read
            // would hand today's score a number from a different night — and
            // "newest row wins" is exactly the rule that makes it look reasonable
            // while doing it. The sleep duration above is read from one episode
            // for the same reason; §9.2 scores a night, not a history.
            let cycleStart = primary?.start ?? timeModel.start(of: today)
            if let cycleStart {
                latestRHR = try vitalsStore.latestValue(for: .restingHeartRate, since: cycleStart)?.value
                latestHRV = try vitalsStore.latestValue(for: .heartRateVariability, since: cycleStart)?.value
            } else {
                // No window means no way to tell which reading belongs to today,
                // and a reading that might be from any day is not today's input.
                // The whole-history read is not the fallback: that is the bug
                // above, and it would be reintroduced by exactly this line.
                latestRHR = nil
                latestHRV = nil
            }

            // §9.7's calibration count and §9.8's three baselines, from the
            // stores that hold the underlying days rather than from an average
            // recomputed here.
            let resolution = try ReadinessBaselineService(db: db!, timeModel: timeModel).resolve(for: today)
            baseline = resolution.baseline
            calibrationDay = resolution.calibrationDay
            baselineNotice = resolution.notice
            recordBaseline(resolution, day: today)

            circadianLine = try CircadianContextStore(db: db!).context(for: today.value)
                .flatMap { CircadianPresentation.line(for: $0.contextType, transitionDayN: $0.transitionDayN) }

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
                injuryAffectsTraining: !injuries.isEmpty,
                religiousFastDay: try ReligiousFastScheduleStore(db: db!).isFastDay(today.value),
                fastedSessionPlanned: try isSessionPlannedBeforeIftar(day: today),
                shiftTransition: try isCircadianTransition(day: today),
                calibrationDay: resolution.calibrationDay
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

    /// Writes the §9.8 baseline row for whichever type answered, so the record
    /// of *what today's score was measured against* survives the day. A failure
    /// here is deliberately silent: the score is already computed and correct,
    /// the row is a record rather than an input, and a persistence failure in an
    /// audit trail should not blank the number the user came for.
    private func recordBaseline(_ resolution: ReadinessBaselineResolution, day: LogicalDay) {
        guard let db,
              let start = resolution.windowStartDate,
              let end = resolution.windowEndDate else { return }
        let type: ReadinessBaselineType
        switch resolution.baseline.context {
        case .general, .calibration: type = .general
        case .shiftSpecific: type = .shiftSpecific
        case .ramadan: type = .ramadan
        }
        let shiftType: ShiftType? = type == .shiftSpecific
            ? try? ShiftScheduleStore(db: db).occurrence(for: day.value)?.shiftType
            : nil
        guard type != .shiftSpecific || shiftType != nil else { return }

        try? ReadinessBaselineStore(db: db).save(resolution.baseline, type: type, shiftType: shiftType,
                                                windowStartDate: start, windowEndDate: end,
                                                rollingWindowDays: ReadinessBaselineService.windowDays)
    }

    /// §9.6's `.religiousFastContext` precedence rule needs "a session is
    /// planned before iftar on a religious fast day" — the *plan*, not a
    /// completed workout. `PlannedWorkoutStore.nextUpcoming` is the plan, and
    /// Maghrib from the prayer cache is the deadline.
    ///
    /// False when the day is not a fast day at all, when no prayer times are
    /// cached yet, or when nothing is planned: each of those is "no fasted
    /// session is planned", which is what the flag means.
    private func isSessionPlannedBeforeIftar(day: LogicalDay) throws -> Bool {
        guard try ReligiousFastScheduleStore(db: db!).isFastDay(day.value) else { return false }
        let cached = try PrayerTimeCacheStore(db: db!).cachedDay(day.value)
        guard let maghrib = cached?.times.first(where: { $0.name == "maghrib" })?.timestamp else { return false }
        guard let planned = try PlannedWorkoutStore(db: db!).nextUpcoming(after: Date()) else { return false }
        return planned.scheduledAt <= maghrib
    }

    /// §13's transition states, which `ReadinessContext.shiftTransition` names.
    /// Read from the stored `circadian_context` row for the day rather than
    /// recomputed: `ReadinessCyclePrimaryLinkingService` already writes that row
    /// on every primary-sleep link, and a second computation here could disagree
    /// with it.
    private func isCircadianTransition(day: LogicalDay) throws -> Bool {
        guard let record = try CircadianContextStore(db: db!).context(for: day.value) else { return false }
        return record.contextType == .transitionEarlier || record.contextType == .transitionLater
    }

    /// Logs mood and soreness together (spec §17's `MoodSorenessScreen` is
    /// one combined check-in, not two), links both to today's cycle, and
    /// refreshes so the score becomes final.
    func logMoodAndSoreness(moodScore: Int, moodNotes: String?,
                             sorenessScore: Int, bodyAreas: [String], sorenessNotes: String?) throws {
        guard let moodStore, let sorenessStore, let cycleId else {
            throw EditorFailure(message: String(localized: "The database is unavailable."))
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
            throw EditorFailure(message: String(localized: "The database is unavailable."))
        }
        try recordStore.setFeedback(cycleId: pendingFeedback.readinessCycleId, value: value)
        refresh()
    }
}
