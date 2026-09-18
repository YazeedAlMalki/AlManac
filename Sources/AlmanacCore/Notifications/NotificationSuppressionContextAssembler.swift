import Foundation

/// Reads the real stores `NotificationSuppressionContext`'s own doc comment
/// names — `FastingSessionStore`, shift data (`ShiftScheduleStore`),
/// `ReadinessCycleStore`/`ReadinessRecordStore`, post-shift-sleep detection
/// (`SleepEpisodeStore`) — and assembles the five-axis context.
/// `NotificationSuppressionMatrix` itself never touches a store (its own
/// doc comment says so); this is the piece that closes that gap, per §14.1
/// step 2 ("load: current day type, active fasting session, today's shift,
/// prayer times, current time").
///
/// **Honest limitation, not an oversight:** `isDryFastActive`,
/// `isConfirmedIFActive` and `isReadinessAlreadyFinal` reflect the fasting
/// session and readiness cycle that are active *right now* in the
/// database — `FastingSessionStore.activeSession()` and
/// `ReadinessCycleStore.openCycle()` have no point-in-time variant, so
/// there is no way to ask "was a fast active at some other instant" from
/// the data this repo persists. `isNightShift` and `isPostShiftSleep` *can*
/// be evaluated for an arbitrary `instant`, since shift occurrences and
/// sleep episodes carry their own start/end timestamps — which is why this
/// type still takes one. This is not actually a gap in practice: §14.1's
/// architecture reruns the whole scheduling pass (and so this whole
/// assembly) on every log entry, shift change, and app launch, rather than
/// computing suppression once for a notification's future fire time and
/// trusting it to still hold — so `instant` should in practice always be
/// "now, or very close to it."
public struct NotificationSuppressionContextAssembler: @unchecked Sendable {
    private let timeModel: TimeModel
    private let fastingSessions: FastingSessionStore
    private let shifts: ShiftScheduleStore
    private let sleepEpisodes: SleepEpisodeStore
    private let readinessCycles: ReadinessCycleStore
    private let readinessRecords: ReadinessRecordStore

    public init(db: Database, timeModel: TimeModel) {
        self.timeModel = timeModel
        self.fastingSessions = FastingSessionStore(db: db)
        self.shifts = ShiftScheduleStore(db: db)
        self.sleepEpisodes = SleepEpisodeStore(db: db)
        self.readinessCycles = ReadinessCycleStore(db: db)
        self.readinessRecords = ReadinessRecordStore(db: db)
    }

    public func context(at instant: Date) throws -> NotificationSuppressionContext {
        let fasting = try fastingSessions.activeSession()
        let isConfirmedIF = fasting.map {
            $0.sessionType == .ifPlanned || $0.sessionType == .ifConfirmedSuggestion
        } ?? false

        return NotificationSuppressionContext(
            isDryFastActive: fasting?.isDryFast ?? false,
            isConfirmedIFActive: isConfirmedIF,
            isNightShift: try isWithinNightShift(at: instant),
            isPostShiftSleep: try isWithinPostShiftSleep(at: instant),
            isReadinessAlreadyFinal: try isOpenReadinessCycleFinal())
    }

    // MARK: - Private

    /// `shift_occurrence.date` is a plain calendar date, matching how every
    /// existing caller of `ShiftScheduleStore` addresses it (e.g. the
    /// `ShiftAwareCaffeineContext` tests use `"2026-09-17"` style dates, not
    /// `LogicalDay`'s 04:00-boundary label) — not the 4am-boundary logical
    /// day the rest of this file uses for sleep episodes. A night shift that
    /// started "yesterday" and is still running now is still filed under
    /// yesterday's date, so both today's and yesterday's occurrence are
    /// checked. `shiftStartTime`/`shiftEndTime` are full instants
    /// (Migration014), not times-of-day, so a plain range check is correct
    /// regardless of whether the shift crosses midnight.
    private func isWithinNightShift(at instant: Date) throws -> Bool {
        for date in [calendarDateString(instant), calendarDateString(instant.addingTimeInterval(-86400))] {
            guard let occurrence = try shifts.occurrence(for: date),
                  occurrence.shiftType == .night,
                  let start = occurrence.shiftStartTime, let end = occurrence.shiftEndTime else { continue }
            if instant >= start && instant <= end { return true }
        }
        return false
    }

    /// Mirrors the night-shift lookup, but keyed by logical day (04:00
    /// boundary) rather than calendar date, since that is what
    /// `SleepEpisodeStore.episodes(for:)` is keyed on — a post-shift episode
    /// classified under yesterday's logical day can still be running past
    /// the 04:00 boundary into today's.
    private func isWithinPostShiftSleep(at instant: Date) throws -> Bool {
        let today = timeModel.logicalDay(instant)
        var days = [today]
        if let yesterday = timeModel.day(before: today) { days.append(yesterday) }

        for day in days {
            let episodes = try sleepEpisodes.episodes(for: day.value)
            if episodes.contains(where: {
                $0.effectiveType == .postShift && instant >= $0.start && instant <= $0.end
            }) {
                return true
            }
        }
        return false
    }

    /// Whether the currently open readiness cycle already has a `.final`
    /// record. No open cycle at all (nothing started yet this cycle) is
    /// "not final" rather than an error — there is nothing to suppress
    /// against.
    private func isOpenReadinessCycleFinal() throws -> Bool {
        guard let cycle = try readinessCycles.openCycle() else { return false }
        return try readinessRecords.record(cycleId: cycle.id)?.state == .final
    }

    private func calendarDateString(_ instant: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeModel.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: instant)
    }
}
