import Testing
import Foundation
@testable import AlmanacCore

@Suite("AdhanCalculator Tests")
struct AdhanCalculatorTests {
    private var riyadhTZ: TimeZone { TimeZone(identifier: "Asia/Riyadh")! }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        comps.timeZone = riyadhTZ
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private func hm(_ time: PrayerTime, in tz: TimeZone) -> (Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: time.timestamp)
        return (c.hour!, c.minute!)
    }

    @Test("Riyadh, Umm al-Qura, 2026-09-17 matches the published civil times within a few minutes")
    func riyadhAccuracy() throws {
        let times = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753,
            date: date(2026, 9, 17), timeZone: riyadhTZ, method: .ummAlQura))

        #expect(times.map(\.name) == ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"])

        // Reference: api.aladhan.com, method=4 (Umm al-Qura), same coordinates
        // and date: Fajr 04:22, Sunrise 05:40, Dhuhr 11:48, Asr 15:16,
        // Maghrib 17:55, Isha 19:25 (Asia/Riyadh). A few minutes' tolerance
        // covers differences between independent implementations of the same
        // solar-position formulas, not a loose "close enough" bar.
        let expected: [String: (Int, Int)] = [
            "fajr": (4, 22), "sunrise": (5, 40), "dhuhr": (11, 48),
            "asr": (15, 16), "maghrib": (17, 55), "isha": (19, 25)
        ]
        for time in times {
            let (h, m) = hm(time, in: riyadhTZ)
            let (eh, em) = expected[time.name]!
            let deltaMinutes = abs((h * 60 + m) - (eh * 60 + em))
            #expect(deltaMinutes <= 2, "\(time.name): got \(h):\(m), expected ~\(eh):\(em)")
        }
    }

    @Test("Prayer times fall in the expected order through the day")
    func chronologicalOrder() throws {
        let times = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753,
            date: date(2026, 9, 17), timeZone: riyadhTZ))
        let timestamps = times.map(\.timestamp)
        #expect(timestamps == timestamps.sorted())
    }

    @Test("Umm al-Qura Isha is exactly 90 minutes after Maghrib outside Ramadan")
    func ummAlQuraIshaInterval() throws {
        let times = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753,
            date: date(2026, 9, 17), timeZone: riyadhTZ, method: .ummAlQura))
        let maghrib = times.first { $0.name == "maghrib" }!.timestamp
        let isha = times.first { $0.name == "isha" }!.timestamp
        #expect(abs(isha.timeIntervalSince(maghrib) - 90 * 60) < 5)
    }

    @Test("A custom method uses the given angles, not Umm al-Qura's")
    func customMethodUsesGivenAngles() throws {
        let ummAlQura = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753,
            date: date(2026, 9, 17), timeZone: riyadhTZ, method: .ummAlQura))
        let custom = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753,
            date: date(2026, 9, 17), timeZone: riyadhTZ,
            method: .custom(fajrAngleDeg: 15, ishaAngleDeg: 15)))

        let ummAlQuraFajr = ummAlQura.first { $0.name == "fajr" }!.timestamp
        let customFajr = custom.first { $0.name == "fajr" }!.timestamp
        // A smaller Fajr angle (15° vs 18.5°) means the sun needs less time
        // to fall below the horizon before Fajr — a later Fajr.
        #expect(customFajr > ummAlQuraFajr)
    }

    @Test("Two different locations on the same date produce different times")
    func differentLocationsDiffer() throws {
        let riyadh = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753,
            date: date(2026, 9, 17), timeZone: riyadhTZ))
        let london = try #require(AdhanCalculator.prayerTimes(
            latitude: 51.5072, longitude: -0.1276,
            date: date(2026, 9, 17), timeZone: TimeZone(identifier: "Europe/London")!))

        let riyadhFajr = riyadh.first { $0.name == "fajr" }!.timestamp
        let londonFajr = london.first { $0.name == "fajr" }!.timestamp
        #expect(riyadhFajr != londonFajr)
    }
}
