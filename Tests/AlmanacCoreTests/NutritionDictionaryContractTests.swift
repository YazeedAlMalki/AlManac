import XCTest
@testable import AlmanacCore

/// tools/nutrition keeps the qualifier vocabulary and the licence registry as
/// data; AlmanacCore keeps them as enums. They must not drift: a disagreement
/// about what ships is the failure the whole licence design exists to prevent.
final class NutritionDictionaryContractTests: XCTestCase {

    private static let dictionary = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AlmanacCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // package root
        .appendingPathComponent("tools/nutrition/dictionary")

    func testQualifierVocabularyMatchesThePipeline() throws {
        let rows = try Self.csv("qualifiers.csv")
        XCTAssertEqual(Set(rows.compactMap { $0["qualifier"] }),
                       Set(NutrientQualifier.allCases.map(\.rawValue)))
        for row in rows {
            let qualifier = try XCTUnwrap(NutrientQualifier(rawValue: row["qualifier"] ?? ""))
            XCTAssertEqual(row["has_quantity"] == "true", qualifier.hasQuantity, qualifier.rawValue)
            XCTAssertEqual(row["directly_observed"] == "true", qualifier.isDirectlyObserved,
                           qualifier.rawValue)
        }
    }

    func testLicenceGroupsAgreeOnWhatShips() throws {
        let rows = try Self.csv("licence_groups.csv")
        XCTAssertEqual(Set(rows.compactMap { $0["licence_group"] }),
                       Set(LicenceGroup.allCases.map(\.rawValue)))
        for row in rows {
            let group = try XCTUnwrap(LicenceGroup(rawValue: row["licence_group"] ?? ""))
            XCTAssertEqual(row["shippable"] == "true", group.isShippable, group.rawValue)
        }
    }

    func testEveryPipelineSourceHasTheSameLicenceGroupInSwift() throws {
        for row in try Self.csv("sources.csv") {
            let name = row["namespace"] ?? ""
            let namespace = try XCTUnwrap(SourceIdentifier.Namespace(rawValue: name), name)
            XCTAssertEqual(namespace.licenceGroup.rawValue, row["licence_group"], name)
        }
    }

    /// The RFC 4180 subset the pipeline writes: quoted fields, doubled quotes, `\n` records.
    private static func csv(_ name: String) throws -> [[String: String]] {
        let text = try String(contentsOf: dictionary.appendingPathComponent(name), encoding: .utf8)
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var characters = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? characters.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    let next = characters.next()
                    if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                record.append(field); field = ""
            } else if c == "\n" {
                record.append(field); records.append(record); record = []; field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }
        guard let header = records.first else { return [] }
        return records.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
    }
}
