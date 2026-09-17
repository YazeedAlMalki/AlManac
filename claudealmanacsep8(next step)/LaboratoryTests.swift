import XCTest
@testable import AlmanacCore

final class LaboratoryTests: XCTestCase {

    private func fixture() throws -> (Database, LabStore, LabCatalogStore) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))  // 2026-02-25
        let catalog = LabCatalogStore(db: db, clock: clock)
        try LabCatalogSeed.seed(into: catalog)
        return (db, LabStore(db: db, clock: clock, zone: ZoneContext(offsetMinutes: 180,
                                                                    identifier: "Asia/Riyadh")), catalog)
    }

    private func quantitative(_ analyte: String, _ text: String, _ value: Double,
                              unit: String) -> LabRevisionContent {
        var c = LabRevisionContent()
        c.lifecycle = .final
        c.valueType = .quantitative
        c.derivation = .reportedWithoutDerivationStated
        c.numericValue = value
        c.unitText = unit
        c.sourceAnalyteText = analyte
        c.sourceValueText = text
        c.contentOrigin = .sourceExtraction
        c.actor = "import:lab-a"
        return c
    }

    // 1. A report with several results, saved and read back.
    func testReportWithSeveralResultsRoundTrips() throws {
        let (_, store, _) = try fixture()
        var report = LabReportDraft()
        report.sourceSystem = "lab-a"
        report.sourceReportID = "R-9001"
        report.laboratoryNameText = "Al Borg Laboratories"
        report.reportedAt = PartialDateTime(text: "2026-02-20", precision: .day)
        report.entryOrigin = "import"
        let reportID = try store.saveReport(report)

        let rows: [(String, String, Double, String)] = [
            ("HGB", "14.2", 14.2, "g/dL"),
            ("Ferritin", "42", 42, "ng/mL"),
            ("TSH", "2.1", 2.1, "mIU/L"),
            ("25(OH)D", "31", 31, "ng/mL")
        ]
        for (index, row) in rows.enumerated() {
            var draft = LabObservationDraft()
            draft.reportID = reportID
            draft.sourceSystem = "lab-a"
            draft.sourceObservationID = "R-9001-\(index)"
            draft.collectedAt = PartialDateTime(text: "2026-02-20T07:45:00Z", precision: .instant)
            try store.record(draft, content: quantitative(row.0, row.1, row.2, unit: row.3))
        }

        let ids = try store.observationIDs(inReport: reportID)
        XCTAssertEqual(ids.count, 4)
        let names = try ids.compactMap { try store.currentRevision(of: $0)?.content.sourceAnalyteText }
        XCTAssertEqual(Set(names), Set(["HGB", "Ferritin", "TSH", "25(OH)D"]))
        // Saving the same source report twice returns the same row, not a copy.
        XCTAssertEqual(try store.saveReport(report), reportID)
    }

    // 2. Alias lookup, including a different script and punctuation.
    func testAliasLookup() throws {
        let (_, _, catalog) = try fixture()
        XCTAssertEqual(try catalog.match(sourceText: "HGB")?.analyteID,
                       "almanac:lab.haematology.haemoglobin")
        XCTAssertEqual(try catalog.match(sourceText: "  hemoglobin ")?.analyteID,
                       "almanac:lab.haematology.haemoglobin")
        XCTAssertEqual(try catalog.match(sourceText: "هيموغلوبين")?.analyteID,
                       "almanac:lab.haematology.haemoglobin")
        XCTAssertEqual(try catalog.match(sourceText: "25(OH)D")?.analyteID,
                       "almanac:lab.vitamin-d.25oh-total")
        XCTAssertEqual(try catalog.match(sourceText: "RBC folate")?.analyteID,
                       "almanac:lab.vitamin-b9.folate-rbc")
        // No nearest guess.
        XCTAssertNil(try catalog.match(sourceText: "Zonulin"))
        XCTAssertNil(try catalog.match(sourceText: ""))
    }

    // Unverified external codes must never drive a match.
    func testUnverifiedExternalCodeDoesNotMatch() throws {
        let (_, _, catalog) = try fixture()
        try catalog.addExternalCode(system: "loinc", code: "718-7",
                                    to: "almanac:lab.haematology.haemoglobin", verified: false)
        XCTAssertNil(try catalog.matchExternalCode(system: "loinc", code: "718-7"))
        try catalog.addExternalCode(system: "loinc", code: "718-7",
                                    to: "almanac:lab.haematology.haemoglobin",
                                    verified: true, verifiedBy: "yazeed")
        XCTAssertEqual(try catalog.matchExternalCode(system: "loinc", code: "718-7")?.analyteID,
                       "almanac:lab.haematology.haemoglobin")
    }

    // 3a. A qualitative result keeps its coded token and gets no number.
    func testQualitativeResult() throws {
        let (_, store, _) = try fixture()
        var c = LabRevisionContent()
        c.lifecycle = .final
        c.valueType = .qualitativeCoded
        c.codedValue = "Negative"
        c.sourceAnalyteText = "HBsAg"
        c.sourceValueText = "NEGATIVE"
        let outcome = try store.record(LabObservationDraft(), content: c)
        let current = try XCTUnwrap(try store.currentRevision(of: outcome.observationID))
        XCTAssertNil(current.content.numericValue)
        XCTAssertEqual(current.content.presentation, .coded(text: "Negative"))
        XCTAssertEqual(try store.catalogAnalyteID(of: outcome.observationID),
                       "almanac:lab.serology.hepatitis-b-surface-antigen")
    }

    // 3b. A bounded result keeps its comparator and does NOT acquire a limit.
    func testBoundedResultDoesNotInventAQuantificationLimit() throws {
        let (_, store, _) = try fixture()
        var c = LabRevisionContent()
        c.lifecycle = .final
        c.valueType = .quantitative
        c.comparator = .lt
        c.numericValue = 0.3
        c.unitText = "mg/L"
        c.sourceAnalyteText = "CRP"
        c.sourceValueText = "<0.3"
        let outcome = try store.record(LabObservationDraft(), content: c)
        let current = try XCTUnwrap(try store.currentRevision(of: outcome.observationID))
        XCTAssertEqual(current.content.comparator, .lt)
        XCTAssertNil(current.content.loqText, "a '<' must not be read as a quantification limit")
        XCTAssertNil(current.content.lodText)
        XCTAssertEqual(current.content.sourceValueText, "<0.3")
        XCTAssertEqual(current.content.presentation,
                       .bounded(comparator: "<", text: "<0.3", unit: "mg/L"))
    }

    // 3c. An unmatched analyte is stored in full and is not dropped.
    func testUnmatchedResultIsPreserved() throws {
        let (_, store, _) = try fixture()
        var c = LabRevisionContent()
        c.lifecycle = .final
        c.valueType = .quantitative
        c.numericValue = 61.0
        c.unitText = "ng/mL"
        c.sourceAnalyteText = "Zonulin"
        c.sourceValueText = "61"
        var draft = LabObservationDraft()
        draft.collectedAt = PartialDateTime(text: "2026-02-20T07:45:00Z", precision: .instant)
        let outcome = try store.record(draft, content: c)
        XCTAssertNil(try store.catalogAnalyteID(of: outcome.observationID))
        let current = try XCTUnwrap(try store.currentRevision(of: outcome.observationID))
        XCTAssertEqual(current.content.sourceAnalyteText, "Zonulin")
        let entries = try store.entries(from: "2026-01-01", to: "2027-01-01")
        let entry = try XCTUnwrap(entries.first { $0.recordID == outcome.observationID })
        XCTAssertEqual(entry.title, "Zonulin")
        XCTAssertEqual(entry.detail, "unmatched: not in catalog")
    }

    // 4. Historical entry with almost nothing known, and nothing invented.
    func testIncompleteHistoricalEntry() throws {
        let (db, store, _) = try fixture()
        var c = LabRevisionContent()
        c.lifecycle = .unknown
        c.valueType = .quantitative
        c.numericValue = 18
        c.sourceAnalyteText = "Vitamin D"
        c.contentOrigin = .userTranscription      // typed from a paper report
        c.actor = "user"
        var draft = LabObservationDraft()
        draft.collectedAt = PartialDateTime(text: "2019", precision: .year)
        let outcome = try store.record(draft, content: c)

        let row = try XCTUnwrap(db.query("""
            SELECT collected_at, collected_precision, collected_tz_offset_minutes,
                   report_id, specimen_text, created_at
            FROM lab_observation WHERE id = ?;
            """, [.text(outcome.observationID)]).first)
        XCTAssertEqual(row.string("collected_at"), "2019")
        XCTAssertEqual(row.string("collected_precision"), "year")
        XCTAssertTrue(row.isNull("collected_tz_offset_minutes"), "unknown zone stays unknown")
        XCTAssertTrue(row.isNull("report_id"))
        XCTAssertTrue(row.isNull("specimen_text"))
        // Almanac's own recording time is always captured, and is not the
        // occurrence: 2019 is when the blood was drawn, 2026 is when it was typed in.
        let recorded = try XCTUnwrap(row.string("created_at"))
        XCTAssertTrue(recorded.hasPrefix("2026"), "recorded_at is generated, got \(recorded)")

        let stored = try XCTUnwrap(PartialDateTime(storedText: "2019", precision: .year))
        XCTAssertNil(stored.datePrefix, "a year names no single day")
    }

    // Missing source text must not block entry.
    func testEntryWithoutAnySourceTextIsAllowed() throws {
        let (_, store, _) = try fixture()
        var c = LabRevisionContent()
        c.valueType = .absent
        c.missingReason = .notEntered
        c.contentOrigin = .userTranscription
        let outcome = try store.record(LabObservationDraft(), content: c)
        let current = try XCTUnwrap(try store.currentRevision(of: outcome.observationID))
        XCTAssertNil(current.content.sourceValueText)
        XCTAssertEqual(current.content.presentation, .missing(reason: "not_entered"))
    }

    func testAbsentValueRequiresAReason() throws {
        let (_, store, _) = try fixture()
        var c = LabRevisionContent()
        c.valueType = .absent
        XCTAssertThrowsError(try store.record(LabObservationDraft(), content: c))
    }

    // 5. Two legitimate repeats of the same test are two observations.
    func testTwoLegitimateRepeatsArePreserved() throws {
        let (_, store, _) = try fixture()
        var first = LabObservationDraft()
        first.timePointLabel = "OGTT 0 min"
        first.repeatIndex = 0
        first.collectedAt = PartialDateTime(text: "2026-02-20T07:00:00Z", precision: .instant)
        var second = LabObservationDraft()
        second.timePointLabel = "OGTT 120 min"
        second.repeatIndex = 1
        second.collectedAt = PartialDateTime(text: "2026-02-20T09:00:00Z", precision: .instant)

        let a = try store.record(first, content: quantitative("Glucose fasting", "5.1", 5.1, unit: "mmol/L"))
        let b = try store.record(second, content: quantitative("Glucose fasting", "7.4", 7.4, unit: "mmol/L"))
        XCTAssertNotEqual(a.observationID, b.observationID)

        // The same holds for a source that identifies each repeat separately.
        var s1 = LabObservationDraft(); s1.sourceSystem = "lab-a"; s1.sourceObservationID = "G-1"
        var s2 = LabObservationDraft(); s2.sourceSystem = "lab-a"; s2.sourceObservationID = "G-2"
        let c = try store.record(s1, content: quantitative("Glucose fasting", "5.1", 5.1, unit: "mmol/L"))
        let d = try store.record(s2, content: quantitative("Glucose fasting", "7.4", 7.4, unit: "mmol/L"))
        XCTAssertNotEqual(c.observationID, d.observationID)
    }

    // 6 + 7. An amendment under the same external id revises; a re-import of
    // content already held changes nothing.
    func testAmendmentKeepsExternalIDAndReimportIsIdempotent() throws {
        let (_, store, _) = try fixture()
        var draft = LabObservationDraft()
        draft.sourceSystem = "lab-a"
        draft.sourceObservationID = "OBS-77"
        draft.collectedAt = PartialDateTime(text: "2026-02-20T07:45:00Z", precision: .instant)

        let original = quantitative("Potassium", "4.1", 4.1, unit: "mmol/L")
        let created = try store.record(draft, content: original)
        guard case .created = created else { return XCTFail("expected a new observation") }

        var amended = original
        amended.lifecycle = .corrected
        amended.numericValue = 4.6
        amended.sourceValueText = "4.6"
        amended.reasonText = "Corrected by issuing laboratory"
        let revised = try store.record(draft, content: amended)
        guard case .revised(let observationID, _, let number) = revised else {
            return XCTFail("expected a revision, got \(revised)")
        }
        XCTAssertEqual(observationID, created.observationID, "same external id, same observation")
        XCTAssertEqual(number, 2)

        let history = try store.revisions(of: observationID)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content.numericValue, 4.1)
        XCTAssertFalse(history[0].isCurrent)
        XCTAssertEqual(history[1].content.numericValue, 4.6)
        XCTAssertTrue(history[1].isCurrent)
        XCTAssertEqual(try store.currentRevision(of: observationID)?.content.numericValue, 4.6)

        // Re-import the current revision: no-op.
        let again = try store.record(draft, content: amended)
        XCTAssertTrue(again.isNoOp)
        XCTAssertEqual(try store.revisions(of: observationID).count, 2)

        // Re-import the *superseded* revision: also a no-op, and it does not
        // resurrect itself as current.
        let older = try store.record(draft, content: original)
        XCTAssertTrue(older.isNoOp)
        XCTAssertEqual(try store.revisions(of: observationID).count, 2)
        XCTAssertEqual(try store.currentRevision(of: observationID)?.content.numericValue, 4.6)
    }

    // Two sources may reuse one identifier string without colliding.
    func testExternalIdentityIsScopedToItsSource() throws {
        let (_, store, _) = try fixture()
        var a = LabObservationDraft(); a.sourceSystem = "lab-a"; a.sourceObservationID = "1"
        var b = LabObservationDraft(); b.sourceSystem = "lab-b"; b.sourceObservationID = "1"
        let first = try store.record(a, content: quantitative("Ferritin", "42", 42, unit: "ng/mL"))
        let second = try store.record(b, content: quantitative("Ferritin", "58", 58, unit: "ng/mL"))
        XCTAssertNotEqual(first.observationID, second.observationID)
    }

    func testPanelsAreReusable() throws {
        let (_, _, catalog) = try fixture()
        // 15, not 4: the CBC now carries red indices, platelet indices and a
        // five-part differential. `CatalogCoverageTests.testCBCPanelIsComplete`
        // pins the membership itself.
        XCTAssertEqual(try catalog.panelMembers("almanac:panel.cbc").count, 15)
        try catalog.createPanel(id: "almanac:panel.my-quarterly", name: "Quarterly bloods",
                                origin: "user",
                                analyteIDs: ["almanac:lab.iron.ferritin",
                                             "almanac:lab.vitamin-d.25oh-total"])
        XCTAssertEqual(try catalog.panelMembers("almanac:panel.my-quarterly"),
                       ["almanac:lab.iron.ferritin", "almanac:lab.vitamin-d.25oh-total"])
    }

    // Specimen is optional, preserved as printed, and never merged across
    // materials.
    func testSpecimenIsOptionalAndBloodAndUrineDoNotMerge() throws {
        let (db, store, _) = try fixture()

        // Says nothing about the specimen, and still saves.
        let silent = try store.record(LabObservationDraft(),
                                      content: quantitative("Ferritin", "42", 42, unit: "ng/mL"))
        XCTAssertEqual(try store.specimenKind(of: silent.observationID), .unknown)

        var serum = LabObservationDraft()
        serum.specimenKind = .serum
        serum.specimenText = "SERUM"
        var urine = LabObservationDraft()
        urine.specimenKind = .urine
        urine.specimenText = "Urine, random"

        let inSerum = try store.record(serum, content: quantitative("Ferritin", "44", 44, unit: "ng/mL"))
        let inUrine = try store.record(urine, content: quantitative("Ferritin", "9", 9, unit: "ng/mL"))

        let groups = try store.observationsBySpecimen(analyteID: "almanac:lab.iron.ferritin")
        XCTAssertEqual(groups[.serum], [inSerum.observationID])
        XCTAssertEqual(groups[.urine], [inUrine.observationID])
        XCTAssertEqual(groups[.unknown], [silent.observationID],
                       "an unstated specimen is its own group, not folded into a stated one")
        XCTAssertEqual(try store.observationIDs(analyteID: "almanac:lab.iron.ferritin",
                                                specimenKind: .serum),
                       [inSerum.observationID])

        XCTAssertFalse(SpecimenKind.sameSpecimen(.serum, .urine))
        XCTAssertTrue(SpecimenKind.knownDifferentMaterial(.serum, .urine))
        XCTAssertFalse(SpecimenKind.sameSpecimen(.serum, .plasma),
                       "different fractions, different reference intervals")
        XCTAssertFalse(SpecimenKind.sameSpecimen(.unknown, .unknown),
                       "two unstated specimens are not evidence that they match")
        XCTAssertFalse(SpecimenKind.sameSpecimen(.other, .other),
                       "'other' covers saliva, CSF and stool at once — unresolved")
        XCTAssertFalse(SpecimenKind.knownDifferentMaterial(.other, .other),
                       "unresolved is not the same as known to differ")
        XCTAssertFalse(SpecimenKind.knownDifferentMaterial(.serum, .unknown),
                       "unstated is not knowledge of a difference")

        // The source's own wording survives the classification.
        let text = try db.query("SELECT specimen_text FROM lab_observation WHERE id = ?;",
                                [.text(inSerum.observationID)]).first?.string("specimen_text")
        XCTAssertEqual(text, "SERUM")
    }

    // A reissued report with a corrected date or name must not be dropped on
    // the floor by find-or-create.
    func testReportMetadataCorrectionIsPreservedNotDiscarded() throws {
        let (db, store, _) = try fixture()
        var report = LabReportDraft()
        report.sourceSystem = "lab-a"
        report.sourceReportID = "R-1"
        report.laboratoryNameText = "Al Borg"
        report.reportedAt = PartialDateTime(text: "2026-02-20", precision: .day)

        guard case .created(let reportID) = try store.upsertReport(report) else {
            return XCTFail("expected a new report")
        }
        XCTAssertEqual(try store.upsertReport(report), .unchanged(reportID: reportID),
                       "identical metadata is a no-op")

        var corrected = report
        corrected.laboratoryNameText = "Al Borg Laboratories"
        corrected.reportedAt = PartialDateTime(text: "2026-02-21", precision: .day)
        guard case .updated(let sameID, _, let number) = try store.upsertReport(corrected) else {
            return XCTFail("expected the correction to be recorded")
        }
        XCTAssertEqual(sameID, reportID)
        XCTAssertEqual(number, 1)

        let live = try XCTUnwrap(db.query("""
            SELECT laboratory_name_text, reported_at FROM lab_report WHERE id = ?;
            """, [.text(reportID)]).first)
        XCTAssertEqual(live.string("laboratory_name_text"), "Al Borg Laboratories")
        XCTAssertEqual(live.string("reported_at"), "2026-02-21")

        let history = try store.reportRevisions(of: reportID)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].laboratoryNameText, "Al Borg")
        XCTAssertEqual(history[0].reportedAtText, "2026-02-20")
    }

    // Aliases are unique per (analyte, fold), not per fold, so a person can
    // introduce a collision after seeding. Resolving that with LIMIT 1 would
    // pick a winner by row order.
    func testAliasCollisionAfterSeedingLeavesTheRecordUnmatched() throws {
        let (_, store, catalog) = try fixture()
        XCTAssertEqual(try catalog.matchCandidates(sourceText: "Ferritin").unique?.analyteID,
                       "almanac:lab.iron.ferritin")

        // A second analyte claims the same word.
        try catalog.addAlias("Ferritin", to: "almanac:lab.iron.serum-iron", origin: "user")

        let result = try catalog.matchCandidates(sourceText: "Ferritin")
        XCTAssertTrue(result.isAmbiguous)
        XCTAssertEqual(result.candidates.map(\.analyteID),
                       ["almanac:lab.iron.ferritin", "almanac:lab.iron.serum-iron"])
        XCTAssertNil(result.unique)
        XCTAssertNil(try catalog.match(sourceText: "Ferritin"),
                     "the convenience accessor refuses an ambiguous answer too")

        // A record imported now stays unmatched, and says why.
        var c = LabRevisionContent()
        c.lifecycle = .final
        c.valueType = .quantitative
        c.numericValue = 42
        c.unitText = "ng/mL"
        c.sourceAnalyteText = "Ferritin"
        c.sourceValueText = "42"
        var draft = LabObservationDraft()
        draft.reportID = try store.saveReport(LabReportDraft())
        let outcome = try store.record(draft, content: c)
        XCTAssertNil(try store.catalogAnalyteID(of: outcome.observationID))

        let view = try XCTUnwrap(try store.currentResults(inReport: draft.reportID!).first)
        XCTAssertTrue(view.isUnmatched)
        XCTAssertEqual(view.ambiguousCandidates,
                       ["almanac:lab.iron.ferritin", "almanac:lab.iron.serum-iron"])
        XCTAssertEqual(view.displayName, "Ferritin", "the source's own words survive")
    }

    // The same for verified external codes.
    func testExternalCodeCollisionIsAmbiguousNotArbitrary() throws {
        let (_, _, catalog) = try fixture()
        try catalog.addExternalCode(system: "loinc", code: "2276-4",
                                    to: "almanac:lab.iron.ferritin", verified: true)
        XCTAssertEqual(try catalog.matchExternalCode(system: "loinc", code: "2276-4")?.analyteID,
                       "almanac:lab.iron.ferritin")
        try catalog.addExternalCode(system: "loinc", code: "2276-4",
                                    to: "almanac:lab.iron.serum-iron", verified: true)
        XCTAssertTrue(try catalog.externalCodeCandidates(system: "loinc", code: "2276-4")
            .isAmbiguous)
        XCTAssertNil(try catalog.matchExternalCode(system: "loinc", code: "2276-4"))
    }

    func testUnitCompatibilityRefusesDimensionlessBlanketPermission() throws {
        // Same dimension, same scale.
        guard case .identical = UnitRegistry.assess("mg/dL", "mg/dl") else {
            return XCTFail("expected identical")
        }
        // Same dimension, different scale: reported, not applied.
        guard case .sameDimensionDifferentScale = UnitRegistry.assess("g/L", "mg/dL") else {
            return XCTFail("expected a scale difference")
        }
        XCTAssertFalse(UnitRegistry.directlyComparable("g/L", "mg/dL"),
                       "conversion is deferred, so a scaled pair is not yet comparable")
        // Dimensionless is not one dimension: a percentage is not a ratio.
        guard case .differentDimension = UnitRegistry.assess("%", "ratio") else {
            return XCTFail("percentage and ratio must not be treated as interchangeable")
        }
        guard case .differentDimension = UnitRegistry.assess("mg/dL", "mmol/L") else {
            return XCTFail("mass and substance concentration need an analyte-specific factor")
        }
        // Unknown units assert nothing.
        guard case .undetermined = UnitRegistry.assess("mIU/L", "mg/dL") else {
            return XCTFail("expected undetermined")
        }
    }
}
