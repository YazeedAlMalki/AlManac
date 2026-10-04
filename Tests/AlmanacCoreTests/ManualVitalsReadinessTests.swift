import Testing
import Foundation
@testable import AlmanacCore

/// Hand-entered vitals reaching a readiness score, and that score reaching a
/// prescription — the whole path §6.7's "manual fallback" exists for, pinned
/// against the real stores rather than against `ReadinessEngine` alone.
///
/// The checklist rows this makes drivable (7.10, 7.11) were UNRUN for a
/// specific and stated reason: `ReadinessEngine.evaluate` returns `score: nil`
/// when duration, stages, RHR+baseline and HRV+baseline are all missing, so a
/// simulator with no watch and no sleep episodes had no band to choose and
/// nothing to present. These tests are the core half of removing that reason;
/// `Native/AlmanacUITests/TrainingProgramUITests` is the UI half.
///
/// **Every number here is the formula's own arithmetic, not a target the tests
/// were written to hit.** The scores are derived from the weights and bands in
/// `ReadinessFormula`/`ReadinessAdjustment`, and the values chosen to reach a
/// band are chosen to be *plausible* first — a resting rate and an HRV a person
/// could actually measure.
@Suite("Manual Vitals Reach Readiness")
struct ManualVitalsReadinessTests {
    private let zone = TimeZone(identifier: "Europe/London")!
    private var timeModel: TimeModel { TimeModel(timeZone: zone, boundary: .almanac) }
    private var store: VitalsRecordStore {
        VitalsRecordStore(db: db, zone: ZoneContext(zone), timeModel: timeModel)
    }
    private let db = try! TestDatabase()

    /// Today at 09:00 London — inside today's logical day.
    private func morning(addingDays days: Int = 0) -> Date {
        let today = timeModel.logicalDay(Date())
        var day = today
        for _ in 0..<max(0, days) { day = timeModel.day(before: day) ?? day }
        let start = timeModel.start(of: day)!
        return start.addingTimeInterval(9 * 3600)
    }

    /// Records `days` of ordinary readings, so the days before today have
    /// something in them and `ReadinessBaselineService` has a baseline to mean.
    ///
    /// Without this the baseline *is* today's reading — `meanPerDay` over a
    /// window containing only today returns today's own number — and every
    /// input scores exactly neutral (95 and 75) no matter what was measured. A
    /// score produced that way says nothing, which is why these tests seed
    /// history rather than asserting against it.
    private func seedHistory(rhr: Double, hrv: Double, days: Int = 3) throws {
        for offset in 1...days {
            try store.recordManual(metric: .restingHeartRate, value: rhr,
                                   measuredAt: morning(addingDays: offset))
            try store.recordManual(metric: .heartRateVariability, value: hrv,
                                   measuredAt: morning(addingDays: offset))
        }
    }

    private func record(metric: VitalsMetric, value: Double) throws {
        try store.recordManual(metric: metric, value: value, measuredAt: morning())
    }

    /// A loaded `sets_reps` item, matching the fixture shape
    /// `ReadinessAdjustmentTests` uses so the two files read the same.
    private func item(_ kind: PrescriptionKind) -> PoolItemEntry {
        PoolItemEntry(
            id: 1, programDayId: 1, exerciseCatalogId: 1, rotationPosition: 0,
            positionWithinSession: 0, isActive: true, prescriptionType: kind.rawValue,
            containerType: nil, prescribedSets: 4, prescribedReps: 10,
            prescribedLoadKg: 60, prescribedDurationSeconds: nil,
            prescribedRestSeconds: 90, progressionEnabled: false,
            progressionIncrementKg: nil, progressionCondition: nil, notes: nil,
            deletedAt: nil, createdAt: "", updatedAt: "")
    }

    private func score() throws -> ReadinessOutcome {
        let today = timeModel.logicalDay(Date())
        let resolution = try ReadinessBaselineService(db: db, timeModel: timeModel).resolve(for: today)
        let cycleStart = morning()
        return ReadinessEngine.evaluate(
            state: .provisional,
            inputs: ReadinessInputs(
                // No episode, so no measured duration — the honest state for a
                // person with no watch, and §9.2's imputed neutral rather than a
                // substitute zero.
                sleepDurationMinutes: nil,
                restingHeartRate: try store.latestValue(for: .restingHeartRate, since: cycleStart)?.value,
                hrv: try store.latestValue(for: .heartRateVariability, since: cycleStart)?.value
            ),
            baseline: resolution.baseline
        )
    }

    // MARK: - The gap manual entry closes

