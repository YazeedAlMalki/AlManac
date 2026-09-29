import Testing
import Foundation
@testable import AlmanacCore

/// BRD §6.15's "comparable-day filtering (Day Type + Circadian Context)" and
/// §13.2's "insights use `circadian_context.contextType` as a filter".
///
/// The fixtures are placed as *offsets back from the end of the window* rather
/// than as literal dates, because the window ends on the injected clock's "now"
/// and a literal date silently falls out of it. An earlier version of this file
/// used literal `2025-09-DD` labels and quietly lost half its sample that way,
/// which surfaced as a sample size of 12 rather than as a date error.
@Suite("Circadian comparable-day filtering")
struct CircadianComparableDayTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    /// 2025-09-18 08:00:00 Riyadh — the last day of every window below.
    let now = Date(timeIntervalSince1970: 1_758_171_600)

    init() throws {
        db = try TestDatabase()
    }

    private var query: InsightsQuery {
        InsightsQuery(db: db, timeModel: timeModel, clock: FixedClock(now))
    }

    // MARK: - Fixtures

    /// The logical day `offset` days before the window's last day.
    private func day(_ offset: Int) -> LogicalDay {
        var cursor = timeModel.logicalDay(now)
        for _ in 0..<offset {
            guard let previous = timeModel.day(before: cursor) else { break }
            cursor = previous
        }
        return cursor
    }

    private func noon(_ logical: LogicalDay) -> Date {
        let bits = logical.value.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]; comps.hour = 12
        comps.timeZone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        return calendar.date(from: comps)!
    }

    /// Sleep minutes and a matching readiness score on `logical`, written the
    /// way the app writes them.
    private func log(_ logical: LogicalDay, sleep: Int, readiness: Int) throws {
        let wake = noon(logical).addingTimeInterval(-5 * 3600)
        try SleepEpisodeStore(db: db).upsert(
            SleepEpisode(start: wake.addingTimeInterval(-Double(sleep) * 60), end: wake,
                         type: .primary, source: .healthkit, asleepMinutes: sleep),
            timezoneOffset: 180, logicalDay: logical.value)
        let cycleId = try ReadinessCycleStore(db: db).ensureCycle(anchorDate: logical.value, at: wake)
        let outcome = ReadinessOutcome(state: .final, score: readiness, color: .green,
                                       textDescription: nil, confidence: .high, missingInputs: [],
                                       formulaVersion: "1.0", inputSnapshot: "{}", recommendation: nil,
                                       precedenceApplied: [], baselineContext: .general)
        try ReadinessRecordStore(db: db).record(outcome, cycleId: cycleId, anchorDate: logical.value)
    }

    private func setContext(_ logical: LogicalDay, _ type: CircadianContextType) throws {
        try CircadianContextStore(db: db)
            .upsert(CircadianContext(date: logical, shiftType: nil, contextType: type))
    }

    /// Twenty settled days at offsets 5...24, rising together.
    ///
    /// Starting at 5 rather than 1 because `transitionDays` owns the four most
    /// recent days: an earlier version wrote both at offsets 1...20 and
    /// 1...4, so the second call silently overwrote the first on four days and
    /// the sample came out sixteen instead of twenty.
    private func settledDays() throws {
        for offset in 5...24 {
            let logical = day(offset)
            try log(logical, sleep: 380 + offset * 5, readiness: 55 + offset)
            try setContext(logical, .stableNight)
        }
    }

    /// Four transition days at offsets 1...4 — the four most recent days, which
    /// is also what a real schedule change looks like — moving the other way.
    private func transitionDays() throws {
        for (index, offset) in (1...4).enumerated() {
            let logical = day(offset)
            try log(logical, sleep: 300 + index * 10, readiness: 92 - index * 6)
            try setContext(logical, .transitionLater)
        }
    }

    // MARK: - Tests

    /// Twenty stable days where sleep and readiness move together, and four
    /// transition days where they move *against* each other. Pooling all 24
    /// would report a confidently negative `r`; the settled twenty give a
    /// strongly positive one. That inversion is the whole argument for the
    /// filter, and it is why the assertion is about the sign and not merely
    /// about the count.
    @Test("Transition days are excluded, and including them would reverse the answer")
    func transitionsAreExcluded() throws {
        try settledDays()
        try transitionDays()

        let summary = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 25)
        #expect(summary.excludedTransitionDays == 4)
        #expect(summary.sampleSize == 20, "the 20 settled days are the sample")
        let r = try #require(summary.rValue)
        #expect(r > 0.5, "over comparable days the relationship is positive, got \(r)")
    }

    @Test("A day with no circadian row is kept, not dropped")
    func missingContextIsNotATransition() throws {
        try settledDays()
        try transitionDays()
        // Half the settled days lose their context row, standing in for days the
        // readiness cycle linking service has not processed. Absence is not a
        // transition: the table is silent about days it has not reached.
        for offset in stride(from: 5, through: 24, by: 2) {
            try db.run("DELETE FROM circadian_context WHERE date = ?;", [.text(day(offset).value)])
        }

        let summary = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 25)
        #expect(summary.sampleSize == 20, "unlinked days are kept; absence is not a transition")
        #expect(summary.excludedTransitionDays == 4)
    }

    @Test("No non-transition context is ever filtered")
    func onlyTransitionsAreFiltered() throws {
        let benign: [CircadianContextType] = [.stableDay, .stableEvening, .stableNight,
                                               .firstDayAfterNight, .recovery, .irregular, .unknown]
        for (index, offset) in (1...7).enumerated() {
            let logical = day(offset)
            try log(logical, sleep: 380 + index * 5, readiness: 55 + index)
            try setContext(logical, benign[index])
        }

        let summary = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 8)
        #expect(summary.excludedTransitionDays == 0)
        #expect(summary.sampleSize == 7)
    }

    @Test("A filter that would starve the sample is dropped rather than applied")
    func filterIsDroppedWhenItWouldStarveTheSample() throws {
        for offset in 1...24 {
            let logical = day(offset)
            try log(logical, sleep: 380 + offset * 3, readiness: 55 + offset)
            // 16 of 24 days are transitions — well over half.
            try setContext(logical, offset % 3 == 0 ? .stableDay : .transitionLater)
        }

        let summary = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 25)
        #expect(summary.excludedTransitionDays == 0, "the filter was dropped, so nothing is claimed")
        #expect(summary.sampleSize == 24, "all the data is still used")
    }

    @Test("A window with nothing to filter makes no claim to have filtered")
    func noTransitionMeansNoClaim() throws {
        try settledDays()
        let summary = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 25)
        #expect(summary.excludedTransitionDays == 0)
        #expect(summary.sampleSize == 20)
    }

    @Test("A window too small to survive the filter falls back to using everything")
    func narrowWindowDropsTheFilter() throws {
        try settledDays()
        try transitionDays()

        // Offsets 0...5, and offset 0 is today itself, which carries no fixture:
        // five pairs, four of them transitions. Filtering would leave one of
        // five, well under the half-window floor, so the filter is dropped and
        // all five are used.
        let narrow = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 6)
        #expect(narrow.excludedTransitionDays == 0, "the filter was dropped, so nothing is claimed")
        #expect(narrow.sampleSize == 5)

        // Offsets 0...9: nine pairs, four of them transitions, five settled.
        // Five of nine clears the floor, so the filter applies.
        let medium = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 10)
        #expect(medium.excludedTransitionDays == 4)
        #expect(medium.sampleSize == 5)

        // 25 days: the full window.
        let wide = try query.correlation(between: .sleepMinutes, and: .readiness, dayCount: 25)
        #expect(wide.excludedTransitionDays == 4)
        #expect(wide.sampleSize == 20)
    }
}
