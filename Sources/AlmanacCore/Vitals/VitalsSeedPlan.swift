import Foundation

/// One reading a UI test asked for, on a day named relative to today.
public struct VitalsSeedReading: Sendable, Hashable {
    public let metric: VitalsMetric
    /// Nil means **clear** every manual reading of `metric` on that day, rather
    /// than plant one.
    ///
    /// This was added because today's readings could not be cleared from the
    /// screen: until 2026-10-06 `VitalsView.reload` read its log with today as
    /// the exclusive `to:` of `records(metric:from:to:)`, so a reading taken
    /// today appeared on the "today" card (no delete) and nowhere else. That
    /// was a defect, not a design — the log is where a hand-entered reading is
    /// corrected — and `VitalsRecordStore.log` now ends with today. The clear
    /// form stays as a harness capability; no UI test depends on it any more.
    public let value: Double?
    /// Logical days before today. `0` is today's logical day, `-1` the day
    /// before, `-2` the day before that.
    public let dayOffset: Int

    public init(metric: VitalsMetric, value: Double?, dayOffset: Int) {
        self.metric = metric
        self.value = value
        self.dayOffset = dayOffset
    }
}

/// Vitals a UI test asked the app to plant on named logical days, and the only
/// way the app is ever permitted to plant them.
///
/// ## Why this exists rather than a test typing into the date picker
///
/// `VitalsEntryEditor` does expose a "Measured at" picker, and it is the reason
/// a person *can* back-date a reading — a deliberate feature, and `recordManual`
/// takes `measuredAt` explicitly so it stays true. What it is not is drivable by
/// a test. It is a compact `DatePicker`, so tapping it expands a **graphical
/// calendar** rather than a set of wheels: the day cells are buttons whose
/// accessibility labels are locale-formatted dates (`Sunday 4 October` under
/// en_GB, `Sunday, October 4` under en_US). A test that tapped one would be
/// asserting on UIKit's date formatting, and `test-ios` in CI resolves the
/// *newest* installed runtime rather than pinning one — so the value string that
/// works on a desk is not guaranteed on a runner, and a green local run would be
/// evidence of nothing.
///
/// So the harness names the days it wants in a launch argument and this reads
/// it. The cost is app code that exists only for tests, and the whole of that
/// cost is contained by two facts: the plan exists only when the argument is
/// present (`fromLaunchArguments`, whose absence returns nil and is what
/// `VitalsSeedPlanTests` pins), and it writes through the same public
/// `VitalsRecordStore.recordManual` a person uses, so a seeded reading is a real
/// reading in every way except who typed it.
public struct VitalsSeedPlan: Sendable, Hashable {
    /// The launch argument that carries the spec. Namespaced with a leading dash
    /// so it cannot collide with anything a real launch passes.
    public static let launchArgument = "-AlmanacSeedVitals"

    /// The hour of the morning a seeded reading is stamped at.
    ///
    /// 09:00 rather than the instant the test happened to run: a reading taken
    /// at 23:40 would sit close to the 04:00 boundary, and a test that seeded
    /// history and then ran across midnight would put a "yesterday" reading on
    /// the day after the one it named. A morning hour is inside every logical day
    /// under §7.1's rule and is the hour a resting rate is actually taken.
    public static let morningHour = 9

    public let readings: [VitalsSeedReading]

    public init(readings: [VitalsSeedReading]) {
        self.readings = readings
    }

    /// Parses a spec of comma-separated entries in either of two forms:
    ///
    /// - `rhr=52@-1` — plant a reading.
    /// - `rhr@-1` — clear every manual reading of that metric on that day.
    ///
    /// where the offset counts logical days back from today. No spaces; the
    /// grammar is a machine format, and a test that mistypes it is rejected
    /// rather than guessed at.
    ///
    /// **All or nothing.** A malformed entry rejects the whole spec rather than
    /// being skipped, because a test whose seed silently planted four of the six
    /// readings it asked for would fail somewhere else entirely, with a message
    /// about a score. Rejecting means nothing is planted, which is loud here and
    /// cheap: the next assertion is about a reading that should be on the log.
    public init?(spec: String) {
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var parsed: [VitalsSeedReading] = []
        for entry in trimmed.split(separator: ",") {
            let dayParts = entry.split(separator: "@", maxSplits: 1)
            guard dayParts.count == 2, let dayOffset = Int(dayParts[1]) else { return nil }

            // The metric is the part before `=`, which is the whole left half
            // when there is no `=` — so the split has to come first.
            let metricParts = dayParts[0].split(separator: "=", maxSplits: 1)
            guard let metric = VitalsMetric(rawValue: String(metricParts[0]).trimmingCharacters(in: .whitespaces))
            else { return nil }

            switch metricParts.count {
            case 1:
                // No `=`, so a clear.
                parsed.append(VitalsSeedReading(metric: metric, value: nil, dayOffset: dayOffset))
            case 2:
                guard let value = Double(metricParts[1]),
                      // `isFinite` before the comparison, because NaN fails
                      // every `>` and would otherwise be carried into the store
                      // as a number no score could interpret.
                      value.isFinite, value > 0 else { return nil }
                parsed.append(VitalsSeedReading(metric: metric, value: value, dayOffset: dayOffset))
            default:
                return nil
            }
        }
        guard !parsed.isEmpty else { return nil }
        self.readings = parsed
    }