    @Test("Two hand-typed numbers are enough to produce a score; without them there is none")
    func manualReadingsAloneYieldAScore() throws {
        // The state the checklist records as the reason 7.10/7.11 were undrivable.
        let withoutVitals = ReadinessEngine.evaluate(
            state: .provisional,
            inputs: ReadinessInputs(),
            baseline: ReadinessBaseline(restingHeartRate: 52, hrv: 55)
        )
        #expect(withoutVitals.score == nil,
                "no reading and no baseline pair is §9.1's insufficient-data branch")

        try seedHistory(rhr: 52, hrv: 55)
        try record(metric: .restingHeartRate, value: 52)
        try record(metric: .heartRateVariability, value: 55)

        let outcome = try score()
        #expect(outcome.score != nil)
        #expect(outcome.confidence != .insufficient)
        // Sleep duration and stage quality are still missing, and the engine says
        // so rather than quietly treating them as measured.
        #expect(outcome.missingInputs.contains(.sleep))
        #expect(outcome.missingInputs.contains(.sleepQuality))
    }

    // MARK: - 7.10, the Yes leg

    @Test("A middling day lands in the moderate band and visibly lowers the prescription")
    func moderateBandLowersThePrescription() throws {
        try seedHistory(rhr: 52, hrv: 55)
        // Slightly off the baseline: `rhrScore` 85 (delta +1.5) and `hrvScore`
        // 50 (-7%). Both ordinary readings a person could measure, and together
        // they land the day in the middle of the scale — where the band says
        // "train at reduced intensity" rather than "rest", which is the
        // distinction 7.10 is about.
        try record(metric: .restingHeartRate, value: 54)
        try record(metric: .heartRateVariability, value: 50)

        let outcome = try score()
        let value = try #require(outcome.score)
        #expect(ReadinessBand.band(for: value) == .moderate,
                "score \(value) is \(ReadinessBand.band(for: value)), not moderate")

        // §9.3's own copy for the band, so the assertion cannot drift from what
        // the card would say.
        #expect(ReadinessFormula.bandText(for: value) == "Moderate recovery — train at reduced intensity")

        let prescription = ReadinessAdjustment.prescription(for: item(.repsLoad), score: value)
        #expect(prescription.isAdjusted)
        #expect(!prescription.isRestDay, "moderate is a smaller session, not none")
        #expect(prescription.sets == 3, "4 sets at the moderate volume factor is 3, not 0")
        let changed = prescription.changes.map(\.field)
        #expect(changed.contains(.sets))
        #expect(changed.contains(.loadKg))
    }

    // MARK: - 7.11, the rest day

    @Test("A very low day is a rest day, not a smaller session")
    func veryLowBandIsARestDay() throws {
        try seedHistory(rhr: 52, hrv: 55)
        // Far outside the baseline on both terms: `rhrScore` 15 (delta beyond
        // +6) and `hrvScore` 10 (past -25%). The floor of both terms is what the
        // band is named after, and §9.3's copy for it says rest rather than less.
        try record(metric: .restingHeartRate, value: 64)
        try record(metric: .heartRateVariability, value: 34)

        let outcome = try score()
        let value = try #require(outcome.score)
        #expect(ReadinessBand.band(for: value) == .veryLow,
                "score \(value) is \(ReadinessBand.band(for: value)), not very low")
        #expect(ReadinessFormula.bandText(for: value)
            == "Recovery is very low — rest is the best training decision")

        let prescription = ReadinessAdjustment.prescription(for: item(.repsLoad), score: value)
        // The distinction the whole row rests on: nil sets is the rest day, and
        // it is not the same thing as zero sets.
        #expect(prescription.isRestDay)
        #expect(prescription.sets == nil)
        if case .restDay = prescription.policy {} else {
            Issue.record("expected a rest-day policy, got \(prescription.policy)")
        }
    }

    @Test("Both bands come from the numbers, not from which screen asked")
    func bandFollowsTheReadingRatherThanTheRoute() throws {
        // The same two entries, one day's worth, and only the values differ. If
        // the band tracked anything but the readings, these two would agree.
        try seedHistory(rhr: 52, hrv: 55)
        // Both terms clearly better than the baseline: `rhrScore` 100 and
        // `hrvScore` 100, the best each term can score.
        try record(metric: .restingHeartRate, value: 49)
        try record(metric: .heartRateVariability, value: 70)
        let ordinary = try #require(try score().score)
        #expect(ReadinessBand.band(for: ordinary) == .good,
                "a day better than baseline on both terms is \\(ReadinessBand.band(for: ordinary)), not good")

        try record(metric: .restingHeartRate, value: 64)
        try record(metric: .heartRateVariability, value: 34)
        let rough = try #require(try score().score)
        #expect(ReadinessBand.band(for: rough) == .veryLow)
        #expect(rough < ordinary)
    }
}
