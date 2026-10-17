import Testing
import Foundation
@testable import AlmanacCore

/// The date a person picks in a date picker is a calendar date, not an
/// instant to be filed under the 04:00 day boundary. `TimeModel.logicalDay`
/// answers a different question: which day an *event* belongs to.
@Suite("Calendar day keys")
struct CalendarDayKeyTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    private func instant(_ y: Int, _ m: Int, _ d: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = riyadh
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test("A date picked at 02:00 keeps its own date, though the logical day has not begun")
    func pickedDateIsNotShiftedByTheBoundary() {
        let picked = instant(2026, 9, 5, 2)

        #expect(TimeModel(timeZone: riyadh).logicalDay(picked).value == "2026-09-04",
                "the premise: the logical day is still yesterday at 02:00")
        #expect(LogicalDay(calendarDayOf: picked, in: riyadh).value == "2026-09-05")
    }

    @Test("A picker that opens on the logical day's date agrees with the row labelled Today, even after midnight")
    func pickerOpensOnTheLogicalDay() throws {
        let model = TimeModel(timeZone: riyadh)

        // 00:30 on the 5th: the calendar says the 5th, the person's day is
        // still the 4th. Opening on `Date()` would file a shift entered "for
        // today" under tomorrow.
        let afterMidnight = try #require(model.start(of: model.logicalDay(instant(2026, 9, 5, 0))))
        #expect(LogicalDay(calendarDayOf: afterMidnight, in: riyadh).value == "2026-09-04")

        let midday = try #require(model.start(of: model.logicalDay(instant(2026, 9, 5, 12))))
        #expect(LogicalDay(calendarDayOf: midday, in: riyadh).value == "2026-09-05")
    }

    @Test("Single-digit months and days are zero-padded and the digits are ASCII")
    func keyIsPaddedAscii() {
        #expect(LogicalDay(calendarDayOf: instant(2027, 1, 3, 12), in: riyadh).value == "2027-01-03")
    }
}
