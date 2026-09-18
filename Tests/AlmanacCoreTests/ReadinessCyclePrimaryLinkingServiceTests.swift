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
}
