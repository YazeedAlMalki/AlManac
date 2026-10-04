import Foundation

/// The vitals a person can enter by hand, and the words Almanac uses for them.
///
/// BRD §6.7: "Resting HR, HRV, workout HR, steps, active energy — imported
/// (HealthKit-authoritative, Section 5.2) with **manual fallback**." Until now
/// nothing in the app fell back: `vitals_record` was written only by
/// `VitalsRecordHealthBridge`, so a person without a watch — or one whose HRV
/// permission was declined, which §5.2's own scenario names — could never
/// produce a readiness score at all.
///
/// **Two metrics, because those are the two readiness scores.** `ReadinessEngine`
/// weighs `rhr` and `hrv` and nothing else from this table, so these two are
/// what turns "Almanac cannot produce a defensible score" into a score for
/// someone with no other source. Steps and active energy have no readiness term
/// and no screen that would ask for them by hand; offering a control with
/// nothing on the other side of it is how this app ends up with a settings
/// screen full of switches.
///
/// **Not the whole `vitals_record` vocabulary, and the raw values are the
/// contract.** The bridge also writes `steps`, `activeEnergy` and `restingEnergy`;
/// `HealthSummaryStore` and `TrackingTimeline` read their own sets. What matters
/// is that these `rawValue`s are byte-for-byte the strings every one of those
/// readers uses, because a rename here silently stops every already-recorded row
/// from being found by `ReadinessBaselineService`, `ReadinessModel` and the
/// dashboard at once, and the only symptom is that a score quietly loses an
/// input. `VitalsManualEntryTests.theVocabularyMatchesTheSyncedVocabulary` pins
/// it against the bridge through its public API.
public enum VitalsMetric: String, CaseIterable, Sendable, Hashable, Codable {
    /// §5.19's `rhr`. Beats per minute.
    case restingHeartRate = "rhr"
    /// §5.19's `hrv`. Milliseconds. Almanac stores the bridge's HRV reading
    /// under `hrv`, not the spec table's `hrv_sdnn`; see
    /// `docs/architecture/spec-reconciliation.md`.
    case heartRateVariability = "hrv"

    public var displayName: String {
        switch self {
        case .restingHeartRate: return "Resting heart rate"
        case .heartRateVariability: return "Heart-rate variability"
        }
    }

    /// The unit this metric is stored and shown in, taken from the same table
    /// `VitalsRecordHealthBridge` uses so a hand-entered reading and a synced
    /// one are the same string rather than two spellings of one number.
    public var unit: String {
        switch self {
        case .restingHeartRate: return "bpm"
        case .heartRateVariability: return "ms"
        }
    }

    /// A guard against a mistyped number, **not a clinical range.**
    ///
    /// Nothing here claims what is normal for anybody; it only catches the
    /// failures a keyboard actually produces — a trailing zero, a swapped unit,
    /// a number typed into the wrong field. `BodyMeasurementType.plausibleRange`
    /// is the precedent and the wording: an out-of-band value is refused by
    /// default, the editor offers "save anyway", and a deliberate reading is
    /// never blocked by a bound this repository invented.
    public var plausibleRange: ClosedRange<Double> {
        switch self {
        case .restingHeartRate: return 25...250
        case .heartRateVariability: return 1...500
        }
    }
}

/// Why a hand-entered reading was refused. Typed rather than a raw SQLite
/// failure, because every one of these is a mistake at the keyboard rather than
/// a fault in the data, and each has something the editor can do about it.
public enum VitalsEntryError: Error, LocalizedError, Sendable, Hashable {
    /// Not a usable reading at all: empty, zero, negative, NaN or infinite.
    /// Carries the metric because the message names the unit, and the two units
    /// are the only thing distinguishing the two prompts.
    case invalidValue(VitalsMetric)
    /// A number, but outside `VitalsMetric.plausibleRange`. Recoverable — the
    /// caller asks. Deliberately unit-free: "Save anyway?" is a question about
    /// whether the number is real, and quoting a range back at the person would
    /// be quoting a bound this repository invented.
    case unusuallySized
    /// The row came from Apple Health. A synced reading is retracted by Apple
    /// Health, and the sync writes `deletedAt` for exactly that; editing it here
    /// would be overwritten by the next sync and would misreport where the
    /// number came from in the meantime.
    case notManual
    /// The row is gone. Distinct from `notManual` because the two need opposite
    /// words: "Apple Health owns this one" is a reason, while "it no longer
    /// exists" means the edit was aimed at a row another change had already
    /// removed, and retrying it will fail the same way.
    case notFound
    /// The row is hand-entered but not of a metric a person can enter.
    /// `vitals_record` also holds `steps` and `activeEnergy` as manual drafts
    /// from before the vocabulary was typed, and correcting one of those must
    /// fail loudly: there is no plausible range to check the new value against,
    /// and borrowing another metric's would reject an ordinary step count.
    /// Only `update` raises this — `delete` validates nothing, so it has nothing
    /// to get wrong.
    case notHandEnterable

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let metric):
            return metric == .restingHeartRate
                ? "Enter a resting heart rate in beats per minute."
                : "Enter a heart-rate variability in milliseconds."
        case .unusuallySized: return "That looks unusually low or high. Save anyway?"
        case .notManual: return "This reading came from Apple Health, so it is corrected by correcting it there."
        case .notFound: return "That reading is no longer there."
        case .notHandEnterable: return "That reading is not one you can enter by hand."
        }
    }
}
