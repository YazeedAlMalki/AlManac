import Foundation

/// §9.3's readiness bands, named.
///
/// **The edges are `ReadinessFormula`'s, not new ones.** 70 and 40 are its named
/// `readyThreshold` and `compromisedThreshold`; 85, 55 and 25 are the edges its
/// `bandText(for:)` already draws. They are spelled out here because Swift will
/// not take a `static let` as an enum raw value, and `ReadinessAdjustmentTests`
/// pins all six against `bandText` — so a band edge that moves in the formula
/// without moving here fails the suite instead of quietly teaching the training
/// table a different scale from the readiness card.
public enum ReadinessBand: Int, Sendable, Hashable, CaseIterable {
    case excellent = 85
    case good = 70
    case moderate = 55
    case belowBaseline = 40
    case poor = 25
    case veryLow = 0

    /// The band a score falls in. Every score has one, including 0 and 100 —
    /// a readiness score is never "outside" the scale, so this never fails.
    public static func band(for score: Int) -> ReadinessBand {
        allCases
            .filter { score >= $0.rawValue }
            .max(by: { $0.rawValue < $1.rawValue })
            ?? .veryLow
    }
}

/// What a readiness band does to a prescription, resolved against its type.
///
/// Two outcomes that are not a scaling, because they are not a smaller version of
/// the same thing: `.unchanged` is the program as written, `.restDay` is no
/// prescription at all.
public enum ReadinessAdjustmentPolicy: Sendable, Hashable {
    case unchanged
    case restDay
    /// Volume, complexity and rest, each with its own factor. All three are
    /// positive; `rest` is never below 1, because there is no reading of a bad
    /// day on which the app should *shorten* the user's rest.
    case scale(volume: Double, complexity: Double, rest: Double)
}

/// One prescription field that moved, with the value it had and the value it now
/// has.
///
/// Both as `Double?` so one type covers a count of sets and a duration, and both
/// optional so a field the prescription never had reads as absent rather than as
/// having been set to zero — the substitution §9.1's nil-score rule forbids.
public struct PrescriptionChange: Sendable, Hashable, Identifiable {
    public enum Field: String, Sendable, Hashable, CaseIterable {
        case sets, reps, loadKg, durationSeconds, restSeconds
    }

    public let field: Field
    public let was: Double?
    public let now: Double?

    public var id: String { field.rawValue }

    public init(field: Field, was: Double?, now: Double?) {
        self.field = field
        self.was = was
        self.now = now
    }
}

/// A prescription after the readiness band has had its say. Never written back
/// to the pool — this is what one session does, not what the program says.
public struct AdjustedPrescription: Sendable, Hashable {
    public let sets: Int?
    public let reps: Int?
    public let loadKg: Double?
    public let durationSeconds: Double?
    public let restSeconds: Double?
    /// Nil when there was no score. Not "a low score" — §9.1's
    /// insufficient-data branch is *no opinion*, and a no-op is the only honest
    /// reading of it.
    public let band: ReadinessBand?
    public let policy: ReadinessAdjustmentPolicy
    /// Every field that actually moved. The sheet needs this, because a session
    /// that silently shows 3 sets where the program says 4 has changed the user's
    /// own plan without saying so.
    public let changes: [PrescriptionChange]

    public var isAdjusted: Bool { !changes.isEmpty }
    public var isRestDay: Bool {
        if case .restDay = policy { return true }
        return false
    }

    public init(sets: Int?, reps: Int?, loadKg: Double?, durationSeconds: Double?,
                restSeconds: Double?, band: ReadinessBand?,
                policy: ReadinessAdjustmentPolicy, changes: [PrescriptionChange]) {
        self.sets = sets
        self.reps = reps
        self.loadKg = loadKg
        self.durationSeconds = durationSeconds
        self.restSeconds = restSeconds
        self.band = band
        self.policy = policy
        self.changes = changes
    }
}

/// Readiness coupling — how a day's readiness score changes its prescription.
///
/// ## This table is reconstructed, and is meant to be overruled
///
/// `prescription-model-v0.1.md` was never committed to this repository, so the
/// twelve-row coupling table went with it (`docs/features/training.md` §1). Two
/// rules survived into `docs/almanac-technical-spec-v1_0.md:377`:
///
/// > `release` is the only type that should ever *increase* on a low‑readiness
/// > day; `quality_reps` holds volume and drops complexity rather than reducing
/// > work.
///
/// Those two are implemented *because they were decided*, and
/// `ReadinessAdjustmentTests` asserts them as properties across all twelve types
/// and all six bands, so neither can be quietly broken by adding a row.
///
/// Every other number here was chosen by this file. That is a deliberate,
/// documented gap rather than an omission, for the same reason
/// `CONTEXT.md` leaves macro targets unset: **this repository does not invent a
/// number nobody chose.** The overrule path is one line — the four factors in
/// `BandRule` below — and the test that says so is
/// `policyIsTotal`, which fails if a band ever stops scaling down.
public enum ReadinessAdjustment {

