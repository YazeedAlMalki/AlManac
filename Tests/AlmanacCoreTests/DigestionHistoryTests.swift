import Testing
import Foundation
@testable import AlmanacCore

/// The read side of BRD §6.3: what was recorded over a range, counted, and
/// never interpreted. Tested at `DigestionHistoryReader.history(endingOn:days:)`,
/// the one seam the history screen calls.
@Suite("Digestion history")
struct DigestionHistoryTests {
    let db = try! TestDatabase()
    var bowel: DigestionStore { DigestionStore(db: db) }
    var urination: UrinationStore { UrinationStore(db: db) }
    var reader: DigestionHistoryReader { DigestionHistoryReader(db: db) }

    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test("A seven-day range ends on the given day and includes it")
    func rangeIncludesTheLastDay() {
        let range = LogicalDayRange(endingOn: "2026-10-15", days: 7)
        #expect(range.from == "2026-10-09")
        #expect(range.to == "2026-10-16", "the range is half-open, so `to` is the day after")
    }

    @Test("A range crosses a month and a year boundary by the calendar")
    func rangeCrossesBoundaries() {
        #expect(LogicalDayRange(endingOn: "2026-03-01", days: 2).from == "2026-02-28")
        #expect(LogicalDayRange(endingOn: "2027-01-01", days: 1).to == "2027-01-02")
        #expect(LogicalDayRange(endingOn: "2026-12-31", days: 1).to == "2027-01-01")
    }

    @Test("Days are listed newest first, each with its own entries, and days with nothing are absent")
    func dayList() throws {
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-10T08:00:00Z"), bristolType: .type4),
                      logicalDay: "2026-10-10")
        try urination.log(UrinationDraft(timestamp: at("2026-10-12T09:00:00Z"), colorGrade: .grade3),
                          logicalDay: "2026-10-12")
        try urination.log(UrinationDraft(timestamp: at("2026-10-12T15:00:00Z"), colorGrade: .grade2),
                          logicalDay: "2026-10-12")

        let history = try reader.history(endingOn: "2026-10-15", days: 7)
        #expect(history.days.map(\.logicalDay) == ["2026-10-12", "2026-10-10"])
        #expect(history.days[0].urinations.count == 2)
        #expect(history.days[0].bowelMovements.isEmpty)
        #expect(history.days[1].bowelMovements.map(\.bristolType) == [.type4])
    }

    @Test("Entries outside the range are not counted")
    func outsideTheRange() throws {
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-08T08:00:00Z"), bristolType: .type1),
                      logicalDay: "2026-10-08")   // one day before a 7-day range ending the 15th
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-16T08:00:00Z"), bristolType: .type7),
                      logicalDay: "2026-10-16")   // the day after
        let history = try reader.history(endingOn: "2026-10-15", days: 7)
        #expect(history.bowelMovementCount == 0)
        #expect(history.days.isEmpty)
    }

    @Test("Bristol counts list all seven types in scale order, zeros included")
    func bristolCounts() throws {
        for type in [BristolType.type4, .type4, .type6] {
            try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T08:00:00Z"), bristolType: type),
                          logicalDay: "2026-10-14")
        }
        let history = try reader.history(endingOn: "2026-10-15", days: 7)
        #expect(history.bristolCounts.map(\.type) == BristolType.allCases)
        #expect(history.bristolCounts.map(\.count) == [0, 0, 0, 2, 0, 1, 0])
        #expect(history.bowelMovementCount == 3)
    }

    @Test("Colour counts are by name; an entry with no colour is counted as not recorded, never as brown")
    func colourCounts() throws {
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T08:00:00Z"), bristolType: .type4, color: "brown"),
                      logicalDay: "2026-10-14")
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T09:00:00Z"), bristolType: .type4, color: "brown"),
                      logicalDay: "2026-10-14")
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T10:00:00Z"), bristolType: .type4, color: "black"),
                      logicalDay: "2026-10-14")
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T11:00:00Z"), bristolType: .type4),
                      logicalDay: "2026-10-14")
        let history = try reader.history(endingOn: "2026-10-15", days: 7)

        let byKind = Dictionary(uniqueKeysWithValues: history.colourCounts.map { ($0.colour, $0.count) })
        #expect(byKind[.named(.brown)] == 2)
        #expect(byKind[.named(.black)] == 1)
        #expect(byKind[.notRecorded] == 1)
        #expect(byKind[.named(.green)] == nil, "only colours that occur are listed")
        // Every row carries words, never a colour alone (§6.20).
        #expect(history.colourCounts.allSatisfy { !$0.colour.displayName.isEmpty })
        #expect(DigestionColourTally.notRecorded.displayName == "Colour not recorded")
    }

    @Test("A colour spelled outside the six is kept as written, not folded into one of them")
    func unrecognisedColour() throws {
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T08:00:00Z"), bristolType: .type4, color: "grey"),
                      logicalDay: "2026-10-14")
        let history = try reader.history(endingOn: "2026-10-15", days: 7)
        #expect(history.colourCounts.map(\.colour) == [.other("grey")])
        #expect(DigestionColourTally.other("grey").displayName == "grey")
    }

    @Test("Urination counts list all eight grades in order, each with its number in the label")
    func gradeCounts() throws {
        for grade in [UrinationColorGrade.grade2, .grade2, .grade8] {
            try urination.log(UrinationDraft(timestamp: at("2026-10-14T08:00:00Z"), colorGrade: grade),
                              logicalDay: "2026-10-14")
        }
        let history = try reader.history(endingOn: "2026-10-15", days: 7)
        #expect(history.urinationGradeCounts.map(\.grade) == UrinationColorGrade.allCases)
        #expect(history.urinationGradeCounts.map(\.count) == [0, 2, 0, 0, 0, 0, 0, 1])
        #expect(history.urinationCount == 3)
    }

    @Test("Per-day counts cover every day of the range, zeros included, oldest first, for a chart")
    func dailyCounts() throws {
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T08:00:00Z"), bristolType: .type4),
                      logicalDay: "2026-10-14")
        try urination.log(UrinationDraft(timestamp: at("2026-10-15T08:00:00Z"), colorGrade: .grade1),
                          logicalDay: "2026-10-15")
        try urination.log(UrinationDraft(timestamp: at("2026-10-15T09:00:00Z"), colorGrade: .grade1),
                          logicalDay: "2026-10-15")
        let history = try reader.history(endingOn: "2026-10-15", days: 3)
        #expect(history.dailyCounts.map(\.logicalDay) == ["2026-10-13", "2026-10-14", "2026-10-15"])
        #expect(history.dailyCounts.map(\.bowelMovements) == [0, 1, 0])
        #expect(history.dailyCounts.map(\.urinations) == [0, 0, 2])
    }

    @Test("Nothing in a history interprets an entry: the escalation column stays as stored")
    func noInterpretation() throws {
        try bowel.log(BowelMovementDraft(timestamp: at("2026-10-14T08:00:00Z"), bristolType: .type7,
                                         color: "black", bloodPresent: true, bloodAmount: "large"),
                      logicalDay: "2026-10-14")
        let history = try reader.history(endingOn: "2026-10-15", days: 7)
        #expect(history.days.first?.bowelMovements.first?.clinicianEscalationLevel == nil)
    }
}
