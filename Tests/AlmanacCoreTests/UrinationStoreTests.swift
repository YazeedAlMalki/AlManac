import Testing
import Foundation
@testable import AlmanacCore

@Suite("UrinationStore Tests")
struct UrinationStoreTests {
    let db = try! TestDatabase()
    var store: UrinationStore { UrinationStore(db: db) }

    @Test("Log a urination entry and read it back")
    func logAndReadBack() throws {
        let id = try store.log(
            UrinationDraft(timestamp: Date(), colorGrade: .grade3, notes: "well hydrated"),
            logicalDay: "2026-09-19"
        )
        let entry = try store.entry(id: id)
        #expect(entry?.colorGrade == .grade3)
        #expect(entry?.logicalDay == "2026-09-19")
        #expect(entry?.notes == "well hydrated")
        #expect(entry?.clinicianEscalationLevel == nil)
    }

    @Test("Fetch urination entries for a logical day")
    func logsForDay() throws {
        try store.log(UrinationDraft(timestamp: Date(), colorGrade: .grade1), logicalDay: "2026-09-19")
        try store.log(UrinationDraft(timestamp: Date(), colorGrade: .grade8), logicalDay: "2026-09-19")
        try store.log(UrinationDraft(timestamp: Date(), colorGrade: .grade2), logicalDay: "2026-09-18")

        #expect(try store.logs(for: "2026-09-19").count == 2)
        #expect(try store.logs(for: "2026-09-18").count == 1)
    }
}
