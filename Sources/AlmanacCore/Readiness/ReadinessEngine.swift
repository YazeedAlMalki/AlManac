import Foundation

/// Composes readiness formula v1.0 into a stored score — Technical
/// Specification §9.1 and §9.3-§9.7.
///
/// Split from `ReadinessFormula` so the arithmetic stays independently
/// testable from the wording. The engine decides what is missing, what the
/// user is told, and which precedence rule governs the recommendation; the
/// formula only turns numbers into numbers.
public enum ReadinessEngine {

    /// Computes one readiness record.
    ///
    /// `baseline` supplies the personal RHR/HRV references. A baseline with a
    /// nil metric makes that input unscoreable, which counts as missing —
    /// during the first 21 valid days that is the normal state, and §9.7
    /// requires it be shown as preliminary rather than dressed up.
    public static func evaluate(
        state: ReadinessState,
        inputs: ReadinessInputs,
        baseline: ReadinessBaseline = ReadinessBaseline(),
        context: ReadinessContext = ReadinessContext()
    ) -> ReadinessOutcome {

        let weights = state == .provisional
            ? ReadinessFormula.provisionalWeights
            : ReadinessFormula.finalWeights

        var missing: [ReadinessInputKind] = []
        var contributions: [(weight: Double, score: Double)] = []

        // I1 — sleep duration.
        if let minutes = inputs.sleepDurationMinutes {
            contributions.append((weights.sleepDuration, ReadinessFormula.sleepDurationScore(
                minutes: minutes,
                religiousFastDay: context.religiousFastDay,
                totalAcrossEpisodesMinutes: inputs.totalSleepAcrossEpisodesMinutes
            )))
        } else {
            missing.append(.sleep)
        }

        // I2 — sleep quality. Always weighed; scored 50 when stage data is
        // absent, and flagged so the confidence level reflects the gap.
        contributions.append((weights.sleepQuality, ReadinessFormula.sleepQualityScore(inputs.stages)))
        if inputs.stages == nil { missing.append(.sleepQuality) }

        // I3 — resting heart rate.
        if let current = inputs.restingHeartRate, let base = baseline.restingHeartRate {
            contributions.append((weights.rhr, ReadinessFormula.rhrScore(current: current, baseline: base)))
        } else {
            missing.append(.rhr)
        }

        // I4 — HRV.
        if let current = inputs.hrv, let base = baseline.hrv {
            contributions.append((weights.hrv, ReadinessFormula.hrvScore(current: current, baseline: base)))
        } else {
            missing.append(.hrv)
        }

        // I5 — mood and soreness. Not applicable to a provisional score, so
        // their absence there is not a gap and is not counted as one.
        if state == .final {
            if let mood = inputs.mood, let soreness = inputs.soreness {
                contributions.append((weights.moodSoreness,
                                      ReadinessFormula.moodSorenessScore(mood: mood, soreness: soreness)))
            } else {
                if inputs.mood == nil { missing.append(.mood) }
                if inputs.soreness == nil { missing.append(.soreness) }
            }
        }

        // §9.1 — with duration, stages, RHR and HRV all absent there is nothing
        // personal left to score. A neutral 50 from the quality default alone
        // would be a number about nobody.
        let automaticInputsAllMissing =
            inputs.sleepDurationMinutes == nil &&
            inputs.stages == nil &&
            !(inputs.restingHeartRate != nil && baseline.restingHeartRate != nil) &&
            !(inputs.hrv != nil && baseline.hrv != nil)

        let baselineContext: ReadinessBaselineContext =
            context.calibrationDay != nil ? .calibration : baseline.context

        if automaticInputsAllMissing {
            return ReadinessOutcome(
                state: state,
                score: nil,
                color: .none,
                textDescription: nil,
                confidence: .insufficient,
                missingInputs: missing,
                formulaVersion: ReadinessFormula.version,
                inputSnapshot: snapshot(inputs: inputs, baseline: baseline, context: context),
                recommendation: recommendation(bandText: nil, context: context).text,
                precedenceApplied: recommendation(bandText: nil, context: context).applied,
                baselineContext: baselineContext
            )
        }

        guard var raw = ReadinessFormula.weightedSum(contributions) else {
            return ReadinessOutcome(
                state: state, score: nil, color: .none, textDescription: nil,
                confidence: .insufficient, missingInputs: missing,
                formulaVersion: ReadinessFormula.version,
                inputSnapshot: snapshot(inputs: inputs, baseline: baseline, context: context),
                recommendation: recommendation(bandText: nil, context: context).text,
                precedenceApplied: recommendation(bandText: nil, context: context).applied,
                baselineContext: baselineContext
            )
        }

        if state == .provisional { raw *= ReadinessFormula.provisionalCeiling }
        let score = Int(raw.rounded())
        let band = ReadinessFormula.bandText(for: score)
        let rec = recommendation(bandText: band, context: context)

        return ReadinessOutcome(
            state: state,
            score: score,
            color: ReadinessFormula.color(for: score),
            textDescription: describe(band: band, context: context),
            confidence: ReadinessFormula.confidence(missingCount: missing.count),
            missingInputs: missing,
            formulaVersion: ReadinessFormula.version,
            inputSnapshot: snapshot(inputs: inputs, baseline: baseline, context: context),
            recommendation: rec.text,
            precedenceApplied: rec.applied,
            baselineContext: baselineContext
        )
    }

