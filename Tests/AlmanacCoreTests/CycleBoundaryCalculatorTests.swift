import Testing
import Foundation
@testable import AlmanacCore

@Suite("CycleBoundaryCalculator Tests")
struct CycleBoundaryCalculatorTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    @Test("A detected wake time becomes the cycle's open start")
    func detectedWakeStartsTheCycle() {
        let wake = Date(timeIntervalSince1970: 1_758_100_000) // 2026-09-17 08:26:40 UTC
        let window = CycleBoundaryCalculator.window(for: .detected(wake), now: wake, timeZone: riyadh)

        #expect(window.start == wake)
        #expect(window.end == nil)
    }

    @Test("A manual wake time is computed identically to a detected one")
    func manualWakeMatchesDetected() {
        let wake = Date(timeIntervalSince1970: 1_758_100_000)

        let detected = CycleBoundaryCalculator.window(for: .detected(wake), now: wake, timeZone: riyadh)
        let manual = CycleBoundaryCalculator.window(for: .manual(wake), now: wake, timeZone: riyadh)

        #expect(manual == detected)
    }

    @Test("Tracking off, before today's 23:59 rollover: window is yesterday 23:59 to today 23:59")
    func trackingOffBeforeRollover() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = riyadh
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 14, minute: 30))!
        let expectedStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 23, minute: 59))!
        let expectedEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 23, minute: 59))!

        let window = CycleBoundaryCalculator.window(for: .trackingOff, now: now, timeZone: riyadh)

        #expect(window.start == expectedStart)
        #expect(window.end == expectedEnd)
    }

    @Test("Tracking off, just after today's 23:59 rollover: window is today 23:59 to tomorrow 23:59")
    func trackingOffAfterRollover() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = riyadh
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 23, minute: 59, second: 30))!
        let expectedStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 23, minute: 59))!
        let expectedEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 23, minute: 59))!

        let window = CycleBoundaryCalculator.window(for: .trackingOff, now: now, timeZone: riyadh)

        #expect(window.start == expectedStart)
        #expect(window.end == expectedEnd)
    }

    @Test("Tracking off, exactly at the 23:59 rollover instant: belongs to the new window, not the old one")
    func trackingOffExactlyAtRollover() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = riyadh
        let rollover = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 23, minute: 59))!
        let expectedEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 23, minute: 59))!

        let window = CycleBoundaryCalculator.window(for: .trackingOff, now: rollover, timeZone: riyadh)

        #expect(window.start == rollover)
        #expect(window.end == expectedEnd)
    }
}
