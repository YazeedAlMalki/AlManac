import XCTest
@testable import AlmanacCore

final class TimeModelTests: XCTestCase {

    private func instant(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    // Midnight is no longer Almanac's boundary (spec §7.1 fixes it at 04:00),
    // but it is still a boundary the model must compute correctly, so this
    // asks for it explicitly rather than relying on the default.
    func testRiyadhMidnightBoundary() {
        let tm = TimeModel.riyadh(boundary: .midnight)
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
        let tm = TimeModel(timeZone: TimeZone(identifier: "Europe/London")!, boundary: .midnight)
        let b = tm.bounds(of: LogicalDay("2026-03-29"))!   // BST begins
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 23 * 3600, accuracy: 1)
    }

    func testDSTFallBackDayIsLongerThan24Hours() {
        let tm = TimeModel(timeZone: TimeZone(identifier: "Europe/London")!, boundary: .midnight)
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

    // 2026 is not a leap year, so the round trip above never exercises
    // February 29th. 2028 is.
    func testLeapYearWalkIncludesFebruary29() {
        let tm = TimeModel.riyadh(boundary: .wakeOffset(hours: 4))
        var day = LogicalDay("2028-01-01")
        var count = 0
        var sawFeb29 = false
        while day.value < "2029-01-01" {
            let b = tm.bounds(of: day)!
            XCTAssertEqual(tm.logicalDay(b.start), day, "start of \(day) mapped elsewhere")
            XCTAssertEqual(tm.logicalDay(b.end.addingTimeInterval(-1)), day,
                           "last second of \(day) mapped elsewhere")
            if day.value == "2028-02-29" { sawFeb29 = true }
            day = tm.day(after: day)!
            count += 1
        }
        XCTAssertEqual(count, 366)
        XCTAssertTrue(sawFeb29, "the walk must pass through the leap day")
    }

    func testFebruary28RollsIntoFebruary29ThenMarch1InALeapYear() {
        let tm = TimeModel.riyadh()
        XCTAssertEqual(tm.day(after: LogicalDay("2028-02-28")), LogicalDay("2028-02-29"))
        XCTAssertEqual(tm.day(after: LogicalDay("2028-02-29")), LogicalDay("2028-03-01"))
    }

    // Asia/Kolkata carries no DST, but its UTC+5:30 offset is not a whole
    // hour — a boundary computed by truncating to whole hours would be wrong
    // by 30 minutes here.
    func testHalfHourOffsetZoneAsiaKolkata() {
        let tm = TimeModel(timeZone: TimeZone(identifier: "Asia/Kolkata")!, boundary: .midnight)
        // 18:29 UTC is 23:59 IST — still the 4th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-04T18:29:00Z")).value, "2026-09-04")
        // 18:30 UTC is 00:00 IST — the 5th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-04T18:30:00Z")).value, "2026-09-05")

        let b = tm.bounds(of: LogicalDay("2026-09-05"))!
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 24 * 3600, accuracy: 1,
                       "a zone with no DST is exactly 24 hours regardless of its offset")
    }

    // Southern-hemisphere DST is the same clock-shift rule as London's, on
    // reversed calendar dates: Sydney's day-length flips (23h/25h) land in
    // October/April, not March/October.
    func testSouthernHemisphereDSTAustraliaSydney() {
        let tm = TimeModel(timeZone: TimeZone(identifier: "Australia/Sydney")!, boundary: .midnight)
        // Clocks spring forward on the first Sunday of October.
        let springForward = tm.bounds(of: LogicalDay("2026-10-04"))!
        XCTAssertEqual(springForward.end.timeIntervalSince(springForward.start), 23 * 3600, accuracy: 1)
        // Clocks fall back on the first Sunday of April.
        let fallBack = tm.bounds(of: LogicalDay("2026-04-05"))!
        XCTAssertEqual(fallBack.end.timeIntervalSince(fallBack.start), 25 * 3600, accuracy: 1)
    }

    // Spec §7.1 fixes the boundary at 04:00. Before the spec was recovered the
    // default was midnight as an explicit placeholder, and Native's hydration
    // model silently took it — which is exactly the failure this test exists
    // to catch if the default ever drifts back.
    func testDefaultBoundaryIsAlmanacFourAM() {
        let tm = TimeModel.riyadh()
        XCTAssertEqual(tm.boundary, .wakeOffset(hours: 4))
        // 03:59 Riyadh on the 5th still belongs to the 4th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-05T00:59:00Z")).value, "2026-09-04")
        // 04:00 Riyadh starts the 5th.
        XCTAssertEqual(tm.logicalDay(instant("2026-09-05T01:00:00Z")).value, "2026-09-05")
    }
}
