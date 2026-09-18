import Testing
import Foundation
@testable import AlmanacCore

/// §14.2's per-type trigger arithmetic, exercised with hand-picked instants
/// so each assertion states its own expected offset rather than relying on
/// a shared fixture.
@Suite("NotificationTriggerTimeComputer Tests")
struct NotificationTriggerTimeComputerTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Suhoor fires 20 minutes before Fajr, only on a fast day")
    func suhoor() {
        let fajr = base
        #expect(NotificationTriggerTimeComputer.suhoorTrigger(fajr: fajr, isFastDay: true)
                == fajr.addingTimeInterval(-20 * 60))
        #expect(NotificationTriggerTimeComputer.suhoorTrigger(fajr: fajr, isFastDay: false) == nil)
    }

    @Test("Iftar fires exactly at Maghrib, only on a fast day")
    func iftar() {
        let maghrib = base
        #expect(NotificationTriggerTimeComputer.iftarTrigger(maghrib: maghrib, isFastDay: true) == maghrib)
        #expect(NotificationTriggerTimeComputer.iftarTrigger(maghrib: maghrib, isFastDay: false) == nil)
    }

    @Test("Water reminders land every interval from wake to 2 hours before the sleep window")
    func waterOrdinaryDay() {
        let wake = base                                    // "07:00"
        let sleepStart = wake.addingTimeInterval(16 * 3600) // "23:00" -> trimmed edge is "21:00"
        let times = NotificationTriggerTimeComputer.waterReminderTimes(
            expectedWakeTime: wake, expectedSleepWindowStart: sleepStart, intervalMinutes: 90)

        // Trimmed window is 14 hours (07:00-21:00); 90-minute steps from wake
        // land at +1.5h, +3h, ... every one up to and including the last one
        // at or before the trimmed edge.
        #expect(times.count == 9)
        #expect(times.first == wake.addingTimeInterval(90 * 60))
        #expect(times.last! <= sleepStart.addingTimeInterval(-2 * 3600))
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(b.timeIntervalSince(a) == 90 * 60)
        }
    }

    @Test("A trimmed window shorter than one interval produces no reminders")
    func waterShortDay() {
        let wake = base
        let sleepStart = wake.addingTimeInterval(3 * 3600) // trimmed edge is 1 hour after wake
        let times = NotificationTriggerTimeComputer.waterReminderTimes(
            expectedWakeTime: wake, expectedSleepWindowStart: sleepStart, intervalMinutes: 90)
        #expect(times.isEmpty)
    }

    @Test("A non-positive interval produces no reminders rather than looping forever")
    func waterZeroInterval() {
        let times = NotificationTriggerTimeComputer.waterReminderTimes(
            expectedWakeTime: base, expectedSleepWindowStart: base.addingTimeInterval(16 * 3600),
            intervalMinutes: 0)
        #expect(times.isEmpty)
    }

    @Test("Bedtime fires the default 30 minutes before the sleep window, or a given offset")
    func bedtime() {
        let sleepStart = base
        #expect(NotificationTriggerTimeComputer.bedtimeTrigger(expectedSleepWindowStart: sleepStart)
                == sleepStart.addingTimeInterval(-30 * 60))
        #expect(NotificationTriggerTimeComputer.bedtimeTrigger(expectedSleepWindowStart: sleepStart,
                                                                offsetMinutes: 45)
                == sleepStart.addingTimeInterval(-45 * 60))
    }

    @Test("Readiness prefers the primary episode's end over any estimate")
    func readinessPrefersPrimaryEpisode() {
        let episodeEnd = base
        let estimate = base.addingTimeInterval(3600)
        #expect(NotificationTriggerTimeComputer.readinessTrigger(
            primarySleepEpisodeEnd: episodeEnd, estimatedWakeTime: estimate) == episodeEnd)
    }

    @Test("Readiness falls back to the estimate when there is no primary episode")
    func readinessFallsBackToEstimate() {
        let estimate = base
        #expect(NotificationTriggerTimeComputer.readinessTrigger(
            primarySleepEpisodeEnd: nil, estimatedWakeTime: estimate) == estimate)
    }

    @Test("Readiness is nil when neither a primary episode nor an estimate is available")
    func readinessNilWhenNothingKnown() {
        #expect(NotificationTriggerTimeComputer.readinessTrigger(
            primarySleepEpisodeEnd: nil, estimatedWakeTime: nil) == nil)
    }

    @Test("Contextual hydration fires the default 60 minutes before the usual meal time, or a given lead time")
    func contextualHydration() {
        let usual = base
        #expect(NotificationTriggerTimeComputer.contextualHydrationTrigger(usualMealTime: usual)
                == usual.addingTimeInterval(-60 * 60))
        #expect(NotificationTriggerTimeComputer.contextualHydrationTrigger(usualMealTime: usual, leadMinutes: 30)
                == usual.addingTimeInterval(-30 * 60))
    }
}
