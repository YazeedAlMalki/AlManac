import Foundation

/// A HealthKit workout, in the shape a future bridge would need to hand
/// over — just enough for time-overlap matching. Deliberately not built
/// against a real `HKWorkout`/`HealthSample`: `docs/features/training.md`
/// §5 explains why extending `HealthSample` for workout activity type is
/// its own unresolved design decision. This is a standalone type so the
/// matching logic can be written and tested now, against fake data, ready
/// to wire to whatever the real bridge eventually produces.
public struct HealthKitWorkoutSample: Sendable, Hashable {
    public let externalID: String
    public let start: Date
    public let end: Date

    public init(externalID: String, start: Date, end: Date) {
        self.externalID = externalID
        self.start = start
        self.end = end
    }
}

/// Matches a manually-logged `workoutSession` to a HealthKit workout by
/// time-window overlap (Ticket 4: "one HealthKit workout maps to exactly
/// one Almanac training session — never split"). Pure and stateless — no
/// storage, no HealthKit.
public enum WorkoutHealthKitMatcher {
    /// The candidate overlapping the session's window the most, or nil if
    /// none overlap at all. "Most overlap" is the tiebreaker so that, if a
    /// session's window happens to touch two HK workouts, the session is
    /// still matched to exactly one — never split.
    public static func match(sessionStart: Date, sessionEnd: Date,
                              candidates: [HealthKitWorkoutSample]) -> HealthKitWorkoutSample? {
        candidates
            .map { ($0, overlap(sessionStart, sessionEnd, $0.start, $0.end)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    private static func overlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> TimeInterval {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }
}
