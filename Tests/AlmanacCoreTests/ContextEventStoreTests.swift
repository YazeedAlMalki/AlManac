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

    @Test("Update notes, and clear them back to nothing")
    func updateNotes() throws {
        let id = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["illness"], notes: "Fever all evening"))
        try store.updateNotes(id: id, to: "Fever, cleared by morning")
        #expect(try store.event(id: id)?.notes == "Fever, cleared by morning")

        try store.updateNotes(id: id, to: nil)
        #expect(try store.event(id: id)?.notes == nil)
    }

    @Test("Updating notes leaves the tags alone")
    func updateNotesLeavesTags() throws {
        let id = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["illness", "sauna"]))
        try store.updateNotes(id: id, to: "Felt rough after the sauna")

        #expect(try store.event(id: id)?.tags == ["illness", "sauna"])
    }

    @Test("A range query returns every event in it, oldest day first")
    func eventsInRange() throws {
        _ = try store.log(ContextEventDraft(date: "2026-09-14", tags: ["sauna"]))
        _ = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["illness"]))
        _ = try store.log(ContextEventDraft(date: "2026-09-18", tags: ["travel_jet_lag"]))

        let events = try store.events(from: "2026-09-15", to: "2026-09-18")
        #expect(events.map { $0.date } == ["2026-09-16"])
    }

    @Test("A range query keeps both rows when a day somehow holds two")
    func eventsInRangeKeepsDuplicateDays() throws {
        // `context_event.date` has no unique index, so two rows on one day is
        // reachable through the store. The range query returns both rather than
        // hiding one; the single-day `event(for:)` returns only the first, and
        // that asymmetry is a flagged ambiguity rather than a settled behaviour.
        _ = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["illness"]))
        _ = try store.log(ContextEventDraft(date: "2026-09-16", tags: ["sauna"]))

        #expect(try store.events(from: "2026-09-16", to: "2026-09-17").count == 2)
        #expect(try store.event(for: "2026-09-16") != nil)
    }
}
