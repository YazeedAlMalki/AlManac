import Testing
import Foundation
@testable import AlmanacCore

/// The water half of the owner's dry-fast rule (2026-09-29): logging a drink
/// during a religious dry fast ends it, because a dry fast that was drunk from
/// is not a fast that was kept. `FastingSessionStore.recordIntake` owns the
/// rule; this is the same wrapper shape as `FastingAwareNutritionLog`, so
/// Hydration does not have to know Fasting exists.
@Suite("FastingAwareHydrationLog Tests")
struct FastingAwareHydrationLogTests {
    let db = try! TestDatabase()
    let clock = FixedClock(Date(timeIntervalSince1970: 2_000_000))
    var bridge: FastingAwareHydrationLog { FastingAwareHydrationLog(db: db, clock: clock) }
    var sessions: FastingSessionStore { FastingSessionStore(db: db, clock: clock) }

    private let fajr = Date(timeIntervalSince1970: 1_000_000)

    private func startReligiousDryFast() throws -> Int64 {
        try sessions.start(
            FastingSessionDraft(startTimestamp: fajr, sessionType: .religious, isDryFast: true),
            logicalDay: "2026-09-16")
    }

    @Test("Logging water during a religious dry fast ends it")
    func waterEndsActiveDryFast() throws {
        let id = try startReligiousDryFast()
        let at = fajr.addingTimeInterval(7 * 3600)

        let outcome = try bridge.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at))

        #expect(outcome.fastingOutcome == .ended(sessionId: id, durationMinutes: 420))
        #expect(try sessions.session(id: id)?.isActive == false)
    }

    @Test("The hydration entry itself is still recorded")
    func hydrationIsStillLogged() throws {
        _ = try startReligiousDryFast()
        let at = fajr.addingTimeInterval(7 * 3600)

        let outcome = try bridge.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at))

        // Breaking a fast must never cost the user their water log — the fast
        // is a claim about the fast, not a veto on the write. The range is
        // half-open (`logged_at < end`), so it needs a real end, not the same
        // instant twice.
        let formatter = ISO8601DateFormatter()
        let total = try HydrationStore(db: db, clock: clock)
            .total(from: formatter.string(from: at), to: formatter.string(from: at.addingTimeInterval(60)))
        #expect(total == Milliliters(250))
        #expect(!outcome.hydrationLogID.isEmpty)
    }

    @Test("Water during an intermittent fast is left alone")
    func waterDoesNotEndIntermittentFast() throws {
        let id = try sessions.start(
            FastingSessionDraft(startTimestamp: fajr, sessionType: .ifConfirmedSuggestion),
            logicalDay: "2026-09-16")
        let at = fajr.addingTimeInterval(7 * 3600)

        let outcome = try bridge.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at))

        #expect(outcome.fastingOutcome == .noOp)
        #expect(try sessions.session(id: id)?.isActive == true)
    }

    @Test("Logging water with no fast running changes nothing")
    func noActiveFastIsANoOp() throws {
        let at = fajr.addingTimeInterval(7 * 3600)

        let outcome = try bridge.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at))

        #expect(outcome.fastingOutcome == .noOp)
        #expect(try sessions.activeSession() == nil)
    }
}
