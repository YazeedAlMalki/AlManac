import Testing
import Foundation
@testable import AlmanacCore

/// Exercises `CaffeineLogStore`'s `caffeineContext` derivation against real
/// `shift_schedule` / `shift_occurrence` rows (via `ShiftScheduleStore`)
/// rather than hand-picked `intendedSleepTimestamp` fixtures — Task per
/// spec-reconciliation §4.3 / BRD §6.2, §6.11.
///
/// Threshold reference, BRD §6.2 (boundaries are inclusive on the lower
/// edge — i.e. exactly 12h is `early`, exactly 8h is `normal`, exactly 3h
/// is `late`):
///   - early:     hoursBeforeIntendedSleep >= 12
///   - normal:    8 <= hoursBeforeIntendedSleep < 12
///   - late:      3 <= hoursBeforeIntendedSleep < 8
///   - very_late: hoursBeforeIntendedSleep < 3
///
/// The three main scenarios below use the same day-worker / night-shift /
/// transition-day stories as the task brief, with caffeine timing nudged so
/// each lands unambiguously inside the band its label names.
@Suite("Shift-aware caffeine context")
struct ShiftAwareCaffeineContextTests {
    let db = try! TestDatabase()
    var caffeineStore: CaffeineLogStore { CaffeineLogStore(db: db) }
    var shiftStore: ShiftScheduleStore { ShiftScheduleStore(db: db) }

    // MARK: - Three main scenarios

