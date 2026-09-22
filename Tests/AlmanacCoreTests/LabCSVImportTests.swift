import XCTest
@testable import AlmanacCore

/// The CSV import is the app's import automation. These pin that it writes
/// through the same seams as manual entry (so conflict holding, fingerprints
/// and revision rules apply), preserves source text verbatim, and never
/// invents a fact to satisfy the schema.
final class LabCSVImportTests: XCTestCase {

    private let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))

    private func makeStore(seedCatalog: Bool = true) throws -> LabStore {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = LabStore(db: db, clock: clock)
        if seedCatalog {
            try LabCatalogSeed.seed(into: LabCatalogStore(db: db, clock: clock))
        }
        return store
    }

    private func csv(_ rows: [String]) -> String { rows.joined(separator: "\n") + "\n" }

    func testWellFormedImportCreatesOneReportWithObservations() throws {
        let store = try makeStore()
        let text = csv([
            "R-1,2026-09-08,HealthCheck Lab,Quarterly bloods,Ferritin,42,ng/mL,20-300,,,o1",
            "R-1,2026-09-08,HealthCheck Lab,Quarterly bloods,Vitamin D,9.4,ng/mL,30-100,,,o2",
        ])

        let result = try LabReportCSVImport.importReports(csv: text, into: store)
        XCTAssertEqual(result.groups, 1)
        XCTAssertEqual(result.reportsCreated, 1)
        XCTAssertEqual(result.observationsCreated, 2)
        XCTAssertEqual(result.invalidRows, [])

        let reports = try store.reports(limit: 10)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].resultCount, 2)
        XCTAssertFalse(reports[0].hasUnresolvedConflict)
        XCTAssertEqual(reports[0].laboratoryNameText, "HealthCheck Lab")

        let results = try store.currentResults(inReport: reports[0].id)
        XCTAssertEqual(results.count, 2)
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.displayName, $0) })
        XCTAssertEqual(byName["Ferritin"]?.value, .quantity(text: "42", unit: "ng/mL"))
        XCTAssertEqual(byName["Ferritin"]?.content.rangeText, "20-300")
        XCTAssertEqual(byName["Vitamin D"]?.content.unitText, "ng/mL")
    }

    func testReimportIsIdempotent() throws {
        let store = try makeStore(seedCatalog: false)
        let text = csv([
            "R-1,2026-09-08,HealthCheck Lab,,Ferritin,42,ng/mL,,,,o1",
            "R-1,2026-09-08,HealthCheck Lab,,Vitamin D,9.4,ng/mL,,,,o2",
        ])

        let first = try LabReportCSVImport.importReports(csv: text, into: store)
        XCTAssertEqual(first.reportsCreated, 1)
        XCTAssertEqual(first.observationsCreated, 2)

        let second = try LabReportCSVImport.importReports(csv: text, into: store)
        XCTAssertEqual(second.reportsUnchanged, 1)
        XCTAssertEqual(second.observationsUnchanged, 2)
        XCTAssertEqual(second.reportsCreated, 0)
        XCTAssertEqual(second.observationsCreated, 0)

        let reports = try store.reports(limit: 10)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(try store.currentResults(inReport: reports[0].id).count, 2)
    }

    func testComparatorValuesAreParsedAndVerbatimTextKept() throws {
        let store = try makeStore(seedCatalog: false)
        let text = csv([
            "R-2,2026-09-08,Laboratory A,,Ferritin,<0.01,ng/mL,,,,o1",
            "R-2,2026-09-08,Laboratory A,,Ferritin,>=2.0,ng/mL,,,,o2",
            "R-2,2026-09-08,Laboratory A,,Ferritin,~5,ng/mL,,,,o3",
        ])

        _ = try LabReportCSVImport.importReports(csv: text, into: store)

        let report = try XCTUnwrap(try store.reports(limit: 10).first)
        let results = try store.currentResults(inReport: report.id)
        XCTAssertEqual(results.count, 3)
        let bySourceText = Dictionary(uniqueKeysWithValues: results.map { ($0.content.sourceValueText ?? "", $0) })
        XCTAssertEqual(bySourceText["<0.01"]?.content.comparator, .lt)
        XCTAssertEqual(bySourceText["<0.01"]?.content.numericValue, 0.01)
        XCTAssertEqual(bySourceText[">=2.0"]?.content.comparator, .gte)
        XCTAssertEqual(bySourceText[">=2.0"]?.content.numericValue, 2.0)
        XCTAssertEqual(bySourceText["~5"]?.content.comparator, .approx)
        XCTAssertEqual(bySourceText["~5"]?.content.numericValue, 5.0)
    }

    func testNonNumericValueIsStoredAsTextVerbatim() throws {
        let store = try makeStore(seedCatalog: false)
        let text = csv([
            "R-3,2026-09-08,Laboratory A,,Viral serology,Not detected,,,,,o1",
        ])

        _ = try LabReportCSVImport.importReports(csv: text, into: store)

        let report = try XCTUnwrap(try store.reports(limit: 10).first)
        let result = try XCTUnwrap(try store.currentResults(inReport: report.id).first)
        XCTAssertEqual(result.content.valueType, .text)
        XCTAssertEqual(result.content.textValue, "Not detected")
        XCTAssertEqual(result.content.sourceValueText, "Not detected")
        XCTAssertEqual(result.value, .narrative(text: "Not detected"))
    }

    func testUnknownAnalyteStaysUnmatchedAndVisible() throws {
        let store = try makeStore()  // seeded catalog, so a miss is a real miss
        let text = csv([
            "R-4,2026-09-08,Laboratory A,,Xerox-Beta-7,12.3,u/mL,,,,o1",
        ])

        _ = try LabReportCSVImport.importReports(csv: text, into: store)

        let report = try XCTUnwrap(try store.reports(limit: 10).first)
        let result = try XCTUnwrap(try store.currentResults(inReport: report.id).first)
        XCTAssertTrue(result.isUnmatched)
        XCTAssertNil(result.catalogAnalyteID)
        XCTAssertEqual(result.displayName, "Xerox-Beta-7")
    }

    func testBlankLinesAndMalformedRowsAreCollectedNotDroppedSilently() throws {
        let store = try makeStore(seedCatalog: false)
        let text = csv([
            "",
            "R-5,2026-09-08,Laboratory A,,Ferritin,42,ng/mL,,,,o1",
            "R-5,2026-09-08,Laboratory A",
            "R-5,2026-09-08,Laboratory A,,,42,ng/mL,,,,o2",
        ])

        let result = try LabReportCSVImport.importReports(csv: text, into: store)
        XCTAssertEqual(result.invalidRowCount, 2)
        XCTAssertEqual(result.reportsCreated, 1)
        XCTAssertEqual(result.observationsCreated, 1)
    }

    func testEmptyValueIsRecordedAsAbsentNotDropped() throws {
        let store = try makeStore(seedCatalog: false)
        let text = csv([
            "R-6,2026-09-08,Laboratory A,,Ferritin,,,,,,o1",
        ])

        let result = try LabReportCSVImport.importReports(csv: text, into: store)
        XCTAssertEqual(result.observationsCreated, 1)

        let report = try XCTUnwrap(try store.reports(limit: 10).first)
        let value = try XCTUnwrap(try store.currentResults(inReport: report.id).first)
        XCTAssertEqual(value.content.valueType, .absent)
        XCTAssertEqual(value.content.missingReason, .notReportedBySource)
    }

    func testChangedReportMetadataOnReimportIsHeldForReview() throws {
        let store = try makeStore(seedCatalog: false)
        let first = csv([
            "R-7,2026-09-08,HealthCheck Lab,Initial issue,Ferritin,42,ng/mL,,,,o1",
        ])
        _ = try LabReportCSVImport.importReports(csv: first, into: store)

        let amended = csv([
            "R-7,2026-09-08,HealthCheck Lab,Amended header,Ferritin,42,ng/mL,,,,o1",
        ])
        let result = try LabReportCSVImport.importReports(csv: amended, into: store)
        XCTAssertEqual(result.reportConflicts, 1)
        XCTAssertEqual(result.observationsUnchanged, 1)

        let report = try XCTUnwrap(try store.reports(limit: 10).first)
        XCTAssertTrue(report.hasUnresolvedConflict)
        let proposals = try store.reportRevisions(of: report.id).filter { $0.kind == "conflict" }
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals[0].headerText, "Amended header")
    }
}