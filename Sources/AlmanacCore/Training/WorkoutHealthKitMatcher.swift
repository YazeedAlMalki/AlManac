import Foundation

/// A HealthKit workout, in the shape a future bridge would need to hand
/// over — just enough for time-overlap matching. Deliberately not built
/// against a real `HKWorkout`/`HealthSample`: `docs/features/training.md`
/// §5 explains why extending `HealthSample` for workout activity type is
/// its own design decision. This is a standalone type so the matching logic
/// can be written and tested now, against fake data, ready to wire to
/// whatever the real bridge eventually produces.
public struct HealthKitWorkoutSample: Sendable, Hashable {
    public let externalID: String
    public let start: Date
    public let end: Date

    public init(externalID: String, start: Date, end: Date) {
        self.externalID = externalID
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Matches a `workoutSession` to a HealthKit workout by time-window overlap
/// (Ticket 4: "one HealthKit workout maps to exactly one Almanac training
/// session — never split"). Pure and stateless — no storage, no HealthKit.
///
/// **Confidence is overlap over the *union* of the two windows**, not over the
/// shorter one. That distinction is the whole point: a 45-minute run logged
/// inside an 8-hour session shares 100% of the shorter window, so a
/// shorter-window rule would swallow the run into the day's session and hide
/// it. Over the union it is ~9%, which is plainly not the same workout. Two
/// genuinely near-identical windows still score ~98% and match, which is the
/// case that matters — the user logged the same workout twice and the manual
/// entry should be enriched rather than duplicated.
public enum WorkoutHealthKitMatcher {
    /// The share of the two windows' union that must be shared time.
    public static let minimumOverlapFraction = 0.6

    /// The candidate sharing at least `minimumOverlapFraction` of the union
    /// with the given window, or nil if none does.
    ///
    /// Symmetric in its two sides, so the bridge calls it with a HealthKit
    /// workout as the window and the user's logged sessions as the candidates
    /// to find the session that *is* that workout.
    public static func match(sessionStart: Date, sessionEnd: Date,
                              candidates: [HealthKitWorkoutSample]) -> HealthKitWorkoutSample? {
        candidates
            .map { candidate in
                (candidate, confidence(of: sessionStart, sessionEnd, candidate))
            }
            .filter { $0.1 >= minimumOverlapFraction }
            // Total order, so the winner never depends on input order: an
            // unstable choice would move a workout between sessions on
            // alternate syncs, silently rewriting history each time.
            .max { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.duration != rhs.0.duration { return lhs.0.duration < rhs.0.duration }
                return lhs.0.externalID < rhs.0.externalID
            }?
            .0
    }

    /// Shared time as a fraction of the two windows' union — 1.0 for identical
    /// windows, 0.0 for disjoint ones.
    static func confidence(of aStart: Date, _ aEnd: Date,
                           _ candidate: HealthKitWorkoutSample) -> Double {
        let shared = overlap(aStart, aEnd, candidate.start, candidate.end)
        let union = max(aEnd, candidate.end).timeIntervalSince(min(aStart, candidate.start))
        guard union > 0 else { return 0 }
        return shared / union
    }

    private static func overlap(_ aStart: Date, _ aEnd: Date,
                                _ bStart: Date, _ bEnd: Date) -> TimeInterval {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }
}
