import AppIntents
import AlmanacCore
import Foundation
import WidgetKit

/// The interactive controls Slice 12's widgets expose. Each intent runs in
/// the widget extension process and opens the *shared* database through
/// `AppGroupDatabase` — the same file the app uses — so a tap here is visible
/// in the app immediately, and vice versa.
///
/// After mutating state every intent asks WidgetKit for a timeline reload, so
/// the widget (and its sibling in the same bundle) re-reads the database
/// right away instead of waiting for its next scheduled refresh.

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log 250 ml of water"
    static let description = IntentDescription("Adds one large glass (250 ml) to today's water total.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let db = try AppGroupDatabase.open()
        // This is a write path the app never sees, so it goes through the same
        // fasting-aware log the app does: a glass during a dry fast ends it, and
        // one at iftar belongs to the night window (§7.2).
        try FastingAwareHydrationLog(db: db).log(HydrationLogDraft(amount: Milliliters(250), loggedAt: Date()))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct StartFastIntent: AppIntent {
    static let title: LocalizedStringResource = "Start fasting"
    static let description = IntentDescription("Starts a fasting session now.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let db = try AppGroupDatabase.open()
        let store = FastingSessionStore(db: db)
        // One fast at a time (`idx_fasting_session_one_active`). A second tap,
        // or a tap while today's religious fast runs, starts nothing rather than
        // failing on the index.
        if try store.activeSession() == nil {
            let logicalDay = TimeModel(timeZone: .current).logicalDay(Date()).value
            try store.start(
                FastingSessionDraft(startTimestamp: Date(), sessionType: .ifPlanned,
                                    timezoneOffset: TimeZone.current.secondsFromGMT() / 60),
                logicalDay: logicalDay)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct EndFastIntent: AppIntent {
    static let title: LocalizedStringResource = "End fast"
    static let description = IntentDescription("Ends the current intermittent fast.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let db = try AppGroupDatabase.open()
        let store = FastingSessionStore(db: db)
        // Intermittent only. A religious fast ends at Maghrib or at the first
        // thing logged after Fajr; a widget tap must not end it some other way.
        if let session = try store.activeIntermittentSession() {
            try store.endScheduled(id: session.id, at: Date())
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}