    /// The plan the given launch arguments asked for, or nil if they did not ask.
    ///
    /// **This is the guard, and it is the whole of the "test-only code cannot
    /// reach a real launch" claim.** There is no other path into `apply`: no
    /// environment variable, no default, no seeding of an empty database. An
    /// ordinary launch — a person's, a reviewer's, CI's `build-app` — has no
    /// such argument and gets nil.
    public static func fromLaunchArguments(_ arguments: [String]) -> VitalsSeedPlan? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return VitalsSeedPlan(spec: arguments[index + 1])
    }

    /// The logical day `dayOffset` lands on, relative to today at `now`.
    ///
    /// Today comes from `TimeModel.logicalDay(now)` rather than from the
    /// calendar, so the offset counts the repo's own 04:00 boundary days and not
    /// midnight ones. Walking with `day(before:)`/`day(after:)` rather than
    /// subtracting 86,400 seconds is the same rule `VitalsView` follows for its
    /// history window: a DST day is 23 or 25 hours long and belongs to the
    /// calendar's arithmetic, not to a fixed offset from an instant.
    public func logicalDay(for dayOffset: Int, now: Date, timeModel: TimeModel) -> LogicalDay? {
        var day = timeModel.logicalDay(now)
        for _ in 0..<abs(dayOffset) {
            day = dayOffset < 0
                ? (timeModel.day(before: day) ?? day)
                : (timeModel.day(after: day) ?? day)
        }
        return day
    }

    /// Plants every reading in the plan, and clears every day it is told to.
    /// Returns how many readings were *written*.
    ///
    /// **Authoritative per `(metric, day)`, not additive.** Each entry first
    /// deletes the manual readings already there and then writes its own, so the
    /// same spec always lands the same state. That is what makes a plan safe to
    /// re-apply — the simulator's database is shared across runs and never reset,
    /// and a test relaunches the app at least once per test, so an appending
    /// seeder would leave a day carrying six copies of a reading instead of one,
    /// fill the 40-row log window, and give any delete helper more to remove
    /// than it is willing to.
    ///
    /// The clearing half was not tidiness when it was written: until 2026-10-06
    /// nothing in the UI could remove a reading taken today, and on a database
    /// that is never reset sixteen of them piled up across runs and quietly
    /// moved the baseline. The Vitals log now includes today, so the UI can.
    ///
    /// Goes through `recordManual` rather than writing SQL, so a seeded reading
    /// carries the same source, unit, zone and logical-day resolution a typed one
    /// does, and the plausibility check still applies — a spec asking for a
    /// negative resting rate throws here rather than planting a row the store
    /// would have refused.
    @discardableResult
    public func apply(into store: VitalsRecordStore,
                      now: Date = Date(),
                      timeModel: TimeModel = TimeModel(timeZone: .current)) throws -> Int {
        var written = 0
        for reading in readings {
            guard let day = logicalDay(for: reading.dayOffset, now: now, timeModel: timeModel),
                  let start = timeModel.start(of: day) else { continue }
            for existing in try store.manualRecords(metric: reading.metric, for: day.value) {
                try store.delete(id: existing.id)
            }
            // A clear has nothing to write; the deletion above was the whole entry.
            guard let value = reading.value else { continue }
            try store.recordManual(metric: reading.metric, value: value,
                                   measuredAt: start.addingTimeInterval(Double(Self.morningHour) * 3600))
            written += 1
        }
        return written
    }
}