import XCTest
@testable import AlmanacCore

final class ProvenanceTests: XCTestCase {

    func testOnlyGroupsABAndNShip() {
        XCTAssertTrue(LicenceGroup.permissive.isShippable)
        XCTAssertTrue(LicenceGroup.attribution.isShippable)
        XCTAssertTrue(LicenceGroup.native.isShippable)
        XCTAssertFalse(LicenceGroup.shareAlike.isShippable)
        XCTAssertFalse(LicenceGroup.restricted.isShippable)
    }

    // Handoff 2026-09-13: Almanac-native rows are Almanac's own IP, group N, and always ship.
    func testAlmanacNativeRowsAreGroupNAndPassTheBundleGuard() {
        XCTAssertEqual(LicenceGroup(rawValue: "N"), .native)
        XCTAssertEqual(SourceIdentifier.Namespace.almanac.licenceGroup, .native)
        XCTAssertNoThrow(try BundleGuard.assertShippable(
            [(identifier: "almanac:kabsa", group: LicenceGroup.native)]))
    }

    func testBundleGuardFailsLoudlyOnRestrictedRow() {
        let clean = [("usda:1105904", LicenceGroup.permissive), ("cofid:13-145", .attribution)]
        XCTAssertNoThrow(try BundleGuard.assertShippable(clean.map { (identifier: $0.0, group: $0.1) }))

        let mixed = clean + [("sfda:kabsa-01", LicenceGroup.restricted)]
        XCTAssertThrowsError(try BundleGuard.assertShippable(mixed.map { (identifier: $0.0, group: $0.1) })) {
            XCTAssertTrue("\($0)".contains("sfda:kabsa-01"))
        }
    }

    func testOpenFoodFactsIsNeverShippable() {
        XCTAssertEqual(SourceIdentifier.Namespace.openFoodFacts.licenceGroup, .shareAlike)
        XCTAssertFalse(SourceIdentifier.Namespace.openFoodFacts.licenceGroup.isShippable)
    }

    func testSourceIdentifierRoundTrips() {
        let id = SourceIdentifier(namespace: .usda, localID: "1105904")
        XCTAssertEqual(id.description, "usda:1105904")
        XCTAssertEqual(SourceIdentifier(parsing: "usda:1105904"), id)
        // CoFID identifiers contain a hyphen; the split must be on the FIRST colon only.
        XCTAssertEqual(SourceIdentifier(parsing: "cofid:13-145")?.localID, "13-145")
        XCTAssertNil(SourceIdentifier(parsing: "nosuchsource:1"))
        XCTAssertNil(SourceIdentifier(parsing: "usda:"))
        XCTAssertNil(SourceIdentifier(parsing: "1105904"))
    }

    // The bug the qualifier enum exists to prevent.
    func testNotAnalysedIsNotZero() {
        let iron = NutrientValue(
            foodRef: SourceIdentifier(namespace: .cofid, localID: "13-145"),
            nutrientID: "fe",
            amount: nil,
            qualifier: .notAnalysed,
            sourceValue: "N",
            sourceNutrientID: "Fe",
            sourceUnit: "mg",
            licenceGroup: .attribution
        )
        XCTAssertNil(iron.amount)
        XCTAssertFalse(iron.qualifier.hasQuantity)
        XCTAssertFalse(iron.qualifier.isDirectlyObserved)
        XCTAssertEqual(iron.sourceValue, "N", "the original cell must survive parsing")
    }

    func testTraceZeroAndUnmeasuredAreThreeDistinctFacts() {
        XCTAssertNotEqual(NutrientQualifier.trace, .zeroReported)
        XCTAssertNotEqual(NutrientQualifier.zeroReported, .notAnalysed)
        XCTAssertNotEqual(NutrientQualifier.trace, .notAnalysed)
        XCTAssertTrue(NutrientQualifier.trace.hasQuantity)
        XCTAssertTrue(NutrientQualifier.zeroReported.isDirectlyObserved)
        XCTAssertFalse(NutrientQualifier.trace.isDirectlyObserved)
    }

    func testQualifierRawValuesAreStableAcrossCoding() throws {
        for q in NutrientQualifier.allCases {
            let data = try JSONEncoder().encode(q)
            XCTAssertEqual(try JSONDecoder().decode(NutrientQualifier.self, from: data), q)
        }
        XCTAssertEqual(NutrientQualifier.notAnalysed.rawValue, "not_analysed")
        XCTAssertEqual(NutrientQualifier.belowLOQ.rawValue, "below_loq")
    }
}