    @Test("Day worker: 7 AM coffee, 16h before 11 PM sleep -> early")
    func dayWorkerEarly() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Day shift"))
        let date = "2026-09-16"
        let coffeeTime = Date(timeIntervalSince1970: 1_700_000_000)   // "7 AM"
        let sleepTime = coffeeTime.addingTimeInterval(16 * 3600)       // "11 PM" same day

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .day,
            expectedSleepWindowStart: sleepTime))

        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
        #expect(intendedSleep == sleepTime)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: coffeeTime, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == "early")
        #expect((entry?.hoursBeforeIntendedSleep ?? 0).isApproximately(16))
    }

    @Test("Night shift: coffee 30 min before 8 AM sleep -> very_late")
    func nightShiftVeryLate() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Night shift"))
        let date = "2026-09-17"
        let sleepTime = Date(timeIntervalSince1970: 1_700_050_000)     // "8 AM"
        let coffeeTime = sleepTime.addingTimeInterval(-0.5 * 3600)     // "7:30 AM", just off-shift

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .night,
            shiftEndTime: sleepTime.addingTimeInterval(-2 * 3600),
            expectedSleepWindowStart: sleepTime))

        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: coffeeTime, drinkType: "coffee_latte", caffeineMg: 75,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == "very_late")
        #expect((entry?.hoursBeforeIntendedSleep ?? 99).isApproximately(0.5))
    }

    @Test("Transition day: tea 5h before 2 AM sleep -> late")
    func transitionDayLate() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Transition"))
        let date = "2026-09-18"
        let sleepTime = Date(timeIntervalSince1970: 1_700_100_000)     // "2 AM" next day
        let teaTime = sleepTime.addingTimeInterval(-5 * 3600)          // "9 PM", during shift

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .evening,
            expectedSleepWindowStart: sleepTime))

        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: teaTime, drinkType: "tea", caffeineMg: 30,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == "late")
        #expect((entry?.hoursBeforeIntendedSleep ?? 99).isApproximately(5))
    }

    // MARK: - Edge cases

    @Test("No shift occurrence for the date -> nil context, no crash")
    func noShiftSchedule() throws {
        let date = "2026-11-01"
        // No schedule, no occurrence logged for this date at all.
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
        #expect(intendedSleep == nil)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: Date(), drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == nil)
        #expect(entry?.hoursBeforeIntendedSleep == nil)
    }

    @Test("Shift occurrence exists but expectedSleepWindowStart is null -> nil context, no crash")
    func occurrenceWithoutSleepWindow() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "On call"))
        let date = "2026-11-02"

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .onCall,
            shiftStartTime: Date(timeIntervalSince1970: 1_700_200_000),
            shiftEndTime: Date(timeIntervalSince1970: 1_700_230_000)
            // expectedSleepWindowStart intentionally omitted.
        ))

        let occurrence = try shiftStore.occurrence(for: date)
        #expect(occurrence != nil)
        #expect(occurrence?.expectedSleepWindowStart == nil)

        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
        #expect(intendedSleep == nil)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: Date(timeIntervalSince1970: 1_700_201_000), drinkType: "coffee_black",
            caffeineMg: 95, intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == nil)
    }

    @Test("Multiple caffeine entries same shift day resolve to different contexts")
    func multipleContextsSameDay() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Day shift"))
        let date = "2026-09-19"
        let sleepTime = Date(timeIntervalSince1970: 1_700_300_000)     // "11 PM"

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .day,
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let morningCoffee = sleepTime.addingTimeInterval(-16 * 3600)   // early
        let eveningTea = sleepTime.addingTimeInterval(-9 * 3600)       // normal

        try caffeineStore.log(CaffeineLogDraft(
            timestamp: morningCoffee, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)
        try caffeineStore.log(CaffeineLogDraft(
            timestamp: eveningTea, drinkType: "tea", caffeineMg: 30,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let early = try caffeineStore.entries(context: "early", for: date)
        let normal = try caffeineStore.entries(context: "normal", for: date)
        #expect(early.count == 1)
        #expect(normal.count == 1)
        #expect(early.first?.drinkType == "coffee_black")
        #expect(normal.first?.drinkType == "tea")
    }

    @Test("Boundary: exactly 12 hours before sleep is early, not normal")
    func boundaryTwelveHours() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Day shift"))
        let date = "2026-09-20"
        let sleepTime = Date(timeIntervalSince1970: 1_700_400_000)
        let coffeeTime = sleepTime.addingTimeInterval(-12 * 3600)

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .day,
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: coffeeTime, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "early")
    }

    @Test("Boundary: exactly 8 hours before sleep is normal, not late")
    func boundaryEightHours() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Evening shift"))
        let date = "2026-09-21"
        let sleepTime = Date(timeIntervalSince1970: 1_700_500_000)
        let teaTime = sleepTime.addingTimeInterval(-8 * 3600)

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .evening,
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: teaTime, drinkType: "tea", caffeineMg: 30,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "normal")
    }

    @Test("Boundary: exactly 3 hours before sleep is late, not very_late")
    func boundaryThreeHours() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Night shift"))
        let date = "2026-09-22"
        let sleepTime = Date(timeIntervalSince1970: 1_700_550_000)
        let energyDrinkTime = sleepTime.addingTimeInterval(-3 * 3600)

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .night,
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: energyDrinkTime, drinkType: "energy_drink", caffeineMg: 120,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "late")
    }

    // MARK: - Additional realistic shift patterns

    @Test("Split shift: coffee between the two blocks resolves against the shared sleep window")
    func splitShiftContext() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Split shift"))
        let date = "2026-09-25"
        // Morning block 6-10, evening block 16-20, sleep at 23:00 same day.
        let shiftStart = Date(timeIntervalSince1970: 1_700_800_000)
        let sleepTime = shiftStart.addingTimeInterval(17 * 3600)
        let coffeeBetweenBlocks = shiftStart.addingTimeInterval(6 * 3600)  // mid-gap, 11h before sleep

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .split,
            shiftStartTime: shiftStart, shiftEndTime: sleepTime.addingTimeInterval(-3 * 3600),
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: coffeeBetweenBlocks, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "normal")
    }

    @Test("Rest day inside a rotation: its own, earlier sleep window is used, not the neighboring night shift's")
    func restDayWithinRotationContext() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "4-on 4-off nights"))
        let patternId = try shiftStore.createRecurrencePattern(ShiftRecurrencePatternDraft(
            scheduleId: scheduleId, patternType: "rotating", shiftSequence: "N,N,N,N,off,off,off,off",
            startDate: "2026-09-26"))

        let nightDate = "2026-09-26"
        let nightSleep = Date(timeIntervalSince1970: 1_700_900_000)     // "8 AM" after the night shift
        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: nightDate, shiftType: .night,
            expectedSleepWindowStart: nightSleep, recurrencePatternId: patternId))

        let restDate = "2026-09-30"
        let restSleep = Date(timeIntervalSince1970: 1_701_270_000)      // back to an ordinary "11 PM" bedtime
        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: restDate, shiftType: .rest,
            expectedSleepWindowStart: restSleep, recurrencePatternId: patternId))

        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: restDate)
        #expect(intendedSleep == restSleep)

        let afternoonCoffee = restSleep.addingTimeInterval(-9 * 3600)   // normal, on the rest day's own clock
        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: afternoonCoffee, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: restDate)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "normal")
    }

    @Test("Caffeine logged right at a shift's end boundary still resolves off the sleep window, not the shift clock")
    func caffeineAtShiftEndBoundary() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Night shift"))
        let date = "2026-10-01"
        let shiftEnd = Date(timeIntervalSince1970: 1_701_400_000)       // shift clocks out
        let sleepTime = shiftEnd.addingTimeInterval(4 * 3600)           // sleeps 4h after clocking out

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .night,
            shiftEndTime: shiftEnd, expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        // Coffee at the exact instant the shift ends — nowhere near the sleep window itself.
        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: shiftEnd, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == "late")
        #expect((entry?.hoursBeforeIntendedSleep ?? 99).isApproximately(4))
    }

    @Test("Recurring night-shift pattern: each occurrence day resolves its own sleep window")
    func recurringShiftContext() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "4-on 4-off nights"))
        let patternId = try shiftStore.createRecurrencePattern(ShiftRecurrencePatternDraft(
            scheduleId: scheduleId, patternType: "rotating", shiftSequence: "N,N,N,N,off,off,off,off",
            startDate: "2026-09-22"))

        let dates = ["2026-09-22", "2026-09-23", "2026-09-24"]
        var sleepTimes: [Date] = []

        for (i, date) in dates.enumerated() {
            let sleepTime = Date(timeIntervalSince1970: 1_700_600_000 + Double(i) * 86_400)
            sleepTimes.append(sleepTime)
            try shiftStore.logOccurrence(ShiftOccurrenceDraft(
                scheduleId: scheduleId, date: date, shiftType: .night,
                expectedSleepWindowStart: sleepTime, recurrencePatternId: patternId))
        }

        for (i, date) in dates.enumerated() {
            let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
            #expect(intendedSleep == sleepTimes[i])

            let coffeeTime = sleepTimes[i].addingTimeInterval(-0.25 * 3600)  // 15 min before
            let id = try caffeineStore.log(CaffeineLogDraft(
                timestamp: coffeeTime, drinkType: "energy_drink", caffeineMg: 120,
                intendedSleepTimestamp: intendedSleep), logicalDay: date)

            let entry = try caffeineStore.entry(id: id)
            #expect(entry?.caffeineContext == "very_late", "day \(i) (\(date)) should independently resolve to very_late")
        }
    }
}

private extension Double {
    func isApproximately(_ value: Double, tolerance: Double = 0.05) -> Bool {
        abs(self - value) <= tolerance
    }
}
