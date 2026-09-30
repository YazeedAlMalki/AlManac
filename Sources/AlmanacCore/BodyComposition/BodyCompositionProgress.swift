import Foundation

/// Which way a number moved between the last two readings.
public enum BodyMetricDirectionOfTravel: String, Sendable, Hashable {
    case improving
    case declining
    case unchanged
    /// Not enough readings to say. One reading is a value, not a direction.
    case unknown

    public var title: String {
        switch self {
        case .improving: return "Improving"
        case .declining: return "Declining"
        case .unchanged: return "Unchanged"
        case .unknown: return "Not enough data"
        }
    }
}

/// Everything a body-composition card shows, worked out once.
///
/// **A value, not a view.** The card draws a number, a meter and a sentence;
/// none of that is decided here. What is decided here is the part that is easy
/// to get quietly wrong: whether a number is going the right way, what a meter
/// should be filled to, and what a reading means when there is no target at all.
/// Those are decisions about arithmetic, not about pixels, so they belong where
/// they can be tested exhaustively instead of eyeballed in a simulator.
///
/// Built by one pass over the store's rows, not by asking the store again per
/// card. Five cards that each asked their own question is five queries to draw
/// one screen, and this type is deliberately constructible from a single
/// `[BodyCompositionMeasurement]` so "read the rest once" is the only shape a
/// call site has.
public struct BodyCompositionProgress: Sendable, Hashable, Identifiable {
    public let metric: BodyMetric

    /// The most recent reading, or `nil` when nothing has ever been recorded.
    public let current: Double?
    /// The reading before it, for the direction of travel. `nil` alongside a
    /// non-nil `current` means there is exactly one reading — not enough to say
    /// anything about which way the number is going, and a meter that claimed
    /// otherwise would be drawing a trend out of a single point.
    public let previous: Double?
    /// The oldest reading in the window. This is the meter's origin: without
    /// somewhere to measure from, "how far along" has no answer.
    public let start: Double?
    /// When `current` was recorded. Shown on the card, so a reading from March
    /// is not read as this morning's.
    public let currentDate: Date?
    /// The target in force, in the metric's own unit (kg or pct). `nil` when the
    /// person has not set one — the *normal* case on a fresh install, not an
    /// error.
    public let target: Double?
    /// How many readings the window holds, which is what makes "not enough
    /// data" a fact rather than a guess.
    public let readingCount: Int
    /// The unit basis every string on this card is written in.
    ///
    /// **Carried, not looked up.** A value type that rendered in kilograms and
    /// read its preference from a store would be a value whose output depends on
    /// ambient state, which is untestable and wrong: the same reading formatted
    /// twice must not be able to produce two answers. The basis arrives with the
    /// progress, from the one place that knows the person's preference, so what
    /// a card shows is fixed by what it was built from.
    ///
    /// The arithmetic above is unaffected — fraction, gap and direction are all
    /// ratios or differences in the stored unit, and a linear conversion scales
    /// them all equally. Only the text is in this basis.
    public let unitBasis: UnitBasis

    public var id: String { metric.id }

    // MARK: - Progress

    /// How much of the way to the target the metric is, from 0 to 1.
    ///
    /// **The definition, since several are defensible and the choice is the
    /// whole content of the meter:** the distance already travelled from the
    /// oldest reading in the window, over that distance plus the distance still
    /// to go.
    ///
    ///     20 kg, started at 25, target 15  →  travelled 5, to go 5  →  0.5
    ///     25 kg, started at 25, target 15  →  travelled 0, to go 10 →  0
    ///     17 kg, started at 25, target 15  →  travelled 8, to go 2  →  0.8
    ///
    /// The alternatives were rejected for specific reasons. A fraction of
    /// `current` (1 − (current−target)/current) says you have closed 60% of the
    /// gap the moment you set a target on a body that has never moved, which
    /// credits progress nobody made. A fraction that is always 0 until the
    /// target is hit is not a meter. And anchoring on a stored baseline needs a
    /// column that would hold a second, competing answer to "where I started".
    ///
    /// `nil` whenever a fraction would be a fiction: no target, no reading, only
    /// one reading (no origin to measure from), no distance to travel at all, or
    /// the target is met — which is answered by `isTargetMet` instead. A bar at
    /// 140% or one silently pinned at full says less than the sentence "target
    /// met", so the sentence is what the card shows.
    ///
    /// Clamped at 0. Moving the wrong way is real and the card shows it, but a
    /// negative bar has no reading — so the bar is empty and
    /// `directionOfTravel` carries the news.
    public var fraction: Double? {
        guard let current, let target, let start, readingCount > 1 else { return nil }
        guard !isTargetMet else { return nil }
        switch metric.progressDirection {
        case .towardLower:
            let travelled = start - current
            let remaining = current - target
            let span = travelled + remaining
            guard span != 0 else { return nil }
            return min(max(travelled / span, 0), 1)
        case .towardHigher:
            let travelled = current - start
            let remaining = target - current
            let span = travelled + remaining
            guard span != 0 else { return nil }
            return min(max(travelled / span, 0), 1)
        }
    }

