import Testing
import Foundation
@testable import AlmanacCore

@Suite("WorkoutHealthKitMatcher Tests")
struct WorkoutHealthKitMatcherTests {
    private func sample(_ id: String, start: TimeInterval, end: TimeInterval) -> HealthKitWorkoutSample {
        HealthKitWorkoutSample(externalID: id,
                                start: Date(timeIntervalSince1970: start),
                                end: Date(timeIntervalSince1970: end))
    }

    @Test("No candidates: no match")
    func noCandidatesNoMatch() {
        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 1000),
                                                    sessionEnd: Date(timeIntervalSince1970: 2000),
                                                    candidates: [])
        #expect(match == nil)
    }

    @Test("A candidate whose window overlaps the session's is matched")
    func overlappingCandidateMatches() {
        let workout = sample("hk-1", start: 1000, end: 4000)

        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 1000),
                                                    sessionEnd: Date(timeIntervalSince1970: 4000),
                                                    candidates: [workout])
        #expect(match?.externalID == "hk-1")
    }

    @Test("A candidate entirely outside the session's window is not matched")
    func nonOverlappingCandidateNotMatched() {
        let workout = sample("hk-1", start: 10_000, end: 13_000)

        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 1000),
                                                    sessionEnd: Date(timeIntervalSince1970: 4000),
                                                    candidates: [workout])
        #expect(match == nil)
    }

    @Test("Two overlapping candidates: only the one with greater overlap is matched, never both")
    func twoOverlappingCandidatesPicksGreaterOverlap() {
        // Session 1000-4000. "hk-partial" overlaps only 1000-1500 (500s).
        // "hk-mostly" overlaps the full 1000-4000 (3000s) — the real match.
        let partial = sample("hk-partial", start: 500, end: 1500)
        let mostly = sample("hk-mostly", start: 900, end: 4200)

        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 1000),
                                                    sessionEnd: Date(timeIntervalSince1970: 4000),
                                                    candidates: [partial, mostly])
        #expect(match?.externalID == "hk-mostly")
    }

    @Test("Candidates touching the session's edge with zero-duration overlap are not matched")
    func edgeTouchingCandidateNotMatched() {
        // Ends exactly when the session starts — no actual shared instant of overlap.
        let touching = sample("hk-1", start: 0, end: 1000)

        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 1000),
                                                    sessionEnd: Date(timeIntervalSince1970: 4000),
                                                    candidates: [touching])
        #expect(match == nil)
    }

    @Test("A workout merely inside a long session is not that session")
    func incidentalOverlapIsNotAMatch() {
        // A 45-minute run (10_000–12_700) logged inside an 8-hour session. The
        // run shares 100% of the *shorter* window, so a confidence measured
        // against the shorter side would absorb it into the day's session and
        // hide the run entirely. Measured against the union it is ~9%, which is
        // not the same workout.
        let run = sample("hk-run", start: 10_000, end: 12_700)

        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 0),
                                                    sessionEnd: Date(timeIntervalSince1970: 28_800),
                                                    candidates: [run])
        #expect(match == nil)
    }

    @Test("A near-identical window is still the same workout")
    func nearIdenticalWindowStillMatches() {
        // The same 45-minute run, logged as its own session a few seconds wider
        // on each side: ~98% of the union overlaps, so it is confidently the
        // same workout and the manual entry should be enriched, not duplicated.
        let run = sample("hk-run", start: 10_000, end: 12_700)

        let match = WorkoutHealthKitMatcher.match(sessionStart: Date(timeIntervalSince1970: 9_990),
                                                    sessionEnd: Date(timeIntervalSince1970: 12_750),
                                                    candidates: [run])
        #expect(match?.externalID == "hk-run")
    }

    @Test("Half-overlapping windows are two workouts, not one logged twice")
    func shiftedWindowIsNotAMatch() {
        // Two 60-minute workouts sharing 30 minutes: 1500s of overlap against a
        // 4500s union, a third. Distinct sessions, not one logged twice.
        let workout = sample("hk-1", start: 1000, end: 4000)
        let other = sample("s-other", start: 2500, end: 5500)

        let match = WorkoutHealthKitMatcher.match(sessionStart: workout.start,
                                                   sessionEnd: workout.end,
                                                   candidates: [other])
        #expect(match == nil)
    }

    @Test("Equally-overlapping sessions resolve the same way on every run")
    func equallyOverlappingSessionsAreNotAmbiguous() {
        // An unstable winner would move a workout between sessions on alternate
        // syncs, so the tiebreak must not depend on input order.
        let workout = sample("hk-1", start: 1000, end: 2000)
        let first = sample("s-early", start: 600, end: 1400)
        let second = sample("s-late", start: 1600, end: 2400)

        let a = WorkoutHealthKitMatcher.match(sessionStart: workout.start,
                                               sessionEnd: workout.end,
                                               candidates: [first, second])
        let b = WorkoutHealthKitMatcher.match(sessionStart: workout.start,
                                               sessionEnd: workout.end,
                                               candidates: [second, first])
        #expect(a?.externalID == b?.externalID)
    }
}