    /// One row of the reconstructed table: a band's own factors, plus the one
    /// that goes the other way.
    ///
    /// Four numbers rather than three because `release` is the whole exception to
    /// the direction of this table, and burying it in a `switch` three functions
    /// away is how an exception gets lost.
    public struct BandRule: Sendable, Hashable {
        /// Sets and reps. **Nil is not 1.0 — it is the rest day**: this is the
        /// band §9.3's own copy answers with "rest is the best training
        /// decision", and prescribing a lighter session instead would be the app
        /// overruling a recovery signal it cannot measure properly.
        public let volume: Double?
        /// Load and time under tension. Never nil: on the rest day it is
        /// irrelevant, and on every other day there is something to take off.
        public let complexity: Double
        /// Lengthening rest is the one adjustment that is always safe, so it is
        /// never below 1.
        public let rest: Double
        /// `release` work — duration, passes per site — on the same band. This
        /// is the only factor above 1 that is not "do less of the work".
        public let release: Double?

        public init(volume: Double?, complexity: Double, rest: Double, release: Double?) {
            self.volume = volume
            self.complexity = complexity
            self.rest = rest
            self.release = release
        }
    }

    /// **The reconstructed table.** Six rows, four numbers, and the two places it
    /// is meant to be argued with.
    ///
    /// Reading it: `.good` and above are `1.0` throughout, because a good day is
    /// not a reason to exceed the program — that is what
    /// `ExerciseProgression` is for, and a readiness score is not permission to
    /// do more than the user planned. `.moderate` onward trades volume first and
    /// complexity second, so the first thing to go is the part that costs
    /// recovery and least progress.
    public static let table: [ReadinessBand: BandRule] = [
        .excellent: BandRule(volume: 1.0, complexity: 1.0, rest: 1.0, release: 1.0),
        .good: BandRule(volume: 1.0, complexity: 1.0, rest: 1.0, release: 1.0),
        .moderate: BandRule(volume: 0.85, complexity: 0.9, rest: 1.1, release: 1.0),
        .belowBaseline: BandRule(volume: 0.7, complexity: 0.75, rest: 1.25, release: 1.25),
        .poor: BandRule(volume: 0.5, complexity: 0.6, rest: 1.5, release: 1.5),
        .veryLow: BandRule(volume: nil, complexity: 0.6, rest: 1.5, release: nil),
    ]

    // MARK: - Granularity

    /// Reconstructed: the finest load step worth suggesting without asking what
    /// plates the user owns. Applied **down**, always — see `roundDown`.
    static let loadStepKg = 0.5
    /// Reconstructed: the finest duration worth reading off a stopwatch for a
    /// hold or a release.
    static let durationStepSeconds = 5.0

    // MARK: - Policy

    /// How one type on one band is adjusted.
    ///
    /// The two surviving rules are matched **before** the band table, because they
    /// are rules about a *type* and would otherwise have to be a per-type column
    /// in a table that is otherwise purely per-band. Total over every one of the
    /// twelve kinds and six bands — there is no "no rule" case, because an
    /// exercise with no readiness coupling is not a thing the table can express.
    public static func policy(for kind: PrescriptionKind, band: ReadinessBand) -> ReadinessAdjustmentPolicy {
        guard let row = table[band] else { return .unchanged }
        switch kind {
        case .release:
            // "the only type that should ever *increase* on a low-readiness day".
            // It increases from `.belowBaseline` down, not from `.moderate`: a
            // merely moderate day is a reason to train differently, not a reason
            // to add recovery work the user did not ask for.
            guard let release = row.release else { return .restDay }
            return .scale(volume: release, complexity: release, rest: row.rest)
        case .qualityReps:
            // "holds volume and drops complexity rather than reducing work". The
            // volume factor is pinned at 1 and only complexity moves — the whole
            // point of the rule is that a tired set of quality reps is still a set
            // of quality reps, just lighter.
            guard row.volume != nil else { return .restDay }
            return .scale(volume: 1.0, complexity: row.complexity, rest: row.rest)
        default:
            guard let volume = row.volume else { return .restDay }
            return .scale(volume: volume, complexity: row.complexity, rest: row.rest)
        }
    }

    // MARK: - Prescription

