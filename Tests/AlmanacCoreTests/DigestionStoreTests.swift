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

    @Test("A range query is half-open over days, newest first")
    func logsInRange() throws {
        let earlier = try store.log(BowelMovementDraft(timestamp: iso("2026-09-18T08:00:00Z"), bristolType: .type3),
                                    logicalDay: "2026-09-18")
        let later = try store.log(BowelMovementDraft(timestamp: iso("2026-09-20T21:00:00Z"), bristolType: .type5),
                                  logicalDay: "2026-09-20")
        let sameDayEarlier = try store.log(BowelMovementDraft(timestamp: iso("2026-09-20T06:00:00Z"), bristolType: .type1),
                                           logicalDay: "2026-09-20")

        // `to` is exclusive, so the 20th is excluded and the 18th is included.
        #expect(try store.logs(from: "2026-09-18", to: "2026-09-20").map { $0.id } == [earlier])

        // Ordering is by timestamp, not by day: the later 20th comes first even
        // though both entries share a logical day and were inserted in the
        // opposite order.
        #expect(try store.logs(from: "2026-09-18", to: "2026-09-21").map { $0.id }
                == [later, sameDayEarlier, earlier])
    }

    @Test("delete removes an entry outright")
    func deleteRemovesEntry() throws {
        let id = try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type4),
                               logicalDay: "2026-09-19")
        try store.delete(id: id)
        #expect(try store.entry(id: id) == nil)
        #expect(try store.logs(for: "2026-09-19").isEmpty)
    }

    // MARK: - Vocabulary

    @Test("Every Bristol type has a distinct name and a summary")
    func bristolNamesAreDistinct() {
        let names = BristolType.allCases.map { $0.displayName }
        #expect(Set(names).count == BristolType.allCases.count, "two types share a name: \(names)")
        #expect(BristolType.allCases.allSatisfy { !$0.summary.isEmpty })
    }

    @Test("The Bristol label carries both the number and the description")
    func bristolAccessibilityCarriesBoth() {
        // BRD §6.3: "never rely on colour alone; numeric grades + text +
        // VoiceOver". A label with only one half is only half the rule.
        for type in BristolType.allCases {
            #expect(type.accessibilityLabel.contains("Type \(type.rawValue)"))
            #expect(type.accessibilityLabel.contains(type.displayName))
        }
    }

    @Test("Stool colour is exactly BRD §6.3's six, and its raw values are what the column stores")
    func stoolColorVocabulary() {
        #expect(StoolColor.allCases.map { $0.rawValue }
                == ["brown", "pale", "yellow", "green", "black", "red"])
        // The six round-trip through the column's own spelling, so a value read
        // back out of the database is a colour the picker can name.
        for color in StoolColor.allCases {
            #expect(StoolColor(rawValue: color.rawValue) == color)
        }
    }

    @Test("Urgency round-trips as whatever a caller passes, because it has no scale of its own")
    func urgencyIsUnscored() throws {
        // `urgency` is a bare `Int?` and neither the BRD nor the technical spec
        // says what its numbers mean. The store therefore stores a number and
        // makes no claim about it, and the digest screen leaves it nil — a
        // picker here would have to invent the scale. This test pins the
        // round-trip so that a future scale can be added without changing the
        // column's meaning under it.
        let id = try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type4, urgency: 3),
                               logicalDay: "2026-09-19")
        #expect(try store.entry(id: id)?.urgency == 3)
    }

    private func iso(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)!
    }
}
