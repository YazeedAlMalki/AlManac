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
        let store = HydrationStore(db: db)
        try store.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: Date()))
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
        let logicalDay = TimeModel(timeZone: .current).logicalDay(Date()).value
        try store.start(
            FastingSessionDraft(startTimestamp: Date(), sessionType: .ifPlanned),
            logicalDay: logicalDay)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct EndFastIntent: AppIntent {
    static let title: LocalizedStringResource = "End fast"
    static let description = IntentDescription("Ends the current fasting session.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let db = try AppGroupDatabase.open()
        let store = FastingSessionStore(db: db)
        if let session = try store.activeSession() {
            try store.endScheduled(id: session.id, at: Date())
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}