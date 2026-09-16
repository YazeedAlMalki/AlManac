import Testing
import Foundation
@testable import AlmanacCore

@Suite("ContextEventStore Tests")
struct ContextEventStoreTests {
    let db = try! TestDatabase()
    var store: ContextEventStore { ContextEventStore(db: db) }

    @Test("Log tags for a date and read them back")
    func logTags() throws {
        let id = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["travel_jet_lag", "poor_watch_wear"]))
        let event = try store.event(id: id)

        #expect(event?.date == "2026-09-16")
        #expect(event?.tags == ["travel_jet_lag", "poor_watch_wear"])
    }

    @Test("Fetch tags for a specific date")
    func eventForDate() throws {
        _ = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["illness"]))
        _ = try store.log(ContextEventDraft(date: "2026-09-17", tags: ["stress"]))

        let event = try store.event(for: "2026-09-16")
        #expect(event?.tags == ["illness"])
    }

    @Test("Update tags for an existing event")
    func updateTags() throws {
        let id = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["illness"]))
        try store.updateTags(id: id, to: ["illness", "sleep_interruption"])

        let event = try store.event(id: id)
        #expect(event?.tags == ["illness", "sleep_interruption"])
    }
}
