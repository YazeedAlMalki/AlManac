import XCTest
@testable import AlmanacCore

final class TimelineTests: XCTestCase {

    // 9. Both domains appear in one merged, ordered timeline.
    func testBothDomainsAppearInTheCombinedTimeline() async throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))  // 2026-02-25
        let catalog = LabCatalogStore(db: db, clock: clock)
        try LabCatalogSeed.seed(into: catalog)
        let lab = LabStore(db: db, clock: clock)
        let samples = HealthSampleStore(db: db, healthDomain: .bodyMass, clock: clock)

        var content = LabRevisionContent()
        content.lifecycle = .final
        content.valueType = .quantitative
        content.numericValue = 42
        content.unitText = "ng/mL"
        content.sourceAnalyteText = "Ferritin"
        content.sourceValueText = "42"
        var draft = LabObservationDraft()
        draft.collectedAt = PartialDateTime(text: "2026-02-25T08:10:00Z", precision: .instant)
        try lab.record(draft, content: content)

        let provider = FakeHealthProvider()
        try await provider.requestAuthorisation(for: [.bodyMass])
        provider.enqueue(HealthChangeSet(
            added: [HealthSample(externalID: "w1", domain: .bodyMass,
                                 start: Date(timeIntervalSince1970: 1_771_995_000),
                                 end: Date(timeIntervalSince1970: 1_771_995_000),
                                 value: 81.2, unit: "kg", sourceName: "Withings")],
            deletedExternalIDs: [], nextAnchor: [1]), for: .bodyMass)
        try await HealthSyncService(db: db, provider: provider, writer: samples,
                                    healthDomain: .bodyMass, clock: clock).syncOnce()

        let timeline = Timeline(providers: [lab, samples])
        let entries = try timeline.entries(from: "2026-02-01", to: "2026-03-01")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.domain)), Set(["laboratory", "bodyMass"]))
        XCTAssertEqual(entries[0].domain, "bodyMass", "06:30 precedes 08:10")
        XCTAssertEqual(entries[1].domain, "laboratory")
        XCTAssertEqual(entries[1].title, "Ferritin")
        XCTAssertEqual(entries[1].value, .quantity(text: "42", unit: "ng/mL"))
        XCTAssertTrue(entries.allSatisfy { $0.basis == .occurrence })

        // Reversing provider order must not change the result.
        let reversed = try Timeline(providers: [samples, lab])
            .entries(from: "2026-02-01", to: "2026-03-01")
        XCTAssertEqual(entries, reversed)
    }

    // An entry with no occurrence and no report time falls back to when it was
    // entered, and says so rather than passing as an occurrence.
    func testEntryDateFallbackIsDistinguished() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        try LabCatalogSeed.seed(into: LabCatalogStore(db: db, clock: clock))
        let lab = LabStore(db: db, clock: clock)

        var dated = LabRevisionContent()
        dated.valueType = .quantitative
        dated.numericValue = 14.2
        dated.sourceAnalyteText = "HGB"
        dated.sourceValueText = "14.2"
        var datedDraft = LabObservationDraft()
        datedDraft.collectedAt = PartialDateTime(text: "2026-02-25T09:00:00Z", precision: .instant)
        try lab.record(datedDraft, content: dated)

        var undated = dated
        undated.sourceAnalyteText = "Ferritin"
        try lab.record(LabObservationDraft(), content: undated)

        let entries = try lab.entries(from: "2026-02-01", to: "2026-03-01")
        XCTAssertEqual(entries.count, 2)
        // Titles come from the catalog once matched, so "HGB" displays as its
        // canonical name — which is itself worth pinning.
        let bases = Dictionary(uniqueKeysWithValues: entries.map { ($0.title, $0.basis) })
        XCTAssertEqual(bases["Haemoglobin"], .occurrence)
        XCTAssertEqual(bases["Ferritin"], .recorded)
    }

    // C: the timeline returns the current revision, and the superseded one is
    // still reachable through the module. Without this the "current by default"
    // claim rests on a WHERE clause nothing exercises after an amendment.
    func testTimelineShowsCurrentRevisionAndHistoryRemainsReachable() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        try LabCatalogSeed.seed(into: LabCatalogStore(db: db, clock: clock))
        let lab = LabStore(db: db, clock: clock)

        var draft = LabObservationDraft()
        draft.sourceSystem = "lab-a"
        draft.sourceObservationID = "K-1"
        draft.collectedAt = PartialDateTime(text: "2026-02-25T08:10:00Z", precision: .instant)

        var original = LabRevisionContent()
        original.lifecycle = .final
        original.valueType = .quantitative
        original.numericValue = 4.1
        original.unitText = "mmol/L"
        original.sourceAnalyteText = "Potassium"
        original.sourceValueText = "4.1"
        original.contentOrigin = .sourceExtraction
        original.actor = "import:lab-a"
        let created = try lab.record(draft, content: original)

        var amended = original
        amended.lifecycle = .corrected
        amended.numericValue = 4.6
        amended.sourceValueText = "4.6"
        try lab.record(draft, content: amended)

        let entries = try lab.entries(from: "2026-02-01", to: "2026-03-01")
        XCTAssertEqual(entries.count, 1, "an amendment must not produce a second timeline entry")
        XCTAssertEqual(entries[0].value, .quantity(text: "4.6", unit: "mmol/L"))
        XCTAssertEqual(entries[0].lifecycle, "corrected")

        let history = try lab.revisions(of: created.observationID)
        XCTAssertEqual(history.map(\.content.sourceValueText), ["4.1", "4.6"])
        XCTAssertEqual(history.map(\.isCurrent), [false, true])
    }

    func testCoarsePrecisionSortsAtTheStartOfItsSpan() throws {
        let year = PartialDateTime(text: "2019", precision: .year)
        let month = PartialDateTime(text: "2019-03", precision: .month)
        let day = PartialDateTime(text: "2019-03-14", precision: .day)
        let instant = PartialDateTime(text: "2019-03-14T08:10:00Z", precision: .instant)
        XCTAssertEqual([instant, day, month, year].sorted(), [year, month, day, instant])
        XCTAssertTrue(day < instant)
        XCTAssertTrue(PartialDateTime.unknown > instant, "unknown sorts last")
    }
}