    // MARK: - §9.4 text

    /// Band text plus the context suffixes that apply, in the spec's order.
    static func describe(band: String, context: ReadinessContext) -> String {
        var suffixes: [String] = []
        if context.religiousFastDay { suffixes.append("· Fasted training context noted") }
        if context.shiftTransition { suffixes.append("· Limited comparable shift data") }
        if context.plannedDeloadDay { suffixes.append("· Planned deload — continue reduced load") }
        if context.plannedRestDay { suffixes.append("· Planned rest day") }
        if let area = context.activeInjuryBodyArea { suffixes.append("· Active injury: \(area)") }
        if let day = context.calibrationDay {
            suffixes.append("· Score is preliminary (calibrating: \(day)/\(ReadinessFormula.calibrationValidDays))")
        }
        guard !suffixes.isEmpty else { return band }
        return band + ". " + suffixes.joined(separator: " ")
    }

    // MARK: - §9.6 precedence

    /// Applies the precedence order. First match decides the wording; every
    /// rule that held is still recorded, so "why did it say that" is
    /// answerable later without recomputing the day.
    static func recommendation(bandText: String?, context: ReadinessContext)
        -> (text: String?, applied: [ReadinessPrecedence]) {

        var applied: [ReadinessPrecedence] = []
        if context.activeInjuryBodyArea != nil && context.injuryAffectsTraining {
            applied.append(.injuryRestriction)
        }
        if context.manualRecoveryDay { applied.append(.manualRecovery) }
        if context.plannedRestDay { applied.append(.restDay) }
        if context.plannedDeloadDay { applied.append(.deload) }
        if context.religiousFastDay && context.fastedSessionPlanned {
            applied.append(.religiousFastContext)
        }

        let fallback = bandText ?? "Not enough data to score readiness."

        switch applied.first {
        case .injuryRestriction:
            // Prepended, not substituted: the score still stands and is still shown.
            let area = context.activeInjuryBodyArea ?? "unspecified area"
            return ("Active injury (\(area)) — train around it. \(fallback).", applied)
        case .manualRecovery:
            return ("Recovery day: rest as planned.", applied)
        case .restDay:
            return ("Rest day as planned.", applied)
        case .deload:
            return ("Deload week: continue reduced load.", applied)
        case .religiousFastContext:
            return ("\(fallback). Session is planned religiously fasted — compared against fasted days only.", applied)
        case nil:
            return (bandText, applied)
        }
    }

    // MARK: - §9.9 snapshot

    /// Every raw value the score used, as deterministic JSON.
    ///
    /// Sorted keys so two snapshots of the same inputs compare equal as
    /// strings — §9.9 requires historical records be comparable, and a
    /// dictionary that serialises in a different order each run is not.
    static func snapshot(inputs: ReadinessInputs,
                         baseline: ReadinessBaseline,
                         context: ReadinessContext) -> String {
        var payload: [String: Any] = [
            "formulaVersion": ReadinessFormula.version,
            "baselineContext": baseline.context.rawValue,
            "baselineValidDayCount": baseline.validDayCount,
            "religiousFastDay": context.religiousFastDay,
            "shiftTransition": context.shiftTransition
        ]
        if let v = inputs.sleepDurationMinutes { payload["sleepDurationMinutes"] = v }
        if let v = inputs.totalSleepAcrossEpisodesMinutes { payload["totalSleepMinutes"] = v }
        if let s = inputs.stages {
            payload["stageDeep"] = s.deep
            payload["stageREM"] = s.rem
            payload["stageCore"] = s.core
        }
        if let v = inputs.restingHeartRate { payload["restingHeartRate"] = v }
        if let v = inputs.hrv { payload["hrv"] = v }
        if let v = inputs.mood { payload["mood"] = v }
        if let v = inputs.soreness { payload["soreness"] = v }
        if let v = baseline.restingHeartRate { payload["baselineRestingHeartRate"] = v }
        if let v = baseline.hrv { payload["baselineHRV"] = v }
        if let v = context.calibrationDay { payload["calibrationDay"] = v }

        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
