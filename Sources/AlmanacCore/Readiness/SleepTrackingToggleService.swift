import Foundation

/// Handles turning sleep tracking off mid-cycle (Ticket 1, decision 1.4).
///
/// The currently open readiness cycle's own boundary is left untouched —
/// only the *next* cycle should fall back to the calendar-day rule
/// (`CycleBoundaryCalculator.WakeSource.trackingOff`); that switch happens
/// naturally the next time a cycle is created after tracking is off, so
/// nothing here needs to touch `readiness_cycle` itself.
///
/// The toggle-off instant is recorded as the open cycle's sleep-ended time.
/// The schema has no "in-progress, end not yet known" shape for
/// `sleep_episode` (every row requires both a start and an end), so this
/// reuses the manual-wake-time slot (Ticket 1.2's `upsertManualWake`) as the
/// pending-confirmation entry — the same "we don't have a detected time, so
/// store our best guess and let the user correct it" idea either way.
public struct SleepTrackingToggleService: @unchecked Sendable {
    let db: Database
    private let settingsStore: SleepTrackingSettingsStore
    private let cycleStore: ReadinessCycleStore
    private let sleepStore: SleepEpisodeStore

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.settingsStore = SleepTrackingSettingsStore(db: db, clock: clock)
        self.cycleStore = ReadinessCycleStore(db: db, clock: clock)
        self.sleepStore = SleepEpisodeStore(db: db, clock: clock)
    }

    public struct DisableResult: Sendable, Hashable {
        /// The cycle that was open when tracking was turned off, if any.
        public let openCycleId: Int64?
        /// The sleep entry now awaiting the user's confirm/edit, if one was recorded.
        public let sleepEpisodeIdPendingConfirmation: Int64?
    }

    @discardableResult
    public func disableTracking(at timestamp: Date, logicalDay: String) throws -> DisableResult {
        try settingsStore.setEnabled(false)

        guard let openCycle = try cycleStore.openCycle() else {
            return DisableResult(openCycleId: nil, sleepEpisodeIdPendingConfirmation: nil)
        }

        let episodeId = try sleepStore.upsertManualWake(wakeTime: timestamp, logicalDay: logicalDay)
        return DisableResult(openCycleId: openCycle.id, sleepEpisodeIdPendingConfirmation: episodeId)
    }
}