    /// Whether the target has been reached.
    public var isTargetMet: Bool {
        guard let current, let target else { return false }
        switch metric.progressDirection {
        case .towardLower: return current <= target
        case .towardHigher: return current >= target
        }
    }

    /// Whether the last change was an improvement, a regression, or neither.
    ///
    /// Three states, not two, because "unchanged" is a real answer with a real
    /// reading. A week of the same weight is information, and rendering it as
    /// either progress or decline is how a chart starts lying.
    public var directionOfTravel: BodyMetricDirectionOfTravel {
        guard let previous, let current else { return .unknown }
        if previous == current { return .unchanged }
        return metric.progressDirection.isImprovement(previous: previous, current: current)
            ? .improving : .declining
    }

    /// The change since the previous reading, in the metric's own unit.
    ///
    /// Signed by amount, not by good-or-bad. A caller that wants the judgement
    /// asks `directionOfTravel`; keeping the two apart stops a chart colouring
    /// by magnitude when it meant to colour by direction.
    public var change: Double? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    /// The distance still to travel, in the metric's own unit. `nil` with no
    /// target, or once the target is met.
    public var remaining: Double? {
        guard let current, let target, !isTargetMet else { return nil }
        return (target - current).magnitude
    }

    // MARK: - Presentation-ready text
    //
    // In core, not in the view, for one reason: these are the strings a screen
    // reader and a sighted person must hear identically, and a value type is
    // the only place that can be tested to say the same thing. A
    // `Text("\(x) kg")` in a view is testable only by running the app.

    /// The reading, formatted for this metric. `nil` when there is nothing.
    /// Bare number, for a place that prints the unit separately.
    public var currentText: String? {
        current.map { unitBasis.format($0, metric: metric) }
    }

    /// Number with its unit, for prose and for VoiceOver.
    ///
    /// The card draws the unit next to the number, so it reads as a unit. A
    /// screen reader has no such luck: "82.4" alone does not say 82.4 of what, and
    /// a weight, a body-fat percentage and a rating are all bare numbers. So the
    /// spoken form carries the unit, and the spoken and read forms are built from
    /// the same call rather than written out twice.
    public var currentWithUnit: String? {
        current.map { unitBasis.formatWithUnit($0, metric: metric) }
    }

    /// The target, formatted for this metric.
    /// Bare number, for a place that prints the unit separately.
    public var targetText: String? {
        target.map { unitBasis.format($0, metric: metric) }
    }

    /// Number with its unit, for prose and for VoiceOver.
    public var targetWithUnit: String? {
        target.map { unitBasis.formatWithUnit($0, metric: metric) }
    }

    /// The distance to travel with its unit. One place, because the short status
    /// and the spoken sentence must never disagree about what the gap is called —
    /// a "2 to go" on screen and a "2 points to go" when spoken is two answers to
    /// one question.
    public var remainingText: String? {
        remaining.map { unitBasis.formatWithUnit($0, metric: metric) }
    }

    /// The one-line summary a card shows under the value.
    ///
    /// Says what is true, including "no target set". A card with an empty meter
    /// and no explanation is the thing this feature is most likely to get
    /// wrong: the meter looks broken, and the natural conclusion is that the
    /// app lost the reading.
    public var statusText: String {
        guard let current, let currentText else { return "Nothing recorded yet" }
        guard let target else { return "No target set" }
        if isTargetMet { return "Target met" }
        guard let remainingText else { return "No target set" }
        return "\(remainingText) to go"
    }

