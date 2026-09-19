import Testing
import Foundation
@testable import AlmanacCore

@Suite("DigestionStore Tests")
struct DigestionStoreTests {
    let db = try! TestDatabase()
    var store: DigestionStore { DigestionStore(db: db) }

    @Test("Log a bowel movement and read it back")
    func logAndReadBack() throws {
        let draft = BowelMovementDraft(
            timestamp: Date(), bristolType: .type4, color: "brown",
            bloodPresent: false, notes: "normal"
        )
        let id = try store.log(draft, logicalDay: "2026-09-19")

        let entry = try store.entry(id: id)
        #expect(entry?.bristolType == .type4)
        #expect(entry?.color == "brown")
        #expect(entry?.bloodPresent == false)
        #expect(entry?.logicalDay == "2026-09-19")
        #expect(entry?.notes == "normal")
    }

    @Test("Fetch bowel movements for a logical day")
    func logsForDay() throws {
        try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type3), logicalDay: "2026-09-19")
        try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type5), logicalDay: "2026-09-19")
        try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type1), logicalDay: "2026-09-18")

        #expect(try store.logs(for: "2026-09-19").count == 2)
        #expect(try store.logs(for: "2026-09-18").count == 1)
    }

    @Test("Blood presence and amount round-trip; escalation level starts unset")
    func bloodFlagsRoundTrip() throws {
        let id = try store.log(
            BowelMovementDraft(timestamp: Date(), bristolType: .type6, bloodPresent: true, bloodAmount: "streaks"),
            logicalDay: "2026-09-19"
        )
        let entry = try store.entry(id: id)
        #expect(entry?.bloodPresent == true)
        #expect(entry?.bloodAmount == "streaks")
        #expect(entry?.clinicianEscalationLevel == nil, "no classifier writes this column yet — clinician review is still pending")
    }
}
