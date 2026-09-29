import Testing
import Foundation
@testable import AlmanacCore

/// `readiness_baseline` persistence. The table has no unique constraint, so
/// "saving twice leaves one row" is a property of the store rather than of the
/// schema, and it is the property worth pinning.
@Suite("ReadinessBaselineStore Tests")
struct ReadinessBaselineStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    private var store: ReadinessBaselineStore { ReadinessBaselineStore(db: db) }

    private func baseline(_ type: ReadinessBaselineContext, rhr: Double, hrv: Double, days: Int) -> ReadinessBaseline {
        ReadinessBaseline(context: type, restingHeartRate: rhr, hrv: hrv, validDayCount: days)
    }

    @Test("A saved baseline round-trips")
    func roundTrip() throws {
        try store.save(baseline(.general, rhr: 58, hrv: 64, days: 28), type: .general,
                       windowStartDate: "2025-09-01", windowEndDate: "2025-09-28", rollingWindowDays: 28)

        let read = try #require(try store.baseline(type: .general))
        #expect(read.type == .general)
        #expect(read.shiftType == nil)
        #expect(read.validDayCount == 28)
        #expect(read.rollingWindowDays == 28)
        #expect(read.averageRestingHeartRate == 58)
        #expect(read.averageHRV == 64)
        #expect(read.windowStartDate == "2025-09-01")
        #expect(read.windowEndDate == "2025-09-28")
        #expect(read.formulaVersion == ReadinessFormula.version)
    }

    @Test("Saving twice replaces rather than accumulating")
    func saveIsIdempotent() throws {
        for rhr in [58.0, 61.0, 55.0] {
            try store.save(baseline(.general, rhr: rhr, hrv: 64, days: 28), type: .general,
                           windowStartDate: "2025-09-01", windowEndDate: "2025-09-28", rollingWindowDays: 28)
        }
        let rows = try db.query("SELECT COUNT(*) AS n FROM readiness_baseline WHERE baselineType = 'general';")
        #expect(rows.first?.int("n") == 1)
        #expect(try store.baseline(type: .general)?.averageRestingHeartRate == 55)
    }

    @Test("Shift-specific baselines are kept apart by their shift type")
    func shiftBaselinesArePerShiftType() throws {
        try store.save(baseline(.shiftSpecific, rhr: 70, hrv: 80, days: 20), type: .shiftSpecific,
                       shiftType: .night, windowStartDate: "2025-09-01", windowEndDate: "2025-09-20",
                       rollingWindowDays: 28)
        try store.save(baseline(.shiftSpecific, rhr: 50, hrv: 60, days: 18), type: .shiftSpecific,
                       shiftType: .day, windowStartDate: "2025-09-01", windowEndDate: "2025-09-18",
                       rollingWindowDays: 28)

        #expect(try store.allBaselines().count == 2)
        #expect(try store.baseline(type: .shiftSpecific, shiftType: .night)?.averageRestingHeartRate == 70)
        #expect(try store.baseline(type: .shiftSpecific, shiftType: .day)?.averageRestingHeartRate == 50)
    }

    @Test("Replacing one shift's baseline leaves the other shift's alone")
    func replacingOneShiftDoesNotTouchAnother() throws {
        try store.save(baseline(.shiftSpecific, rhr: 70, hrv: 80, days: 20), type: .shiftSpecific,
                       shiftType: .night, windowStartDate: "2025-09-01", windowEndDate: "2025-09-20",
                       rollingWindowDays: 28)
        try store.save(baseline(.shiftSpecific, rhr: 50, hrv: 60, days: 18), type: .shiftSpecific,
                       shiftType: .day, windowStartDate: "2025-09-01", windowEndDate: "2025-09-18",
                       rollingWindowDays: 28)
        try store.save(baseline(.shiftSpecific, rhr: 72, hrv: 82, days: 22), type: .shiftSpecific,
                       shiftType: .night, windowStartDate: "2025-09-02", windowEndDate: "2025-09-23",
                       rollingWindowDays: 28)

        #expect(try store.allBaselines().count == 2)
        #expect(try store.baseline(type: .shiftSpecific, shiftType: .night)?.averageRestingHeartRate == 72)
        #expect(try store.baseline(type: .shiftSpecific, shiftType: .day)?.averageRestingHeartRate == 50)
    }

    @Test("A shift-specific baseline with no shift type is refused")
    func shiftSpecificNeedsAShiftType() throws {
        #expect(throws: ReadinessBaselineStoreError.shiftSpecificBaselineNeedsAShiftType) {
            try store.save(baseline(.shiftSpecific, rhr: 70, hrv: 80, days: 20), type: .shiftSpecific,
                           shiftType: nil, windowStartDate: "2025-09-01", windowEndDate: "2025-09-20",
                           rollingWindowDays: 28)
        }
    }

    @Test("A baseline with no numbers stores nulls rather than zeroes")
    func emptyBaselineStoresNulls() throws {
        try store.save(ReadinessBaseline(context: .general, validDayCount: 0), type: .general,
                       windowStartDate: "2025-09-01", windowEndDate: "2025-09-01", rollingWindowDays: 28)
        let read = try #require(try store.baseline(type: .general))
        #expect(read.averageRestingHeartRate == nil)
        #expect(read.averageHRV == nil)
        #expect(read.validDayCount == 0)
    }

    @Test("An absent type reads back as absent, not as a synthesised row")
    func absentTypeIsNil() throws {
        #expect(try store.baseline(type: .ramadan) == nil)
    }
}
