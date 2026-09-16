import XCTest
@testable import AlmanacCore

/// Technical Specification §9 and Appendix A — readiness formula v1.0.
///
/// The arithmetic tests pin the published numbers so a future formula change
/// has to be deliberate (§9.9 forbids silent rewrites). The behavioural tests
/// cover the two failure modes the BRD names by risk: R-RDY, a missing input
/// scored as a bad one, and the precedence rules that stop a high score
/// telling the user to train through a rest day.
final class ReadinessEngineTests: XCTestCase {

    private let goodStages = SleepStageBreakdown(deep: 0.25, rem: 0.25, core: 0.50)
    private let baseline = ReadinessBaseline(context: .general, restingHeartRate: 52,
                                             hrv: 60, validDayCount: 40)

    private func perfectInputs(mood: Int? = nil, soreness: Int? = nil) -> ReadinessInputs {
        ReadinessInputs(sleepDurationMinutes: 480, stages: goodStages,
                        restingHeartRate: 48, hrv: 70, mood: mood, soreness: soreness)
    }

    // MARK: - §9.2 input scoring

    func testSleepDurationBands() {
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 200), 10)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 270), 30)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 330), 55)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 390), 75)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 480), 100)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 570), 90)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 660), 75)
    }

    func testRamadanModifierRewardsFragmentedSleepOnlyOnFastDays() {
        // Five and a half hours in three pieces during Ramadan is not the same
        // failure as five and a half hours on an ordinary night.
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(minutes: 330), 55)
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(
            minutes: 330, religiousFastDay: true, totalAcrossEpisodesMinutes: 330), 65)
        // Below five hours total, the modifier does not apply.
        XCTAssertEqual(ReadinessFormula.sleepDurationScore(
            minutes: 250, religiousFastDay: true, totalAcrossEpisodesMinutes: 250), 30)
    }

    func testQualityScoreWeightsDeepAndREMAboveCore() {
        XCTAssertEqual(ReadinessFormula.sleepQualityScore(goodStages), 97.5, accuracy: 0.01)
        let coreHeavy = SleepStageBreakdown(deep: 0.05, rem: 0.10, core: 0.85)
        XCTAssertLessThan(ReadinessFormula.sleepQualityScore(coreHeavy), 80)
    }

    func testQualityWithoutStageDataIsNeutralFiftyNotZero() {
        XCTAssertEqual(ReadinessFormula.sleepQualityScore(nil), 50)
    }

    func testRHRAndHRVScoreAgainstBaseline() {
        XCTAssertEqual(ReadinessFormula.rhrScore(current: 48, baseline: 52), 100)
        XCTAssertEqual(ReadinessFormula.rhrScore(current: 53, baseline: 52), 85)
        XCTAssertEqual(ReadinessFormula.rhrScore(current: 60, baseline: 52), 15)
        XCTAssertEqual(ReadinessFormula.hrvScore(current: 70, baseline: 60), 100)
        XCTAssertEqual(ReadinessFormula.hrvScore(current: 58, baseline: 60), 75)
        XCTAssertEqual(ReadinessFormula.hrvScore(current: 38, baseline: 60), 10)
    }

    func testSorenessIsInverted() {
        XCTAssertEqual(ReadinessFormula.moodSorenessScore(mood: 9, soreness: 2), 85)
        XCTAssertEqual(ReadinessFormula.moodSorenessScore(mood: 9, soreness: 9), 50)
    }

    // MARK: - §9.1 composition

    func testProvisionalIsCappedAtNinety() {
        let outcome = ReadinessEngine.evaluate(state: .provisional, inputs: perfectInputs(),
                                               baseline: baseline)
        XCTAssertEqual(outcome.score, 90,
                       "a score before the check-in must not read as a complete picture")
        XCTAssertEqual(outcome.confidence, .high)
        XCTAssertEqual(outcome.color, .green)
    }

    func testFinalIncludesMoodAndSoreness() {
        let outcome = ReadinessEngine.evaluate(state: .final,
                                               inputs: perfectInputs(mood: 9, soreness: 2),
                                               baseline: baseline)
        XCTAssertEqual(outcome.score, 98)
        XCTAssertEqual(outcome.confidence, .high)
        XCTAssertTrue(outcome.missingInputs.isEmpty)
    }

    func testProvisionalDoesNotCountMoodAndSorenessAsMissing() {
        let outcome = ReadinessEngine.evaluate(state: .provisional, inputs: perfectInputs(),
                                               baseline: baseline)
        XCTAssertFalse(outcome.missingInputs.contains(.mood))
        XCTAssertFalse(outcome.missingInputs.contains(.soreness))
    }

    /// R-RDY, stated as a test: a missing reading must not be scored as a bad
    /// reading. The redistributed score has to beat the same day with a
    /// genuinely poor HRV.
    func testMissingHRVRedistributesRatherThanScoringZero() {
        var withoutHRV = perfectInputs(mood: 9, soreness: 2)
        withoutHRV.hrv = nil
        let missing = ReadinessEngine.evaluate(state: .final, inputs: withoutHRV, baseline: baseline)

        var poorHRV = perfectInputs(mood: 9, soreness: 2)
        poorHRV.hrv = 38   // −37% against baseline: the worst band
        let poor = ReadinessEngine.evaluate(state: .final, inputs: poorHRV, baseline: baseline)

        XCTAssertEqual(missing.score, 98)
        XCTAssertEqual(poor.score, 80)
        XCTAssertGreaterThan(missing.score!, poor.score!,
                             "absent data must never be worse than bad data")
        XCTAssertEqual(missing.missingInputs, [.hrv])
        XCTAssertEqual(missing.confidence, .medium)
    }

    func testBaselineWithoutAMetricMakesThatInputMissing() {
        // During calibration there is no personal RHR baseline yet, so a
        // reading exists but cannot be scored against anything.
        let empty = ReadinessBaseline(context: .general, restingHeartRate: nil, hrv: nil)
        let outcome = ReadinessEngine.evaluate(state: .provisional, inputs: perfectInputs(),
                                               baseline: empty)
        XCTAssertTrue(outcome.missingInputs.contains(.rhr))
        XCTAssertTrue(outcome.missingInputs.contains(.hrv))
        XCTAssertEqual(outcome.confidence, .low)
        XCTAssertNotNil(outcome.score, "sleep alone is still enough to score")
    }

    func testConfidenceTiers() {
        XCTAssertEqual(ReadinessFormula.confidence(missingCount: 0), .high)
        XCTAssertEqual(ReadinessFormula.confidence(missingCount: 1), .medium)
        XCTAssertEqual(ReadinessFormula.confidence(missingCount: 2), .low)
        XCTAssertEqual(ReadinessFormula.confidence(missingCount: 4), .veryLow)
    }

    /// Acceptance scenario A5: with nothing automatic available the score is
    /// null and says so. It is never zero, and never a confident 50.
    func testNoAutomaticInputsYieldsNullAndInsufficient() {
        let outcome = ReadinessEngine.evaluate(state: .final, inputs: ReadinessInputs(),
                                               baseline: ReadinessBaseline())
        XCTAssertNil(outcome.score)
        XCTAssertEqual(outcome.confidence, .insufficient)
        XCTAssertEqual(outcome.color, .none)
        XCTAssertNil(outcome.textDescription)
        XCTAssertTrue(outcome.missingInputs.contains(.sleep))
        XCTAssertTrue(outcome.missingInputs.contains(.hrv))
    }

    // MARK: - §9.3 / §9.4

    func testColourBands() {
        XCTAssertEqual(ReadinessFormula.color(for: 70), .green)
        XCTAssertEqual(ReadinessFormula.color(for: 69), .yellow)
        XCTAssertEqual(ReadinessFormula.color(for: 40), .yellow)
        XCTAssertEqual(ReadinessFormula.color(for: 39), .red)
        XCTAssertEqual(ReadinessFormula.color(for: nil), .none)
    }

    func testCalibrationSuffixAndBaselineContext() {
        let context = ReadinessContext(calibrationDay: 7)
        let outcome = ReadinessEngine.evaluate(state: .provisional, inputs: perfectInputs(),
                                               baseline: baseline, context: context)
        XCTAssertEqual(outcome.baselineContext, .calibration)
        XCTAssertTrue(outcome.textDescription!.contains("calibrating: 7/21"),
                      "got: \(outcome.textDescription!)")
    }

    func testShiftTransitionSuffixDoesNotDiagnose() {
        let outcome = ReadinessEngine.evaluate(
            state: .final, inputs: perfectInputs(mood: 8, soreness: 3),
            baseline: baseline, context: ReadinessContext(shiftTransition: true))
        XCTAssertTrue(outcome.textDescription!.contains("Limited comparable shift data"))
    }

    // MARK: - §9.6 precedence

    /// The spec's own example: a 90-plus score on a deload day must not turn
    /// into "train hard".
    func testHighScoreOnADeloadDayStillSaysDeload() {
        let outcome = ReadinessEngine.evaluate(
            state: .final, inputs: perfectInputs(mood: 9, soreness: 2),
            baseline: baseline, context: ReadinessContext(plannedDeloadDay: true))

        XCTAssertEqual(outcome.score, 98)
        XCTAssertEqual(outcome.recommendation, "Deload week: continue reduced load.")
        XCTAssertTrue(outcome.textDescription!.contains("Recovery is excellent"))
        XCTAssertTrue(outcome.textDescription!.contains("Planned deload"))
        XCTAssertEqual(outcome.precedenceApplied, [.deload])
    }

    func testRestDayOutranksDeload() {
        let outcome = ReadinessEngine.evaluate(
            state: .final, inputs: perfectInputs(mood: 9, soreness: 2), baseline: baseline,
            context: ReadinessContext(plannedRestDay: true, plannedDeloadDay: true))
        XCTAssertEqual(outcome.recommendation, "Rest day as planned.")
        XCTAssertEqual(outcome.precedenceApplied, [.restDay, .deload],
                       "both held; the first one decided the wording")
    }

    func testInjuryPrependsWithoutSuppressingTheScore() {
        let outcome = ReadinessEngine.evaluate(
            state: .final, inputs: perfectInputs(mood: 9, soreness: 2), baseline: baseline,
            context: ReadinessContext(activeInjuryBodyArea: "left shoulder",
                                      injuryAffectsTraining: true))
        XCTAssertEqual(outcome.score, 98, "§9.6: the injury note is prepended, not a suppression")
        XCTAssertTrue(outcome.recommendation!.hasPrefix("Active injury (left shoulder)"))
        XCTAssertEqual(outcome.precedenceApplied.first, .injuryRestriction)
    }

    func testInactiveInjuryDoesNotChangeTheRecommendation() {
        let outcome = ReadinessEngine.evaluate(
            state: .final, inputs: perfectInputs(mood: 9, soreness: 2), baseline: baseline,
            context: ReadinessContext(activeInjuryBodyArea: "left shoulder",
                                      injuryAffectsTraining: false))
        XCTAssertTrue(outcome.precedenceApplied.isEmpty)
    }

    // MARK: - §9.7 calibration validity

    func testValidCalibrationDayNeedsSleepOrBothVitals() {
        XCTAssertTrue(ReadinessFormula.isValidCalibrationDay(hasSleepData: true, hasRHR: false, hasHRV: false))
        XCTAssertTrue(ReadinessFormula.isValidCalibrationDay(hasSleepData: false, hasRHR: true, hasHRV: true))
        XCTAssertFalse(ReadinessFormula.isValidCalibrationDay(hasSleepData: false, hasRHR: true, hasHRV: false))
        XCTAssertFalse(ReadinessFormula.isValidCalibrationDay(hasSleepData: false, hasRHR: false, hasHRV: false))
    }

    // MARK: - §9.9 snapshot

    func testSnapshotIsDeterministicAndOmitsAbsentInputs() {
        let a = ReadinessEngine.evaluate(state: .provisional, inputs: perfectInputs(), baseline: baseline)
        let b = ReadinessEngine.evaluate(state: .provisional, inputs: perfectInputs(), baseline: baseline)
        XCTAssertEqual(a.inputSnapshot, b.inputSnapshot,
                       "two runs of the same inputs must compare equal as strings")
        XCTAssertFalse(a.inputSnapshot.contains("\"mood\""),
                       "an absent input is left out, not written as null or zero")
        XCTAssertTrue(a.inputSnapshot.contains("\"formulaVersion\":\"1.0\""))
    }
}
