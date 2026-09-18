import Testing
import Foundation
@testable import AlmanacCore

@Suite("ReadinessCycleStore Tests")
struct ReadinessCycleStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    @Test("Create a cycle and read it back by anchor date")
    func createAndReadByAnchorDate() throws {
        let store = ReadinessCycleStore(db: db)
        let id = try store.createCycle(anchorDate: "2026-09-17",
                                        primaryWakeTimestamp: Date(timeIntervalSince1970: 1000),
                                        cycleStartTimestamp: Date(timeIntervalSince1970: 1000))

        let cycle = try store.cycle(anchorDate: "2026-09-17")
        #expect(cycle?.id == id)
        #expect(cycle?.anchorDate == "2026-09-17")
        #expect(cycle?.cycleEndTimestamp == nil)
    }

    @Test("A cycle with no cycleEndTimestamp is the open cycle")
    func openCycleIsTheOneWithNoEnd() throws {
        let store = ReadinessCycleStore(db: db)
        let closedId = try store.createCycle(anchorDate: "2026-09-16")
        try db.run("UPDATE readiness_cycle SET cycleEndTimestamp = ? WHERE id = ?;",
                    [.text("2026-09-17T04:00:00Z"), .integer(closedId)])
        let openId = try store.createCycle(anchorDate: "2026-09-17")

        let open = try store.openCycle()
        #expect(open?.id == openId)
    }

    @Test("No open cycle returns nil rather than the most recent closed one")
    func noOpenCycleIsNil() throws {
        let store = ReadinessCycleStore(db: db)
        let closedId = try store.createCycle(anchorDate: "2026-09-16")
        try db.run("UPDATE readiness_cycle SET cycleEndTimestamp = ? WHERE id = ?;",
                    [.text("2026-09-17T04:00:00Z"), .integer(closedId)])

        #expect(try store.openCycle() == nil)
    }

    @Test("ensureCycle returns the existing cycle for an anchor date instead of duplicating it")
    func ensureCycleReusesExisting() throws {
        let store = ReadinessCycleStore(db: db)
        let first = try store.createCycle(anchorDate: "2026-09-17")
        let ensured = try store.ensureCycle(anchorDate: "2026-09-17", at: Date())

        #expect(ensured == first)
        #expect(try db.query("SELECT COUNT(*) as n FROM readiness_cycle;").first?.int("n") == 1)
    }

    @Test("ensureCycle creates a bare cycle when none exists for the anchor date")
    func ensureCycleCreatesWhenMissing() throws {
        let store = ReadinessCycleStore(db: db)
        let at = Date(timeIntervalSince1970: 2000)
        let id = try store.ensureCycle(anchorDate: "2026-09-17", at: at)

        let cycle = try store.cycle(id: id)
        #expect(cycle?.anchorDate == "2026-09-17")
        #expect(cycle?.primarySleepEpisodeId == nil)
    }

    @Test("cycle(id:) returns nil for an id that does not exist")
    func cycleByIdMissing() throws {
        let store = ReadinessCycleStore(db: db)
        #expect(try store.cycle(id: 999) == nil)
    }

    @Test("linkPrimaryEpisode backfills a bare cycle without duplicating it")
    func linkPrimaryEpisodeBackfillsBareCycle() throws {
        let store = ReadinessCycleStore(db: db)
        let id = try store.createCycle(anchorDate: "2026-09-17")
        let wake = Date(timeIntervalSince1970: 1_000_000)
        // primarySleepEpisodeId is a real FK into sleep_episode — a fabricated
        // id would fail the constraint, so a genuine row is needed here.
        let episode = SleepEpisode(start: wake.addingTimeInterval(-3600), end: wake,
                                    type: .primary, source: .healthkit, asleepMinutes: 60)
        let episodeId = try SleepEpisodeStore(db: db).upsert(episode, timezoneOffset: 0, logicalDay: "2026-09-17")

        let updated = try store.linkPrimaryEpisode(id: id, primarySleepEpisodeId: episodeId,
                                                     primaryWakeTimestamp: wake, cycleStartTimestamp: wake)

        #expect(updated)
        let cycle = try store.cycle(id: id)
        #expect(cycle?.primarySleepEpisodeId == episodeId)
        #expect(cycle?.primaryWakeTimestamp == wake)
        #expect(cycle?.cycleStartTimestamp == wake)
        #expect(try db.query("SELECT COUNT(*) as n FROM readiness_cycle;").first?.int("n") == 1)
    }

    @Test("linkPrimaryEpisode returns false for an id that does not exist")
    func linkPrimaryEpisodeMissingId() throws {
        let store = ReadinessCycleStore(db: db)
        // A real episode id is still needed here — the FK is checked before
        // the WHERE id = ? even finds no matching row.
        let episode = SleepEpisode(start: Date(timeIntervalSince1970: 900_000), end: Date(timeIntervalSince1970: 1_000_000),
                                    type: .primary, source: .healthkit, asleepMinutes: 60)
        let episodeId = try SleepEpisodeStore(db: db).upsert(episode, timezoneOffset: 0, logicalDay: "2026-09-17")

        let updated = try store.linkPrimaryEpisode(id: 999, primarySleepEpisodeId: episodeId,
                                                     primaryWakeTimestamp: Date(), cycleStartTimestamp: Date())
        #expect(!updated)
    }

    @Test("closeCycle sets cycleEndTimestamp and the cycle is no longer open")
    func closeCycleSetsEnd() throws {
        let store = ReadinessCycleStore(db: db)
        let wake = Date(timeIntervalSince1970: 1_000_000)
        let id = try store.createCycle(anchorDate: "2026-09-17", primaryWakeTimestamp: wake,
                                        cycleStartTimestamp: wake)
        let nextWake = Date(timeIntervalSince1970: 1_090_000)

        let closed = try store.closeCycle(id: id, cycleEndTimestamp: nextWake)

        #expect(closed)
        #expect(try store.cycle(id: id)?.cycleEndTimestamp == nextWake)
        #expect(try store.openCycle() == nil)
    }

    @Test("closeCycle returns false for an id that does not exist")
    func closeCycleMissingId() throws {
        let store = ReadinessCycleStore(db: db)
        #expect(!(try store.closeCycle(id: 999, cycleEndTimestamp: Date())))
    }

    @Test("closeCycle with nil reopens a previously-closed cycle")
    func closeCycleNilReopens() throws {
        let store = ReadinessCycleStore(db: db)
        let wake = Date(timeIntervalSince1970: 1_000_000)
        let id = try store.createCycle(anchorDate: "2026-09-17", primaryWakeTimestamp: wake,
                                        cycleStartTimestamp: wake)
        try store.closeCycle(id: id, cycleEndTimestamp: Date(timeIntervalSince1970: 1_090_000))

        let reopened = try store.closeCycle(id: id, cycleEndTimestamp: nil)

        #expect(reopened)
        #expect(try store.cycle(id: id)?.cycleEndTimestamp == nil)
        #expect(try store.openCycle()?.id == id)
    }

    @Test("createCycle attaches a circadianContextId when given one")
    func createCycleAttachesCircadianContextId() throws {
        let store = ReadinessCycleStore(db: db)
        // circadianContextId is a real FK into circadian_context, same FK
        // discipline as primarySleepEpisodeId elsewhere in this file.
        try db.run("""
        INSERT INTO circadian_context (date, contextType, createdAt) VALUES (?, ?, ?);
        """, [.text("2026-09-17"), .text("unknown"), .text("2026-09-17T00:00:00Z")])
        let contextId = try db.query("SELECT last_insert_rowid() as id;").first?.int("id")

        let id = try store.createCycle(anchorDate: "2026-09-17", circadianContextId: contextId)

        #expect(try store.cycle(id: id)?.circadianContextId == contextId)
    }

    @Test("allCycles returns every row, including bare ones")
    func allCyclesReturnsEveryRow() throws {
        let store = ReadinessCycleStore(db: db)
        _ = try store.createCycle(anchorDate: "2026-09-16")
        _ = try store.createCycle(anchorDate: "2026-09-17")

        let all = try store.allCycles()

        #expect(all.count == 2)
        #expect(Set(all.map(\.anchorDate)) == ["2026-09-16", "2026-09-17"])
    }
}
