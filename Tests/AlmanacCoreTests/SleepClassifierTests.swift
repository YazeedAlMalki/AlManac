import XCTest
@testable import AlmanacCore

/// Technical Specification §8 — sleep classification.
///
/// The scenarios here are the ones the spec's own acceptance tests turn on,
/// A8 above all: a night-shift worker's daytime sleep must come out as their
/// primary sleep, not as a long nap.
final class SleepClassifierTests: XCTestCase {

    private let riyadh = TimeModel.riyadh()

    /// Riyadh local time (UTC+3) as an instant.
    private func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso + "+03:00")!
    }

    private func sample(_ start: String, _ end: String, _ stage: SleepStage,
                        app: String? = "com.apple.health", uuid: String? = nil) -> SleepStageSample {
        SleepStageSample(start: at(start), end: at(end), stage: stage,
                         sourceApp: app, sourceDevice: "Apple Watch", healthKitUUID: uuid)
    }

    // MARK: - §8.1 grouping

    func testGapOfExactlyThirtyMinutesMerges() {
        let episodes = SleepClassifier.groupIntoEpisodes([
            sample("2026-09-04T23:00:00", "2026-09-05T01:00:00", .asleepCore),
            sample("2026-09-05T01:30:00", "2026-09-05T05:00:00", .asleepCore)
        ])
        XCTAssertEqual(episodes.count, 1, "a 30-minute gap is within the merge rule")
        XCTAssertEqual(episodes[0].spanMinutes, 360)
    }

    func testGapOfThirtyOneMinutesSplits() {
        let episodes = SleepClassifier.groupIntoEpisodes([
            sample("2026-09-04T23:00:00", "2026-09-05T01:00:00", .asleepCore),
            sample("2026-09-05T01:31:00", "2026-09-05T05:00:00", .asleepCore)
        ])
        XCTAssertEqual(episodes.count, 2, "past 30 minutes the spec starts a new episode")
    }

    func testShortSampleInsideALongOneDoesNotLookLikeAGap() {
        // A 5-minute awake sample nested inside a long asleep sample: measured
        // against the previous sample's end this would appear to be a huge gap.
        let episodes = SleepClassifier.groupIntoEpisodes([
            sample("2026-09-04T23:00:00", "2026-09-05T06:00:00", .asleepCore),
            sample("2026-09-05T02:00:00", "2026-09-05T02:05:00", .awake),
            sample("2026-09-05T06:10:00", "2026-09-05T06:40:00", .asleepREM)
        ])
        XCTAssertEqual(episodes.count, 1)
    }

    func testAwakeAndInBedDoNotCountAsAsleepMinutes() {
        let episodes = SleepClassifier.groupIntoEpisodes([
            sample("2026-09-04T22:00:00", "2026-09-04T23:00:00", .inBed),
            sample("2026-09-04T23:00:00", "2026-09-05T01:00:00", .asleepCore),
            sample("2026-09-05T01:00:00", "2026-09-05T01:20:00", .awake),
            sample("2026-09-05T01:20:00", "2026-09-05T03:00:00", .asleepDeep)
        ])
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].spanMinutes, 300, "the episode spans bed-time to waking")
        XCTAssertEqual(episodes[0].asleepMinutes, 220, "but only asleep stages count as sleep")
    }

    // MARK: - §8.5 multi-source

    func testAppleWatchWinsOverThirdPartyWithLongerCoverage() {
        let winner = SleepClassifier.preferredSource(in: [
            sample("2026-09-04T23:00:00", "2026-09-05T05:00:00", .asleepCore, app: "com.sleepapp.autosleep"),
            sample("2026-09-04T23:30:00", "2026-09-05T04:00:00", .asleepCore, app: "com.apple.health")
        ])
        XCTAssertEqual(winner, "com.apple.health")
    }

    func testOverlappingSourcesDoNotSumTheirDurations() {
        // Two apps describing the same six hours. The user slept six hours,
        // not twelve, and no arithmetic here may suggest otherwise.
        let episodes = SleepClassifier.groupIntoEpisodes([
            sample("2026-09-04T23:00:00", "2026-09-05T05:00:00", .asleepCore, app: "com.apple.health"),
            sample("2026-09-04T23:00:00", "2026-09-05T05:00:00", .asleepCore, app: "com.sleepapp.autosleep")
        ])
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].asleepMinutes, 360)
    }

    func testThirdPartyChoiceIsDeterministicOnEqualCoverage() {
        let samples = [
            sample("2026-09-04T23:00:00", "2026-09-05T05:00:00", .asleepCore, app: "com.b.app"),
            sample("2026-09-04T23:00:00", "2026-09-05T05:00:00", .asleepCore, app: "com.a.app")
        ]
        XCTAssertEqual(SleepClassifier.preferredSource(in: samples),
                       SleepClassifier.preferredSource(in: samples.reversed()))
    }

    // MARK: - §8.2 primary determination

    func testLongestQualifyingEpisodeIsPrimary() {
        let (episodes, decision) = SleepClassifier.classify(
            samples: [
                sample("2026-09-04T23:00:00", "2026-09-05T06:30:00", .asleepCore),
                sample("2026-09-05T14:00:00", "2026-09-05T14:40:00", .asleepCore)
            ],
            anchor: LogicalDay("2026-09-05"), timeModel: riyadh
        )
        XCTAssertEqual(decision.rule, .general)
        XCTAssertEqual(episodes[decision.primaryIndex!].spanMinutes, 450)
        XCTAssertEqual(episodes[0].type, .primary)
        XCTAssertEqual(episodes[1].type, .nap)
    }

    func testUserCorrectionOverridesTheAlgorithm() {
        var episodes = SleepClassifier.groupIntoEpisodes([
            sample("2026-09-04T23:00:00", "2026-09-05T06:30:00", .asleepCore),
            sample("2026-09-05T14:00:00", "2026-09-05T16:00:00", .asleepCore)
        ])
        episodes[1].userCorrectedType = .primary

        let decision = SleepClassifier.determinePrimary(
            episodes: episodes, anchor: LogicalDay("2026-09-05"), timeModel: riyadh
        )
        XCTAssertEqual(decision.rule, .userCorrection)
        XCTAssertEqual(decision.primaryIndex, 1, "the shorter episode wins because the user said so")
    }

    func testShiftAwarePicksEpisodeEndingNearestExpectedWake() {
        let episodes = SleepClassifier.groupIntoEpisodes([
            // Longer, but ends nowhere near the expected wake.
            sample("2026-09-04T22:00:00", "2026-09-05T06:00:00", .asleepCore),
            sample("2026-09-05T09:00:00", "2026-09-05T13:00:00", .asleepCore)
        ])
        let shift = ShiftContext(date: LogicalDay("2026-09-05"), shiftType: .night,
                                 shiftEnd: at("2026-09-05T08:00:00"),
                                 expectedWake: at("2026-09-05T13:15:00"))

        let decision = SleepClassifier.determinePrimary(
            episodes: episodes, anchor: LogicalDay("2026-09-05"), timeModel: riyadh, shift: shift
        )
        XCTAssertEqual(decision.rule, .shiftAware)
        XCTAssertEqual(decision.primaryIndex, 1)
    }

    /// Acceptance scenario A8. Night shift ends at 08:00; the user sleeps
    /// 09:00-16:00 and takes a short nap in the evening. The daytime sleep is
    /// the primary episode, and nothing about the clock may demote it.
    func testDaytimeSleepAfterNightShiftIsPrimaryNotNap() {
        let shift = ShiftContext(date: LogicalDay("2026-09-05"), shiftType: .night,
                                 shiftEnd: at("2026-09-05T08:00:00"))

        let (episodes, decision) = SleepClassifier.classify(
            samples: [
                sample("2026-09-05T09:00:00", "2026-09-05T16:00:00", .asleepCore),
                sample("2026-09-05T20:00:00", "2026-09-05T20:30:00", .asleepCore)
            ],
            anchor: LogicalDay("2026-09-05"), timeModel: riyadh, shift: shift
        )
        XCTAssertEqual(decision.rule, .postShift)
        XCTAssertEqual(episodes[0].type, .primary)
        XCTAssertEqual(episodes[1].type, .nap)
    }

    func testTwoHourSleepAfterNightShiftIsPostShiftRatherThanNap() {
        let shift = ShiftContext(date: LogicalDay("2026-09-05"), shiftType: .night,
                                 shiftEnd: at("2026-09-05T08:00:00"))
        let (episodes, decision) = SleepClassifier.classify(
            samples: [
                // Short sleep straight off the shift.
                sample("2026-09-05T08:30:00", "2026-09-05T10:30:00", .asleepCore),
                // The longer sleep of this cycle, later the same afternoon.
                sample("2026-09-05T11:30:00", "2026-09-05T16:30:00", .asleepCore)
            ],
            anchor: LogicalDay("2026-09-05"), timeModel: riyadh, shift: shift
        )
        XCTAssertEqual(decision.primaryIndex, 1, "the five-hour sleep is the primary one")
        XCTAssertEqual(episodes[0].type, .postShift,
                       "sleep caused by the shift is post_shift, never a nap")
    }

    /// A boundary worth pinning down, because two spec rules meet here and it
    /// reads like a contradiction until you see which question each answers.
    ///
    /// §7.1 puts 02:00 on the 6th inside logical day the 5th. §8.2's search
    /// window is 26 hours centred on 04:00 of the anchor day, which for the 5th
    /// ends at 17:00 on the 5th — so a sleep ending at 02:00 on the 6th is not
    /// a candidate for the 5th's primary sleep. That is correct: that sleep
    /// supports the waking on the 6th, and belongs to the 6th's cycle. The
    /// logical day answers "which day does this record count toward"; the
    /// window answers "which sleep did this waking come out of".
    func testSleepEndingAfterTheWindowBelongsToTheNextCycle() {
        let samples = [sample("2026-09-05T18:00:00", "2026-09-06T02:00:00", .asleepCore)]

        XCTAssertEqual(riyadh.logicalDay(at("2026-09-06T02:00:00")).value, "2026-09-05",
                       "the record counts toward the 5th")

        let fifth = SleepClassifier.determinePrimary(
            episodes: SleepClassifier.groupIntoEpisodes(samples),
            anchor: LogicalDay("2026-09-05"), timeModel: riyadh
        )
        XCTAssertNil(fifth.primaryIndex, "but it is not the sleep the 5th's waking came out of")

        let sixth = SleepClassifier.determinePrimary(
            episodes: SleepClassifier.groupIntoEpisodes(samples),
            anchor: LogicalDay("2026-09-06"), timeModel: riyadh
        )
        XCTAssertEqual(sixth.primaryIndex, 0, "the 6th's cycle claims it")
    }

    func testEpisodesBetweenNinetyMinutesAndTwoHoursAreSplitNotNap() {
        let (episodes, _) = SleepClassifier.classify(
            samples: [
                sample("2026-09-04T23:00:00", "2026-09-05T06:00:00", .asleepCore),
                sample("2026-09-05T13:00:00", "2026-09-05T14:40:00", .asleepCore)
            ],
            anchor: LogicalDay("2026-09-05"), timeModel: riyadh
        )
        XCTAssertEqual(episodes[1].spanMinutes, 100)
        XCTAssertEqual(episodes[1].type, .split)
    }

    func testNoEpisodesMeansNoPrimaryRatherThanAGuess() {
        let decision = SleepClassifier.determinePrimary(
            episodes: [], anchor: LogicalDay("2026-09-05"), timeModel: riyadh
        )
        XCTAssertNil(decision.primaryIndex)
        XCTAssertEqual(decision.rule, .none)
    }

    func testShortestEpisodeStillWinsWhenNothingReachesTwoHours() {
        // §8.2 step 3b: with no episode of two hours, the longest available one
        // is still primary rather than the day having no sleep at all.
        let (episodes, decision) = SleepClassifier.classify(
            samples: [
                sample("2026-09-05T02:00:00", "2026-09-05T03:00:00", .asleepCore),
                sample("2026-09-05T05:00:00", "2026-09-05T06:30:00", .asleepCore)
            ],
            anchor: LogicalDay("2026-09-05"), timeModel: riyadh
        )
        XCTAssertEqual(decision.rule, .general)
        XCTAssertEqual(episodes[decision.primaryIndex!].spanMinutes, 90)
    }
}