    /// A pool item's prescription, adjusted for a readiness score.
    ///
    /// Pure, and it writes nothing. The pool is the user's own plan; applying an
    /// adjustment to a *session* writes a bout, and if it rewrote the pool then
    /// the next good day would inherit a bad day's numbers and the rotation would
    /// be quietly weaker for ever. `adjustmentIsPure` pins this.
    ///
    /// Fields the prescription does not use are not invented — a hold has no sets
    /// and no load, and scaling an absent field would put a number in front of the
    /// user for a question the exercise never asked.
    public static func prescription(for item: PoolItemEntry, score: Int?) -> AdjustedPrescription {
        guard let score else {
            return AdjustedPrescription(
                sets: item.prescribedSets, reps: item.prescribedReps,
                loadKg: item.prescribedLoadKg, durationSeconds: item.prescribedDurationSeconds,
                restSeconds: item.prescribedRestSeconds,
                band: nil, policy: .unchanged, changes: [])
        }
        let band = ReadinessBand.band(for: score)
        // A type this build has never heard of is left exactly as written. Its
        // numbers may not mean what we would assume they mean, and guessing is
        // worse than doing nothing.
        guard let kind = PrescriptionKind(rawValue: item.prescriptionType) else {
            return AdjustedPrescription(
                sets: item.prescribedSets, reps: item.prescribedReps,
                loadKg: item.prescribedLoadKg, durationSeconds: item.prescribedDurationSeconds,
                restSeconds: item.prescribedRestSeconds,
                band: band, policy: .unchanged, changes: [])
        }
        let policy = policy(for: kind, band: band)

        guard case .scale(let volume, let complexity, let rest) = policy else {
            return AdjustedPrescription(
                sets: nil, reps: nil, loadKg: nil, durationSeconds: nil, restSeconds: nil,
                band: band, policy: policy, changes: [])
        }

        let sets = item.prescribedSets.map { scaledCount(Double($0), by: volume) }
        let reps = item.prescribedReps.map { scaledCount(Double($0), by: volume) }
        let loadKg = item.prescribedLoadKg.map { roundDown($0 * complexity, step: loadStepKg) }
        let durationSeconds = item.prescribedDurationSeconds.map {
            max(durationStepSeconds, roundDown($0 * complexity, step: durationStepSeconds))
        }
        let restSeconds = item.prescribedRestSeconds.map {
            roundUp($0 * rest, step: durationStepSeconds)
        }

        // Recorded from what actually moved, not from the policy: a factor of 1.0
        // is still `.scale`, and reporting "load 100 → 100" on a good morning
        // would train the user to ignore the whole panel.
        var changes: [PrescriptionChange] = []
        if let was = item.prescribedSets, let now = sets, Int64(now) != Int64(was) {
            changes.append(.init(field: .sets, was: Double(was), now: Double(now)))
        }
        if let was = item.prescribedReps, let now = reps, Int64(now) != Int64(was) {
            changes.append(.init(field: .reps, was: Double(was), now: Double(now)))
        }
        if let was = item.prescribedLoadKg, let now = loadKg, now != was {
            changes.append(.init(field: .loadKg, was: was, now: now))
        }
        if let was = item.prescribedDurationSeconds, let now = durationSeconds, now != was {
            changes.append(.init(field: .durationSeconds, was: was, now: now))
        }
        if let was = item.prescribedRestSeconds, let now = restSeconds, now != was {
            changes.append(.init(field: .restSeconds, was: was, now: now))
        }

        return AdjustedPrescription(
            sets: sets, reps: reps, loadKg: loadKg, durationSeconds: durationSeconds,
            restSeconds: restSeconds, band: band, policy: policy, changes: changes)
    }

    // MARK: - Arithmetic

    /// A count of sets or reps, scaled **down** and never to nothing.
    ///
    /// The floor is what makes a 0.85 factor on one set mean "one set" instead of
    /// "no session": doing less has to mean doing some.
    private static func scaledCount(_ value: Double, by factor: Double) -> Int {
        max(1, Int(floor(value * factor)))
    }

    /// Never rounds **up**. Rounding up is the one thing this whole table cannot
    /// do: a factor of 0.85 on three reps is 2.55, and 2.55 → 3 means the day the
    /// app decided was bad prescribed exactly as much work as a good one.
    private static func roundDown(_ value: Double, step: Double) -> Double {
        (value / step).rounded(.down) * step
    }

    /// Rest is the exception to the rounding direction, and deliberately so. Every
    /// other quantity rounds down because the app must never ask for more work
    /// than was written; rest rounds **up** because the rest is itself the
    /// adjustment, and shaving a second off a 99-second rest to land on a grid
    /// would be the app arguing with its own arithmetic.
    private static func roundUp(_ value: Double, step: Double) -> Double {
        (value / step).rounded(.up) * step
    }
}
