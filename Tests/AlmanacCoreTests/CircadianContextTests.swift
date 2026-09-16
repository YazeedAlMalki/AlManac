import XCTest
@testable import AlmanacCore

/// Technical Specification §13 — circadian context.
final class CircadianContextTests: XCTestCase {

    private let riyadh = TimeModel.riyadh()

    private func history(_ pairs: [(String, ShiftType)]) -> [LogicalDay: ShiftType] {
        Dictionary(uniqueKeysWithValues: pairs.map { (LogicalDay($0.0), $0.1) })
    }

    func testFiveDaysOnNightsIsStableNight() {
        let h = history([
            ("2026-09-01", .night), ("2026-09-02", .night), ("2026-09-03", .night),
            ("2026-09-04", .night), ("2026-09-05", .night)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertEqual(context.contextType, .stableNight)
        XCTAssertNil(context.transitionDayN)
    }

    func testFourDaysIsNotYetStable() {
        let h = history([
            ("2026-09-02", .day), ("2026-09-03", .day), ("2026-09-04", .day), ("2026-09-05", .day)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertNotEqual(context.contextType, .stableDay)
    }

    func testNightsToDaysIsATransitionEarlier() {
        let h = history([
            ("2026-09-01", .night), ("2026-09-02", .night), ("2026-09-03", .night),
            ("2026-09-04", .night), ("2026-09-05", .day)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertEqual(context.contextType, .transitionEarlier)
        XCTAssertEqual(context.transitionDayN, 1)
    }

    func testDaysToNightsIsATransitionLater() {
        let h = history([
            ("2026-09-03", .day), ("2026-09-04", .day), ("2026-09-05", .night)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertEqual(context.contextType, .transitionLater)
        XCTAssertEqual(context.transitionDayN, 1)
    }

    func testTransitionDayCounterAdvances() {
        let h = history([
            ("2026-09-01", .day), ("2026-09-02", .day), ("2026-09-03", .night),
            ("2026-09-04", .night), ("2026-09-05", .night)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertEqual(context.contextType, .transitionLater)
        XCTAssertEqual(context.transitionDayN, 3, "third day on the new pattern")
    }

    func testRestDayIsRecoveryWhateverSurroundsIt() {
        let h = history([
            ("2026-09-03", .night), ("2026-09-04", .night), ("2026-09-05", .rest)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertEqual(context.contextType, .recovery)
    }

    /// §6.11: a user with no shift schedule is the ordinary case. The engine
    /// says it does not know, and never infers a shift from sleep timing.
    func testNoScheduleIsUnknownNotInferred() {
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: [:], timeModel: riyadh)
        XCTAssertEqual(context.contextType, .unknown)
        XCTAssertNil(context.shiftType)
    }

    func testRotatingPatternsHaveNoStableStateAndNoDirection() {
        let h = history([
            ("2026-09-01", .split), ("2026-09-02", .split), ("2026-09-03", .split),
            ("2026-09-04", .split), ("2026-09-05", .split)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertEqual(context.contextType, .irregular,
                       "§5.4 has no stable_split — a rotating pattern is not a settled rhythm")
    }

    func testGapInTheScheduleEndsTheRun() {
        // The 3rd is unscheduled, so the 4th-5th run is two days, not five.
        let h = history([
            ("2026-09-01", .day), ("2026-09-02", .day),
            ("2026-09-04", .day), ("2026-09-05", .day)
        ])
        let context = CircadianContextEngine.determine(
            anchor: LogicalDay("2026-09-05"), history: h, timeModel: riyadh)
        XCTAssertNotEqual(context.contextType, .stableDay)
    }
}
