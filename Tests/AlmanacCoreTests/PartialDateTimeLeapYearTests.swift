import XCTest
@testable import AlmanacCore

/// `PartialDateTime.shapeMatches` already rejects calendar rollover (e.g.
/// February 30th) via a real `Calendar` check — see `PartialDateTime.swift`.
/// That check is exercised elsewhere for out-of-range days and months, but
/// never specifically for the leap-year case: February 29th is a real day in
/// some years and not others, which a fixed regex alone cannot know.
final class PartialDateTimeLeapYearTests: XCTestCase {

    func testFebruary29IsAcceptedInALeapYear() {
        let date = PartialDateTime(storedText: "2028-02-29", precision: .day)
        XCTAssertNotNil(date, "2028 is a leap year; February 29th is a real day")
        XCTAssertEqual(date?.text, "2028-02-29")
    }

    func testFebruary29IsRejectedInANonLeapYear() {
        XCTAssertNil(PartialDateTime(storedText: "2027-02-29", precision: .day),
                     "2027 is not a leap year; February 29th does not exist")
    }

    func testFebruary29IsAcceptedInACenturyLeapYear() {
        // Divisible by 400, so still a leap year despite being a century year.
        XCTAssertNotNil(PartialDateTime(storedText: "2000-02-29", precision: .day))
    }

    func testFebruary29IsRejectedInANonLeapCenturyYear() {
        // Divisible by 100 but not by 400 — the Gregorian exception.
        XCTAssertNil(PartialDateTime(storedText: "2100-02-29", precision: .day))
    }
}
