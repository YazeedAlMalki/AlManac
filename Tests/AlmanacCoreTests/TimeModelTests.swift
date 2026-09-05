import XCTest
@testable import AlmanacCore

final class TimeModelTests: XCTestCase {

    private func instant(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    func testRiyadhMidnightBoundary() {
        let tm = TimeModel.riyadh()
        // 20:59 UTC is 23:59 Riyadh — still the 4th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-04T20:59:00Z")).value, "2026-09-04")
        // 21:00 UTC is 00:00 Riyadh — the 5th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-04T21:00:00Z")).value, "2026-09-05")
    }

    func testWakeOffsetPullsSmallHoursIntoPreviousDay() {
        let tm = TimeModel.riyadh(boundary: .wakeOffset(hours: 4))
        // 01:30 Riyadh on the 5th belongs to the night of the 4th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-04T22:30:00Z")).value, "2026-09-04")
        // 03:59 Riyadh — still the 4th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-05T00:59:00Z")).value, "2026-09-04")
        // 04:00 Riyadh — the 5th begins.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-05T01:00:00Z")).value, "2026-09-05")
    }

    func testBoundsAreHalfOpenAndRoundTrip() {
        let tm = TimeModel.riyadh(boundary: .wakeOffset(hours: 4))
        let day = LogicalDay("2026-09-04")
        let b = tm.bounds(of: day)!
        XCTAssertTrue(tm.contains(b.start, in: day))
        XCTAssertFalse(tm.contains(b.end, in: day), "end must be exclusive")
        XCTAssertEqual(tm.logicalDay(b.start).value, "2026-09-04")
        XCTAssertEqual(tm.logicalDay(b.end).value, "2026-09-05")
    }

    // The reason bounds() adds a calendar day instead of 86,400 seconds.
    func testDSTSpringForwardDayIsShorterThan24Hours() {
        let tm = TimeModel(timeZone: TimeZone(identifier: "Europe/London")!)
        let b = tm.bounds(of: LogicalDay("2026-03-29"))!   // BST begins
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 23 * 3600, accuracy: 1)
    }

    func testDSTFallBackDayIsLongerThan24Hours() {
        let tm = TimeModel(timeZone: TimeZone(identifier: "Europe/London")!)
        let b = tm.bounds(of: LogicalDay("2026-10-25"))!   // BST ends
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 25 * 3600, accuracy: 1)
    }

    func testEveryDayOfAYearRoundTrips() {
        let tm = TimeModel.riyadh(boundary: .wakeOffset(hours: 4))
        var day = LogicalDay("2026-01-01")
        var count = 0
        while day.value < "2027-01-01" {
            let b = tm.bounds(of: day)!
            XCTAssertEqual(tm.logicalDay(b.start), day, "start of \(day) mapped elsewhere")
            XCTAssertEqual(tm.logicalDay(b.end.addingTimeInterval(-1)), day,
                           "last second of \(day) mapped elsewhere")
            day = tm.day(after: day)!
            count += 1
        }
        XCTAssertEqual(count, 365)
    }
}
