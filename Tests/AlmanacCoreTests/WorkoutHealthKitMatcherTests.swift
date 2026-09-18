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
}