    /// The same summary as one sentence, for VoiceOver.
    ///
    /// Says the number, the target and the gap. A meter alone conveys none of
    /// that; a sighted person gets all three by looking at three places on the
    /// card, and a screen-reader user has to be handed all three or has nothing.
    public var accessibilityDescription: String {
        guard let currentWithUnit else { return "\(metric.title): nothing recorded yet." }
        guard let target, let targetWithUnit else {
            return "\(metric.title): \(currentWithUnit). No target set."
        }
        // "Your target", capitalised because it starts a sentence. Nothing
        // generates a body-composition target, so every one was chosen by a person,
        // and saying so is more useful than a bare article — it is also why a
        // wrong target is fixed by editing it rather than by re-deriving it.
        let kind = "Your target"
        if isTargetMet { return "\(metric.title): \(currentWithUnit). \(kind) of \(targetWithUnit) reached." }
        guard let remainingText else { return "\(metric.title): \(currentWithUnit). \(kind) of \(targetWithUnit)." }
        return "\(metric.title): \(currentWithUnit). \(kind) of \(targetWithUnit), \(remainingText) to go."
    }

    // MARK: - Building

    public init(metric: BodyMetric,
                current: Double? = nil,
                previous: Double? = nil,
                start: Double? = nil,
                currentDate: Date? = nil,
                target: Double? = nil,
                readingCount: Int = 0,
                unitBasis: UnitBasis = .kilograms) {
        self.metric = metric
        self.current = current
        self.previous = previous
        self.start = start
        self.currentDate = currentDate
        self.target = target
        self.readingCount = readingCount
        self.unitBasis = unitBasis
    }

    /// The progress for every metric, from one pass over the readings.
    ///
    /// - Parameters:
    ///   - readings: every reading in the window, in any order, for any mix of
    ///     metrics. Passing them all is the point — the alternative is a query
    ///     per card, and a grid of five metrics that costs five reads is exactly
    ///     the shape this exists to avoid.
    ///   - targets: the targets in force, keyed by metric. A missing entry
    ///     means "no target", which is a normal state and not a failure.
    ///   - unitBasis: the basis every card's text is written in. The arithmetic is
    ///     identical either way — a mass is stored in kilograms and a conversion
    ///     is a scale factor — so this is presentation only, and putting it here
    ///     rather than in the view keeps the strings testable.
    ///
    /// Every metric always gets an entry, whether or not it has readings: a
    /// card grid's set of cards is a fact about the app, not about the data, and
    /// a metric that appears only once something is logged is a layout that
    /// changes shape under the reader.
    public static func all(from readings: [BodyCompositionMeasurement],
                           targets: [BodyMetric: GoalTargetSnapshot] = [:],
                           unitBasis: UnitBasis = .kilograms) -> [BodyCompositionProgress] {
        BodyMetric.allCases.map { metric in
            let series = readings
                .filter { $0.metric == metric.rawValue }
                .sorted { $0.timestamp > $1.timestamp }
            let snapshot = targets[metric]
            return BodyCompositionProgress(
                metric: metric,
                current: series.first?.value,
                previous: series.count > 1 ? series[1].value : nil,
                start: series.last?.value,
                currentDate: series.first?.timestamp,
                target: snapshot?.targetValue(for: metric),
                readingCount: series.count,
                unitBasis: unitBasis
            )
        }
    }
}

public extension BodyMetric {
    /// Formats a value in the metric's unit, at the metric's own precision.
    ///
    /// One implementation so a card, a chart axis and a VoiceOver string cannot
    /// disagree about the same number — which they could before this existed,
    /// as `%.1f` in one place and `%.2f` in another.
    static func format(_ value: Double, metric: BodyMetric) -> String {
        String(format: "%.\(metric.decimalPlaces)f", value)
    }

    /// A value with its unit, in kilograms, for prose. `visceralRating` has no
    /// unit to append: it is a rating on a scale, not a quantity, and "7 rating"
    /// is worse than "7".
    ///
    /// Delegates to the basis rather than repeating the rule, because a pounds
    /// variant of this that appends `lb` while this appends `kg` is a pair of
    /// implementations that will drift.
    static func formatWithUnit(_ value: Double, metric: BodyMetric) -> String {
        UnitBasis.kilograms.formatWithUnit(value, metric: metric)
    }
}
