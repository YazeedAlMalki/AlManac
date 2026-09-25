import Testing
import Foundation
@testable import AlmanacCore

@Suite("CustomMeasurementStore Tests")
struct CustomMeasurementStoreTests {
    let db = try! TestDatabase()
    var store: CustomMeasurementStore { CustomMeasurementStore(db: db) }

    @Test("Create a definition and read it back")
    func createDefinition() throws {
        let id = try store.createDefinition(name: "waist", unit: "cm")
        let definition = try store.definition(id: id)

        #expect(definition?.name == "waist")
        #expect(definition?.unit == "cm")
    }

    @Test("Definition names are unique")
    func duplicateNameRejected() throws {
        _ = try store.createDefinition(name: "waist", unit: "cm")

        #expect(throws: (any Error).self) {
            try store.createDefinition(name: "waist", unit: "in")
        }
    }

    @Test("List all definitions")
    func listDefinitions() throws {
        _ = try store.createDefinition(name: "waist", unit: "cm")
        _ = try store.createDefinition(name: "chest", unit: "cm")

        let definitions = try store.definitions()
        #expect(Set(definitions.map { $0.name }) == ["waist", "chest"])
    }

    @Test("Log a measurement against a definition and read history")
    func logAndHistory() throws {
        let waistId = try store.createDefinition(name: "waist", unit: "cm")

        _ = try store.log(CustomMeasurementLogDraft(
            definitionId: waistId, value: 82.0,
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            timezoneOffset: 180, timezoneIdentifier: "Asia/Riyadh"), logicalDay: "2026-09-01")
        _ = try store.log(CustomMeasurementLogDraft(
            definitionId: waistId, value: 80.5,
            timestamp: Date(timeIntervalSince1970: 2_000_000)), logicalDay: "2026-09-08")

        let history = try store.history(definitionId: waistId, from: "2026-09-01", to: "2026-09-09")

        #expect(history.count == 2)
        #expect(history.map { $0.value } == [82.0, 80.5])
        #expect(history.first?.timezoneOffset == 180)
        #expect(history.first?.timezoneIdentifier == "Asia/Riyadh")
    }

    @Test("A log entry against a nonexistent definition is rejected")
    func logAgainstMissingDefinitionRejected() throws {
        #expect(throws: (any Error).self) {
            try store.log(CustomMeasurementLogDraft(
                definitionId: 999, value: 1.0, timestamp: Date()), logicalDay: "2026-09-01")
        }
    }
}
