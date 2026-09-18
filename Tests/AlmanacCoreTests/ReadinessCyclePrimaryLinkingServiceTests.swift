import Testing
import Foundation
@testable import AlmanacCore

/// §7.3/§8.4 — tying a stored primary sleep episode to its `readiness_cycle`
/// row, closing the cycle before it, and re-linking wellness logs to both.
/// Deliberately does not exercise *which* episode ends up primary — that's
/// `SleepClassifier`'s job (`SleepClassifierTests`); every episode built
/// here is handed `type: .primary` directly, as if the classifier already
/// decided.
@Suite("ReadinessCyclePrimaryLinkingService Tests")
struct ReadinessCyclePrimaryLinkingServiceTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "UTC")!)

    init() throws {
        db = try TestDatabase()
    }

    var sleepStore: SleepEpisodeStore { SleepEpisodeStore(db: db) }
    var cycleStore: ReadinessCycleStore { ReadinessCycleStore(db: db) }
    var service: ReadinessCyclePrimaryLinkingService {
        ReadinessCyclePrimaryLinkingService(db: db, timeModel: timeModel)
    }

    private func utc(_ hour: Int, _ minute: Int = 0, day dateString: String) -> Date {
        var comps = DateComponents()
        let bits = dateString.split(separator: "-").compactMap { Int($0) }
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = hour; comps.minute = minute
        comps.timeZone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        return calendar.date(from: comps)!
    }

    @discardableResult
    private func storePrimary(start: Date, end: Date, logicalDay: String) throws -> Int64 {
        let episode = SleepEpisode(start: start, end: end, type: .primary, source: .healthkit,
                                    asleepMinutes: Int(end.timeIntervalSince(start) / 60))
        return try sleepStore.upsert(episode, timezoneOffset: 0, logicalDay: logicalDay)
    }

    @Test("Links a stored primary episode to a brand-new cycle")
    func createsNewCycleFromPrimaryEpisode() throws {
        let wake = utc(7, day: "2026-09-17")
        let episodeId = try storePrimary(start: utc(23, day: "2026-09-16"), end: wake, logicalDay: "2026-09-17")

        let result = try service.linkPrimaryEpisode(for: "2026-09-17")

        let unwrapped = try #require(result)
        #expect(unwrapped.closedPreviousCycleId == nil)
        let cycle = try #require(try cycleStore.cycle(id: unwrapped.cycleId))
        #expect(cycle.anchorDate == "2026-09-17")
        #expect(cycle.primarySleepEpisodeId == episodeId)
        #expect(cycle.primaryWakeTimestamp == wake)
        #expect(cycle.cycleStartTimestamp == wake)
        #expect(cycle.cycleEndTimestamp == nil)
    }

    @Test("Returns nil, and creates nothing, when the day has no primary episode")
    func nilWhenNoPrimaryEpisode() throws {
        #expect(try service.linkPrimaryEpisode(for: "2026-09-20") == nil)
        #expect(try db.query("SELECT COUNT(*) as n FROM readiness_cycle;").first?.int("n") == 0)
    }

    @Test("linkPrimaryEpisode(episodeId:) returns nil for a non-primary episode")
    func nilForNonPrimaryEpisode() throws {
        let nap = SleepEpisode(start: utc(13, day: "2026-09-17"), end: utc(13, 30, day: "2026-09-17"),
                                type: .nap, source: .healthkit, asleepMinutes: 30)
        let id = try sleepStore.upsert(nap, timezoneOffset: 0, logicalDay: "2026-09-17")

        #expect(try service.linkPrimaryEpisode(episodeId: id) == nil)
        #expect(try db.query("SELECT COUNT(*) as n FROM readiness_cycle;").first?.int("n") == 0)
    }

    @Test("Backfills an existing bare cycle instead of duplicating it")
    func backfillsBareCycleFromEnsureCycle() throws {
        // Dashboard opened before any sleep was classified — the existing
        // ensureCycle path this service leaves untouched.
        try cycleStore.ensureCycle(anchorDate: "2026-09-17", at: utc(6, day: "2026-09-17"))
        let wake = utc(7, day: "2026-09-17")
        let episodeId = try storePrimary(start: utc(23, day: "2026-09-16"), end: wake, logicalDay: "2026-09-17")

        let result = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))

        #expect(try db.query("SELECT COUNT(*) as n FROM readiness_cycle;").first?.int("n") == 1)
        let cycle = try #require(try cycleStore.cycle(id: result.cycleId))
        #expect(cycle.primarySleepEpisodeId == episodeId)
        #expect(cycle.cycleStartTimestamp == wake, "the bare timestamp must be replaced by the real wake time")
    }

    @Test("Linking the next day's primary episode closes the previous cycle")
    func closesPreviousCycleOnNextWake() throws {
        let wake1 = utc(7, day: "2026-09-17")
        let wake2 = utc(7, day: "2026-09-18")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake1, logicalDay: "2026-09-17")
        try storePrimary(start: utc(23, day: "2026-09-17"), end: wake2, logicalDay: "2026-09-18")

        let day1 = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let day2 = try #require(try service.linkPrimaryEpisode(for: "2026-09-18"))

        #expect(day2.closedPreviousCycleId == day1.cycleId)
        let cycle1 = try #require(try cycleStore.cycle(id: day1.cycleId))
        #expect(cycle1.cycleEndTimestamp == wake2)
        let cycle2 = try #require(try cycleStore.cycle(id: day2.cycleId))
        #expect(cycle2.cycleEndTimestamp == nil, "the newest cycle stays open")
    }

    @Test("Re-linking the same primary episode is idempotent — no duplicate cycle")
    func idempotentReprocessing() throws {
        let wake = utc(7, day: "2026-09-17")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake, logicalDay: "2026-09-17")

        let first = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let second = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))

        #expect(first.cycleId == second.cycleId)
        #expect(try db.query("SELECT COUNT(*) as n FROM readiness_cycle;").first?.int("n") == 1)
    }

    @Test("Mood and soreness logs inside the new cycle's window get linked")
    func linksWellnessLogsIntoTheNewCycle() throws {
        let wake = utc(7, day: "2026-09-17")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake, logicalDay: "2026-09-17")

        let moodStore = MoodLogStore(db: db)
        let sorenessStore = SorenessLogStore(db: db)
        let before = try moodStore.log(MoodLogDraft(score: 5, timestamp: wake.addingTimeInterval(-3600)),
                                        logicalDay: "2026-09-16")
        let after = try moodStore.log(MoodLogDraft(score: 8, timestamp: wake.addingTimeInterval(3600)),
                                       logicalDay: "2026-09-17")
        let sorenessAfter = try sorenessStore.log(SorenessLogDraft(overallScore: 3,
                                                                    timestamp: wake.addingTimeInterval(7200)),
                                                   logicalDay: "2026-09-17")

        let result = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))

        #expect(try moodStore.entry(id: before)?.readinessCycleId == nil)
        #expect(try moodStore.entry(id: after)?.readinessCycleId == result.cycleId)
        #expect(try sorenessStore.entry(id: sorenessAfter)?.readinessCycleId == result.cycleId)
    }

    @Test("Closing a cycle re-scopes its logs, moving a late-arriving one into the next cycle")
    func closingReassignsALateLogToTheNextCycle() throws {
        let wake1 = utc(7, day: "2026-09-17")
        let wake2 = utc(7, day: "2026-09-18")
        let episode1 = try storePrimary(start: utc(23, day: "2026-09-16"), end: wake1, logicalDay: "2026-09-17")
        let day1 = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))

        // A mood entry timestamped after wake2 arrives (or is backfilled)
        // while cycle1 is still open and day2 hasn't been linked yet.
        let moodStore = MoodLogStore(db: db)
        let lateLog = try moodStore.log(MoodLogDraft(score: 6, timestamp: wake2.addingTimeInterval(3600)),
                                         logicalDay: "2026-09-18")

        // Reprocessing cycle1 while it's still open links everything from
        // wake1 onward, unbounded — including the late log, wrongly.
        try service.linkPrimaryEpisode(episodeId: episode1)
        #expect(try moodStore.entry(id: lateLog)?.readinessCycleId == day1.cycleId)

        // Linking day2's primary episode closes cycle1 at wake2 and must
        // both drop the late log from cycle1 and pick it up into cycle2.
        try storePrimary(start: utc(23, day: "2026-09-17"), end: wake2, logicalDay: "2026-09-18")
        let day2 = try #require(try service.linkPrimaryEpisode(for: "2026-09-18"))

        #expect(try moodStore.entry(id: lateLog)?.readinessCycleId == day2.cycleId)
    }

    @Test("Linking a primary episode computes and attaches a circadian context")
    func circadianContextIsComputedAndAttached() throws {
        let wake = utc(7, day: "2026-09-17")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake, logicalDay: "2026-09-17")

        let result = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))

        let cycle = try #require(try cycleStore.cycle(id: result.cycleId))
        let contextId = try #require(cycle.circadianContextId)
        let context = try #require(try CircadianContextStore(db: db).context(for: "2026-09-17"))
        #expect(context.id == contextId)
        // No shift schedule at all in this test — the ordinary case §13.1
        // itself calls out as needing to stay fully supported.
        #expect(context.contextType == .unknown)
    }

    @Test("Backfilling an earlier night after a later one already exists fixes both neighbors")
    func outOfOrderBackfillFixesBothNeighbors() throws {
        let wake1 = utc(7, day: "2026-09-17")
        let wake2 = utc(7, day: "2026-09-18")
        let wake3 = utc(7, day: "2026-09-19")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake1, logicalDay: "2026-09-17")
        try storePrimary(start: utc(23, day: "2026-09-18"), end: wake3, logicalDay: "2026-09-19")

        let day1 = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let day3 = try #require(try service.linkPrimaryEpisode(for: "2026-09-19"))
        // Day 2 doesn't exist yet, so day1's nearest known successor really
        // is day3 at this point — correct given what's been processed so far.
        #expect(try cycleStore.cycle(id: day1.cycleId)?.cycleEndTimestamp == wake3)

        // The missing night now arrives — a backfill import, a late entry.
        try storePrimary(start: utc(23, day: "2026-09-17"), end: wake2, logicalDay: "2026-09-18")
        let day2 = try #require(try service.linkPrimaryEpisode(for: "2026-09-18"))

        #expect(try cycleStore.cycle(id: day1.cycleId)?.cycleEndTimestamp == wake2,
                "day1 must now close against day2's wake, not day3's")
        #expect(try cycleStore.cycle(id: day2.cycleId)?.cycleEndTimestamp == wake3,
                "the backfilled cycle must close against day3, the one that comes after it")
        #expect(try cycleStore.cycle(id: day3.cycleId)?.cycleEndTimestamp == nil,
                "day3 is still the newest cycle and stays open")
    }

    @Test("Correcting a cycle's wake time earlier re-closes its true predecessor, not the old one")
    func correctionMovesPredecessorBoundary() throws {
        let wakeZ = utc(7, day: "2026-09-16")
        let wakeA = utc(7, day: "2026-09-17")
        let wakeB = utc(7, day: "2026-09-18")
        try storePrimary(start: utc(23, day: "2026-09-15"), end: wakeZ, logicalDay: "2026-09-16")
        // A carries a healthKitUUID (unlike storePrimary's other calls) so the
        // correction below upserts onto the same row, mirroring HealthKit
        // reality: a correction re-delivers the same sample under the same
        // UUID with a revised end time, it doesn't mint a new one.
        let nightAUUID = "night-2026-09-17-primary"
        let episodeA = SleepEpisode(start: utc(23, day: "2026-09-16"), end: wakeA, type: .primary,
                                     source: .healthkit,
                                     asleepMinutes: Int(wakeA.timeIntervalSince(utc(23, day: "2026-09-16")) / 60),
                                     healthKitUUIDs: [nightAUUID])
        let episodeAId = try SleepEpisodeStore(db: db).upsert(episodeA, timezoneOffset: 0, logicalDay: "2026-09-17")
        try storePrimary(start: utc(23, day: "2026-09-17"), end: wakeB, logicalDay: "2026-09-18")

        let z = try #require(try service.linkPrimaryEpisode(for: "2026-09-16"))
        _ = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let b = try #require(try service.linkPrimaryEpisode(for: "2026-09-18"))
        #expect(try cycleStore.cycle(id: z.cycleId)?.cycleEndTimestamp == wakeA)

        // Correct A's wake time to be earlier, within the same anchor day.
        let correctedWakeA = utc(5, day: "2026-09-17")
        let correction = SleepEpisode(start: utc(23, day: "2026-09-16"), end: correctedWakeA,
                                       type: .primary, source: .healthkit,
                                       asleepMinutes: Int(correctedWakeA.timeIntervalSince(utc(23, day: "2026-09-16")) / 60),
                                       healthKitUUIDs: [nightAUUID])
        let correctedId = try SleepEpisodeStore(db: db).upsert(correction, timezoneOffset: 0, logicalDay: "2026-09-17")
        #expect(correctedId == episodeAId, "same night, same row — a correction, not a new episode")

        let recheck = try #require(try service.linkPrimaryEpisode(episodeId: correctedId))

        #expect(try cycleStore.cycle(id: z.cycleId)?.cycleEndTimestamp == correctedWakeA,
                "Z's true predecessor relationship must follow A's corrected, earlier wake time")
        #expect(try cycleStore.cycle(id: recheck.cycleId)?.cycleEndTimestamp == wakeB,
                "A's successor is still B, unaffected by A's own correction")
        #expect(try cycleStore.cycle(id: b.cycleId)?.cycleEndTimestamp == nil)
    }

    @Test("Correcting an episode's wake across an anchor-date boundary clears the abandoned row and preserves its old neighbor's boundary")
    func correctionAcrossAnchorDateClearsOrphanedRow() throws {
        let wake17 = utc(7, day: "2026-09-17")
        let wake18 = utc(7, day: "2026-09-18")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake17, logicalDay: "2026-09-17")
        // Carries a healthKitUUID, like the correction test above, so the later
        // correction upserts onto this same row instead of minting a new episode.
        let uuid18 = "night-2026-09-18-primary"
        let episode18 = SleepEpisode(start: utc(23, day: "2026-09-17"), end: wake18, type: .primary,
                                      source: .healthkit,
                                      asleepMinutes: Int(wake18.timeIntervalSince(utc(23, day: "2026-09-17")) / 60),
                                      healthKitUUIDs: [uuid18])
        let episode18Id = try SleepEpisodeStore(db: db).upsert(episode18, timezoneOffset: 0, logicalDay: "2026-09-18")

        let day17 = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let day18 = try #require(try service.linkPrimaryEpisode(episodeId: episode18Id))
        #expect(try cycleStore.cycle(id: day17.cycleId)?.cycleEndTimestamp == wake18)

        // A gross correction reveals the night actually belongs to the 25th, not
        // the 18th (e.g. an ingestion timezone bug caught well after the fact) —
        // far enough that it lands on a brand-new anchor date rather than merely
        // shifting the wake time within day18's own anchor window.
        let correctedWake = utc(7, day: "2026-09-25")
        let correction = SleepEpisode(start: utc(23, day: "2026-09-24"), end: correctedWake, type: .primary,
                                       source: .healthkit,
                                       asleepMinutes: Int(correctedWake.timeIntervalSince(utc(23, day: "2026-09-24")) / 60),
                                       healthKitUUIDs: [uuid18])
        let correctedId = try SleepEpisodeStore(db: db).upsert(correction, timezoneOffset: 0, logicalDay: "2026-09-25")
        #expect(correctedId == episode18Id, "same episode, corrected — not a new one")

        let recheck = try #require(try service.linkPrimaryEpisode(episodeId: correctedId))
        #expect(recheck.cycleId != day18.cycleId, "the corrected wake lands on a different anchor date's row")

        let staleRow = try #require(try cycleStore.cycle(id: day18.cycleId))
        #expect(staleRow.primarySleepEpisodeId == nil, "the old row must stop claiming the episode that moved away")
        #expect(staleRow.cycleStartTimestamp == nil)
        #expect(staleRow.cycleEndTimestamp == nil)

        #expect(try cycleStore.cycle(id: day17.cycleId)?.cycleEndTimestamp == correctedWake,
                "day17's true successor is now the corrected cycle, not the abandoned day18 row")

        let claimCount = try db.query(
            "SELECT COUNT(*) as n FROM readiness_cycle WHERE primarySleepEpisodeId = ?;", [.integer(episode18Id)]
        ).first?.int("n")
        #expect(claimCount == 1, "only one row may claim this episode as primary")
    }

    @Test("Clearing an abandoned row also deletes its stale readiness_record, not just the cycle fields")
    func orphanClearingDeletesStaleRecord() throws {
        let wake17 = utc(7, day: "2026-09-17")
        let wake18 = utc(7, day: "2026-09-18")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake17, logicalDay: "2026-09-17")
        let uuid18 = "night-2026-09-18-primary"
        let episode18 = SleepEpisode(start: utc(23, day: "2026-09-17"), end: wake18, type: .primary,
                                      source: .healthkit,
                                      asleepMinutes: Int(wake18.timeIntervalSince(utc(23, day: "2026-09-17")) / 60),
                                      healthKitUUIDs: [uuid18])
        let episode18Id = try SleepEpisodeStore(db: db).upsert(episode18, timezoneOffset: 0, logicalDay: "2026-09-18")

        _ = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let day18 = try #require(try service.linkPrimaryEpisode(episodeId: episode18Id))

        // A score was already computed and stored for day18 (as
        // ReadinessModel.refresh() would do) before the correction arrives.
        let recordStore = ReadinessRecordStore(db: db)
        let outcome = ReadinessOutcome(
            state: .final, score: 82, color: .green,
            textDescription: "Recovery is good — ready for a strong session",
            confidence: .high, missingInputs: [], formulaVersion: "1.0", inputSnapshot: "{}",
            recommendation: "Recovery is good — ready for a strong session",
            precedenceApplied: [], baselineContext: .general)
        try recordStore.record(outcome, cycleId: day18.cycleId, anchorDate: "2026-09-18")
        #expect(try recordStore.record(cycleId: day18.cycleId)?.score == 82)

        // The correction reveals the night actually belongs to the 25th, far
        // enough to land on a brand-new anchor date (see the sibling test above).
        let correctedWake = utc(7, day: "2026-09-25")
        let correction = SleepEpisode(start: utc(23, day: "2026-09-24"), end: correctedWake, type: .primary,
                                       source: .healthkit,
                                       asleepMinutes: Int(correctedWake.timeIntervalSince(utc(23, day: "2026-09-24")) / 60),
                                       healthKitUUIDs: [uuid18])
        let correctedId = try SleepEpisodeStore(db: db).upsert(correction, timezoneOffset: 0, logicalDay: "2026-09-25")
        try service.linkPrimaryEpisode(episodeId: correctedId)

        #expect(try recordStore.record(cycleId: day18.cycleId) == nil,
               "a score computed against an episode that has since moved to a different day must not survive")
        #expect(try recordStore.latestUnratedRecord(before: "2026-09-26") == nil,
               "the stale, now-deleted record must never be offered for feedback")
    }

    @Test("Clearing an abandoned row picks its logs back up into the neighbor that now covers that window")
    func orphanClearingRescopesLogsToTheExtendedNeighbor() throws {
        let wake17 = utc(7, day: "2026-09-17")
        let wake18 = utc(7, day: "2026-09-18")
        try storePrimary(start: utc(23, day: "2026-09-16"), end: wake17, logicalDay: "2026-09-17")
        let uuid18 = "night-2026-09-18-primary"
        let episode18 = SleepEpisode(start: utc(23, day: "2026-09-17"), end: wake18, type: .primary,
                                      source: .healthkit,
                                      asleepMinutes: Int(wake18.timeIntervalSince(utc(23, day: "2026-09-17")) / 60),
                                      healthKitUUIDs: [uuid18])
        let episode18Id = try SleepEpisodeStore(db: db).upsert(episode18, timezoneOffset: 0, logicalDay: "2026-09-18")

        // Logged before day18's cycle is linked — falls inside what day18's
        // window is about to cover (it's still open, so unbounded above).
        let moodStore = MoodLogStore(db: db)
        let mid = try moodStore.log(MoodLogDraft(score: 7, timestamp: utc(9, day: "2026-09-20")),
                                     logicalDay: "2026-09-20")

        let day17 = try #require(try service.linkPrimaryEpisode(for: "2026-09-17"))
        let day18 = try #require(try service.linkPrimaryEpisode(episodeId: episode18Id))
        #expect(try moodStore.entry(id: mid)?.readinessCycleId == day18.cycleId)

        let correctedWake = utc(7, day: "2026-09-25")
        let correction = SleepEpisode(start: utc(23, day: "2026-09-24"), end: correctedWake, type: .primary,
                                       source: .healthkit,
                                       asleepMinutes: Int(correctedWake.timeIntervalSince(utc(23, day: "2026-09-24")) / 60),
                                       healthKitUUIDs: [uuid18])
        let correctedId = try SleepEpisodeStore(db: db).upsert(correction, timezoneOffset: 0, logicalDay: "2026-09-25")
        try service.linkPrimaryEpisode(episodeId: correctedId)

        #expect(try moodStore.entry(id: mid)?.readinessCycleId == day17.cycleId,
                "the log falls inside day17's newly-extended window, now that day18's row is gone")
    }
}
