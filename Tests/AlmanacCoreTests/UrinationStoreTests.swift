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

    @Test("A range query is half-open over days, newest first")
    func logsInRange() throws {
        let earlier = try store.log(UrinationDraft(timestamp: iso("2026-09-18T06:00:00Z"), colorGrade: .grade2),
                                    logicalDay: "2026-09-18")
        let later = try store.log(UrinationDraft(timestamp: iso("2026-09-20T22:00:00Z"), colorGrade: .grade7),
                                  logicalDay: "2026-09-20")
        let sameDayEarlier = try store.log(UrinationDraft(timestamp: iso("2026-09-20T07:00:00Z"), colorGrade: .grade1),
                                           logicalDay: "2026-09-20")

        #expect(try store.logs(from: "2026-09-18", to: "2026-09-20").map { $0.id } == [earlier])
        #expect(try store.logs(from: "2026-09-18", to: "2026-09-21").map { $0.id }
                == [later, sameDayEarlier, earlier])
    }

    @Test("delete removes an entry outright")
    func deleteRemovesEntry() throws {
        let id = try store.log(UrinationDraft(timestamp: Date(), colorGrade: .grade4), logicalDay: "2026-09-19")
        try store.delete(id: id)
        #expect(try store.entry(id: id) == nil)
        #expect(try store.logs(for: "2026-09-19").isEmpty)
    }

    // MARK: - Vocabulary

    @Test("Only the two ends of the chart are named; the middle stays a number")
    func onlyTheEndsAreNamed() {
        // BRD §6.3 asks for an 8-level chart but does not give it. The only two
        // points this repository can state are the ones the type's own doc
        // comment states: 1 is pale, 8 is dark brown. A plausible-sounding
        // ladder of eight descriptions would be eight clinical claims invented
        // here, a clause earlier than the clinician review that §6.3's own
        // advisory section is held back for.
        #expect(UrinationColorGrade.grade1.displayName == "Grade 1 — pale")
        #expect(UrinationColorGrade.grade8.displayName == "Grade 8 — dark brown")
        for grade in UrinationColorGrade.allCases where grade != .grade1 && grade != .grade8 {
            #expect(grade.displayName == "Grade \(grade.rawValue)",
                    "grade \(grade.rawValue) has been given a description it was never given")
        }
    }

    @Test("The grade label carries the number, the scale, and the name")
    func gradeAccessibilityCarriesAllThree() {
        // BRD §6.3: "never rely on colour alone; numeric grades + text +
        // VoiceOver".
        for grade in UrinationColorGrade.allCases {
            let label = grade.accessibilityLabel
            #expect(label.contains("\(grade.rawValue)"))
            #expect(label.contains("of 8"))
            #expect(label.contains(grade.displayName))
        }
    }

    @Test("Every grade has a distinct name")
    func gradeNamesAreDistinct() {
        let names = UrinationColorGrade.allCases.map { $0.displayName }
        #expect(Set(names).count == UrinationColorGrade.allCases.count, "grades share a name: \(names)")
    }

    private func iso(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)!
    }
}
