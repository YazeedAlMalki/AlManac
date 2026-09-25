import XCTest
@testable import AlmanacCore

private struct TestTimelineProvider: TimelineProviding {
    let domain: String
    let values: [TimelineEntry]

    func entries(from: String, to: String) throws -> [TimelineEntry] { values }
}

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

    func testTrackingTimelineKeepsModuleValuesInOccurrenceOrder() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let lab = LabStore(db: db, clock: clock)
        try LabCatalogSeed.seed(into: LabCatalogStore(db: db, clock: clock))

        let sampleStore = HealthSampleStore(db: db, healthDomain: .bodyMass, clock: clock)
        let sample = HealthSample(externalID: "timeline-weight", domain: .bodyMass,
                                  start: Date(timeIntervalSince1970: 1_771_995_000),
                                  end: Date(timeIntervalSince1970: 1_771_995_000),
                                  value: 81.2, unit: "kg")
        try sampleStore.apply(HealthChangeSet(added: [sample], deletedExternalIDs: [], nextAnchor: nil), in: db)

        var content = LabRevisionContent()
        content.valueType = .quantitative
        content.numericValue = 42
        content.unitText = "ng/mL"
        content.sourceAnalyteText = "Ferritin"
        content.sourceValueText = "42"
        var draft = LabObservationDraft()
        draft.collectedAt = PartialDateTime(text: "2026-02-25T08:10:00Z", precision: .instant)
        try lab.record(draft, content: content)

        let items = try TrackingTimeline(db: db).items(from: "2026-02-01", to: "2026-03-01")
        XCTAssertEqual(items.map(\.title), ["bodyMass", "Ferritin"])
        XCTAssertEqual(items.first?.value, "81.2 kg")
    }

    func testTimelineOrdersOffsetInstantsByInstantNotText() throws {
        let zulu = TimelineEntry(
            domain: "z", kind: "event", recordTable: "z", recordID: "1",
            occurrence: PartialDateTime(text: "2026-02-25T10:00:00Z", precision: .instant),
            basis: .occurrence, title: "Zulu"
        )
        let offset = TimelineEntry(
            domain: "offset", kind: "event", recordTable: "offset", recordID: "1",
            occurrence: PartialDateTime(text: "2026-02-25T12:00:00+03:00", precision: .instant),
            basis: .occurrence, title: "Offset"
        )
        let entries = try Timeline(providers: [
            TestTimelineProvider(domain: "z", values: [zulu]),
            TestTimelineProvider(domain: "offset", values: [offset])
        ]).entries(from: "2026-02-25T00:00:00Z", to: "2026-02-26T00:00:00Z")

        XCTAssertEqual(entries.map(\.title), ["Offset", "Zulu"])
    }

    func testTrackingTimelineIncludesManualMeasurementProviders() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let timeModel = TimeModel.riyadh()
        let timestamp = Date(timeIntervalSince1970: 1_772_000_000)
        let body = BodyCompositionMeasurementStore(db: db)
        _ = try body.log(BodyCompositionMeasurementDraft(
            metric: "weight", value: 82, unit: "kg", timestamp: timestamp,
            source: "manual", timezoneOffset: 180, timezoneIdentifier: "Asia/Riyadh"
        ), logicalDay: "2026-02-25")
        let custom = CustomMeasurementStore(db: db)
        let definition = try custom.createDefinition(name: "waist", unit: "cm")
        _ = try custom.log(CustomMeasurementLogDraft(
            definitionId: definition, value: 81, timestamp: timestamp,
            timezoneOffset: 180, timezoneIdentifier: "Asia/Riyadh"
        ), logicalDay: "2026-02-25")

        let items = try TrackingTimeline(db: db).items(for: "2026-02-25", timeModel: timeModel)
        XCTAssertTrue(items.contains { $0.title == "Weight" })
        XCTAssertTrue(items.contains { $0.title == "waist" })
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
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

    // A month-precision record must not vanish from a range that starts inside
    // that month. Prefix comparison placed it at 1 March and dropped it; span
    // comparison keeps it and says the membership is potential, not certain.
    func testCoarseMonthObservationSurvivesARangeStartingInsideIt() throws {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        try LabCatalogSeed.seed(into: LabCatalogStore(db: db, clock: clock))
        let lab = LabStore(db: db, clock: clock)

        var content = LabRevisionContent()
        content.valueType = .quantitative
        content.numericValue = 18
        content.sourceAnalyteText = "Vitamin D"
        content.sourceValueText = "18"
        content.contentOrigin = .userTranscription
        var draft = LabObservationDraft()
        draft.collectedAt = PartialDateTime(text: "2019-03", precision: .month)
        try lab.record(draft, content: content)

        let startingMidMonth = try lab.entries(from: "2019-03-15", to: "2019-04-01")
        XCTAssertEqual(startingMidMonth.count, 1, "a month-precision record must not disappear")
        XCTAssertEqual(startingMidMonth[0].rangeFit, .potential)
        XCTAssertEqual(startingMidMonth[0].occurrence.text, "2019-03",
                       "storage still holds the month; no day was invented")

        // Whole month, but the record states no offset, so membership still
        // cannot be called definite — see testUnknownOffsetIsNeverDefinite.
        let wholeMonth = try lab.entries(from: "2019-03-01", to: "2019-04-01")
        XCTAssertEqual(wholeMonth.count, 1)
        XCTAssertEqual(wholeMonth[0].rangeFit, .potential)

        let differentMonth = try lab.entries(from: "2019-05-01", to: "2019-06-01")
        XCTAssertEqual(differentMonth.count, 0, "no overlap at all means excluded")

        // With the offset stated, the same containment is definite.
        let known = PartialDateTime(text: "2019-03", precision: .month,
                                    zone: ZoneContext(offsetMinutes: 180,
                                                      identifier: "Asia/Riyadh"))
        let march = try XCTUnwrap(DateRange(from: "2019-02-01", to: "2019-05-01"))
        XCTAssertEqual(known.fit(in: march), .definite)
        let midMarch = try XCTUnwrap(DateRange(from: "2019-03-15", to: "2019-04-01"))
        XCTAssertEqual(known.fit(in: midMarch), .potential)
        let elsewhere = try XCTUnwrap(DateRange(from: "2019-06-01", to: "2019-07-01"))
        XCTAssertNil(known.fit(in: elsewhere))
    }

    // An unknown offset can put the true instant up to 14 hours either side of
    // where the label reads. The span widens so nothing is wrongly excluded,
    // and the answer is never definite — that is the claim it cannot support.
    func testUnknownOffsetIsNeverDefinite() throws {
        let noOffset = PartialDateTime(text: "2019-03-14T08:10", precision: .minute)
        XCTAssertFalse(noOffset.hasKnownOffset)
        let containing = try XCTUnwrap(DateRange(from: "2019-01-01", to: "2020-01-01"))
        XCTAssertEqual(noOffset.fit(in: containing), .potential,
                       "a bare wall-clock reading is not pinned to an instant")

        // Widened, so a range just outside the naive UTC reading still overlaps.
        let justBefore = try XCTUnwrap(DateRange(from: "2019-03-13T20:00:00Z",
                                                 to: "2019-03-13T23:00:00Z"))
        XCTAssertEqual(noOffset.fit(in: justBefore), .potential)

        // The same reading with its offset stated is pinned, and definite.
        let withOffset = PartialDateTime(text: "2019-03-14T08:10", precision: .minute,
                                         zone: ZoneContext(offsetMinutes: 180))
        XCTAssertTrue(withOffset.hasKnownOffset)
        XCTAssertEqual(withOffset.fit(in: containing), .definite)
        XCTAssertNil(withOffset.fit(in: justBefore),
                     "pinned, so it is genuinely outside that window")

        // Text carrying its own offset counts as known without a ZoneContext.
        XCTAssertTrue(PartialDateTime(text: "2019-03-14T08:10:00Z", precision: .instant)
            .hasKnownOffset)
        XCTAssertTrue(PartialDateTime(text: "2019-03-14T08:10:00+03:00", precision: .instant)
            .hasKnownOffset)
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
