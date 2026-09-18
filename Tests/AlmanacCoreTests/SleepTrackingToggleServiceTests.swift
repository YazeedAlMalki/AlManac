import Testing
import Foundation
@testable import AlmanacCore

@Suite("SleepTrackingToggleService Tests")
struct SleepTrackingToggleServiceTests {
    let db = try! TestDatabase()
    var settingsStore: SleepTrackingSettingsStore { SleepTrackingSettingsStore(db: db) }
    var cycleStore: ReadinessCycleStore { ReadinessCycleStore(db: db) }
    var sleepStore: SleepEpisodeStore { SleepEpisodeStore(db: db) }
    var service: SleepTrackingToggleService { SleepTrackingToggleService(db: db) }

    @Test("Disabling tracking with no open cycle just turns the setting off")
    func disableWithNoOpenCycle() throws {
        let toggleOff = Date(timeIntervalSince1970: 2_000_000)

        let result = try service.disableTracking(at: toggleOff, logicalDay: "2026-09-17")

        #expect(try settingsStore.isEnabled() == false)
        #expect(result.openCycleId == nil)
        #expect(result.sleepEpisodeIdPendingConfirmation == nil)
    }

    @Test("Disabling tracking mid-cycle preserves the open cycle's original boundary")
    func disableMidCyclePreservesBoundary() throws {
        let wake = Date(timeIntervalSince1970: 1_000_000)
        let cycleId = try cycleStore.createCycle(anchorDate: "2026-09-17",
                                                   primaryWakeTimestamp: wake,
                                                   cycleStartTimestamp: wake)
        let toggleOff = Date(timeIntervalSince1970: 1_050_000) // later the same day

        try service.disableTracking(at: toggleOff, logicalDay: "2026-09-17")

        let cycle = try cycleStore.cycle(id: cycleId)
        #expect(cycle?.anchorDate == "2026-09-17")
        #expect(cycle?.cycleStartTimestamp == wake, "the boundary must not shift to the toggle-off moment")
        #expect(cycle?.cycleEndTimestamp == nil, "the cycle stays open — only the next cycle changes rule")
    }

    @Test("Disabling tracking mid-cycle records the toggle-off instant as a pending sleep entry")
    func disableMidCycleRecordsPendingEntry() throws {
        try cycleStore.createCycle(anchorDate: "2026-09-17", primaryWakeTimestamp: Date(timeIntervalSince1970: 1_000_000))
        let toggleOff = Date(timeIntervalSince1970: 1_050_000)

        let result = try service.disableTracking(at: toggleOff, logicalDay: "2026-09-17")

        let episodeId = try #require(result.sleepEpisodeIdPendingConfirmation)
        let episode = try sleepStore.episode(id: episodeId)
        #expect(episode?.source == .manual)
        #expect(episode?.end == toggleOff)
        #expect(episode?.logicalDay == "2026-09-17")
    }
}
