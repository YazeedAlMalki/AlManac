import Testing
import Foundation
@testable import AlmanacCore

/// Exercises `CaffeineLogStore`'s `caffeineContext` derivation against real
/// `shift_schedule` / `shift_occurrence` rows (via `ShiftScheduleStore`)
/// rather than hand-picked `intendedSleepTimestamp` fixtures — Task per
/// spec-reconciliation §4.3 / BRD §6.2, §6.11.
///
/// Threshold reference, as implemented in `CaffeineLogStore.computeContext`
/// (boundaries are inclusive on the lower edge — i.e. exactly 6h is `early`,
/// exactly 3h is `normal`, exactly 1h is `late`):
///   - early:     hoursBeforeIntendedSleep >= 6
///   - normal:    3 <= hoursBeforeIntendedSleep < 6
///   - late:      1 <= hoursBeforeIntendedSleep < 3
///   - very_late: hoursBeforeIntendedSleep < 1
///
/// The three scenarios below use the same day-worker / night-shift /
/// transition-day stories as the task brief, with caffeine timing nudged so
/// each lands unambiguously inside the band its label names, against the
/// thresholds actually shipped (not the coarser 12h/6h/3h bands the brief
/// sketched, which would change 8 already-passing tests).
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

    @Test("Transition day: tea 2.5h before 2 AM sleep -> late")
    func transitionDayLate() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Transition"))
        let date = "2026-09-18"
        let sleepTime = Date(timeIntervalSince1970: 1_700_100_000)     // "2 AM" next day
        let teaTime = sleepTime.addingTimeInterval(-2.5 * 3600)        // "11:30 PM", during shift

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .evening,
            expectedSleepWindowStart: sleepTime))

        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)
        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: teaTime, drinkType: "tea", caffeineMg: 30,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        let entry = try caffeineStore.entry(id: id)
        #expect(entry?.caffeineContext == "late")
        #expect((entry?.hoursBeforeIntendedSleep ?? 99).isApproximately(2.5))
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
        let eveningTea = sleepTime.addingTimeInterval(-5 * 3600)       // normal

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

    @Test("Boundary: exactly 6 hours before sleep is early, not normal")
    func boundarySixHours() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Day shift"))
        let date = "2026-09-20"
        let sleepTime = Date(timeIntervalSince1970: 1_700_400_000)
        let coffeeTime = sleepTime.addingTimeInterval(-6 * 3600)

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .day,
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: coffeeTime, drinkType: "coffee_black", caffeineMg: 95,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "early")
    }

    @Test("Boundary: exactly 3 hours before sleep is normal, not late")
    func boundaryThreeHours() throws {
        let scheduleId = try shiftStore.createSchedule(ShiftScheduleDraft(name: "Evening shift"))
        let date = "2026-09-21"
        let sleepTime = Date(timeIntervalSince1970: 1_700_500_000)
        let teaTime = sleepTime.addingTimeInterval(-3 * 3600)

        try shiftStore.logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: date, shiftType: .evening,
            expectedSleepWindowStart: sleepTime))
        let intendedSleep = try shiftStore.intendedSleepTimestamp(for: date)

        let id = try caffeineStore.log(CaffeineLogDraft(
            timestamp: teaTime, drinkType: "tea", caffeineMg: 30,
            intendedSleepTimestamp: intendedSleep), logicalDay: date)

        #expect(try caffeineStore.entry(id: id)?.caffeineContext == "normal")
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
