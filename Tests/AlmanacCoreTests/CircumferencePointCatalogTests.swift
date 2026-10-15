import Testing
import Foundation
@testable import AlmanacCore

/// BRD §6.6: custom circumference measurements are owner-priority,
/// "user-definable, charted". The seven built-in points stop being a fixed list:
/// the owner hides the ones they do not measure and adds their own, and every
/// point has a series to chart. Tested at `CircumferencePointCatalog`, the seam
/// the circumference screen calls.
@Suite("Circumference points")
struct CircumferencePointCatalogTests {
    let db = try! TestDatabase()
    var catalog: CircumferencePointCatalog { CircumferencePointCatalog(db: db) }

    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test("With nothing chosen, the seven built-in points are offered in their usual order")
    func defaults() throws {
        #expect(try catalog.points() == BodyMeasurementType.allCases.map(CircumferencePoint.builtIn))
    }

    @Test("A hidden built-in point is no longer offered, and can be shown again")
    func hideAndShow() throws {
        try catalog.setHidden(.calf, true)
        try catalog.setHidden(.neck, true)
        #expect(try !catalog.points().contains(.builtIn(.calf)))
        #expect(try catalog.hiddenBuiltIns() == [.calf, .neck])
        try catalog.setHidden(.calf, false)
        #expect(try catalog.points().contains(.builtIn(.calf)))
        #expect(try catalog.hiddenBuiltIns() == [.neck])
    }

    @Test("Hiding a point keeps its readings: they are still in its series")
    func hidingKeepsData() throws {
        try BodyMeasurementStore(db: db).log(BodyMeasurementDraft(
            measuredAt: at("2026-10-10T08:00:00Z"), measurementType: .calf, valueCm: 38))
        try catalog.setHidden(.calf, true)
        let series = try catalog.series(for: .builtIn(.calf),
                                        from: at("2026-10-01T00:00:00Z"), to: at("2026-11-01T00:00:00Z"))
        #expect(series.flatMap(\.values).map(\.value) == [38])
    }

    @Test("An owner point is added in centimetres and offered after the built-ins")
    func addOwnerPoint() throws {
        let point = try catalog.addPoint(name: "  Forearm ")
        guard case let .owner(id, name) = point else {
            Issue.record("expected an owner point, got \(point)")
            return
        }
        #expect(name == "Forearm")
        #expect(try CustomMeasurementStore(db: db).definition(id: id)?.unit == "cm")
        #expect(try catalog.points().last == point)
    }

    @Test("A point cannot be added twice, or under a built-in's name, or with no name")
    func duplicateNames() throws {
        _ = try catalog.addPoint(name: "Forearm")
        #expect(throws: CircumferencePointError.duplicateName) { try catalog.addPoint(name: "forearm") }
        #expect(throws: CircumferencePointError.duplicateName) { try catalog.addPoint(name: "Waist") }
        #expect(throws: CircumferencePointError.emptyName) { try catalog.addPoint(name: "   ") }
    }

    @Test("Custom measurements in other units are not circumference points")
    func otherUnitsExcluded() throws {
        try CustomMeasurementStore(db: db).createDefinition(name: "Grip strength", unit: "kg")
        #expect(try catalog.points().allSatisfy { $0.name != "Grip strength" })
    }

    @Test("A sided point charts each side as its own series, oldest first")
    func sidedSeries() throws {
        try ProfileStore(db: db).updateBodyMeasurementTrackSides(true)
        let store = BodyMeasurementStore(db: db)
        try store.log(BodyMeasurementDraft(measuredAt: at("2026-10-12T08:00:00Z"), measurementType: .arm, side: .left, valueCm: 35))
        try store.log(BodyMeasurementDraft(measuredAt: at("2026-10-10T08:00:00Z"), measurementType: .arm, side: .left, valueCm: 34))
        try store.log(BodyMeasurementDraft(measuredAt: at("2026-10-11T08:00:00Z"), measurementType: .arm, side: .right, valueCm: 36))

        let series = try catalog.series(for: .builtIn(.arm),
                                        from: at("2026-10-01T00:00:00Z"), to: at("2026-11-01T00:00:00Z"))
        #expect(series.map(\.side) == [.left, .right])
        #expect(series[0].values.map(\.value) == [34, 35])
        #expect(series[1].values.map(\.value) == [36])
    }

    @Test("An owner point's series is its own log, oldest first, bounded by the range")
    func ownerSeries() throws {
        let point = try catalog.addPoint(name: "Forearm")
        guard case let .owner(id, _) = point else { return }
        let custom = CustomMeasurementStore(db: db)
        try custom.log(CustomMeasurementLogDraft(definitionId: id, value: 29, timestamp: at("2026-10-12T08:00:00Z")),
                       logicalDay: "2026-10-12")
        try custom.log(CustomMeasurementLogDraft(definitionId: id, value: 28.5, timestamp: at("2026-10-05T08:00:00Z")),
                       logicalDay: "2026-10-05")
        try custom.log(CustomMeasurementLogDraft(definitionId: id, value: 27, timestamp: at("2026-09-01T08:00:00Z")),
                       logicalDay: "2026-09-01")

        let series = try catalog.series(for: point,
                                        from: at("2026-10-01T00:00:00Z"), to: at("2026-11-01T00:00:00Z"))
        #expect(series.count == 1)
        #expect(series[0].side == nil)
        #expect(series[0].values.map(\.value) == [28.5, 29])
    }

    @Test("Logging to a point goes to the right store")
    func logToPoint() throws {
        try catalog.log(to: .builtIn(.waist), valueCm: 84, at: at("2026-10-14T08:00:00Z"))
        let owner = try catalog.addPoint(name: "Forearm")
        try catalog.log(to: owner, valueCm: 29, at: at("2026-10-14T08:00:00Z"))
        let range = (at("2026-10-01T00:00:00Z"), at("2026-11-01T00:00:00Z"))
        #expect(try catalog.series(for: .builtIn(.waist), from: range.0, to: range.1).flatMap(\.values).map(\.value) == [84])
        #expect(try catalog.series(for: owner, from: range.0, to: range.1).flatMap(\.values).map(\.value) == [29])
    }
}
