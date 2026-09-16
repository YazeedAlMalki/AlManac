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
}
