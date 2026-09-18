import Testing
import Foundation
@testable import AlmanacCore

@Suite("ReadinessRecordStore Tests")
struct ReadinessRecordStoreTests {
    let db: Database
    let cycleId: Int64

    init() throws {
        db = try TestDatabase()
        cycleId = try ReadinessCycleStore(db: db).createCycle(anchorDate: "2026-09-17")
    }

    private func outcome(score: Int? = 72, state: ReadinessState = .final) -> ReadinessOutcome {
        ReadinessOutcome(
            state: state,
            score: score,
            color: score.map { $0 >= 70 ? .green : .yellow } ?? .none,
            textDescription: score != nil ? "Recovery is good — ready for a strong session" : nil,
            confidence: score != nil ? .high : .insufficient,
            missingInputs: [],
            formulaVersion: "1.0",
            inputSnapshot: "{}",
            recommendation: score != nil ? "Recovery is good — ready for a strong session" : nil,
            precedenceApplied: [],
            baselineContext: .general
        )
    }

    @Test("Recording an outcome for a cycle can be read back")
    func recordAndRead() throws {
        let store = ReadinessRecordStore(db: db)
        try store.record(outcome(), cycleId: cycleId, anchorDate: "2026-09-17")

        let stored = try store.record(cycleId: cycleId)
        #expect(stored?.score == 72)
        #expect(stored?.state == .final)
        #expect(stored?.colorGrade == .green)
        #expect(stored?.confidence == .high)
        #expect(stored?.anchorDate == "2026-09-17")
        #expect(stored?.feedbackValue == nil)
    }

    @Test("Recording a second outcome for the same cycle replaces the first, not duplicates it")
    func recordUpsertsByCycle() throws {
        let store = ReadinessRecordStore(db: db)
        try store.record(outcome(score: 60, state: .provisional), cycleId: cycleId, anchorDate: "2026-09-17")
        try store.record(outcome(score: 78, state: .final), cycleId: cycleId, anchorDate: "2026-09-17")

        let stored = try store.record(cycleId: cycleId)
        #expect(stored?.score == 78)
        #expect(stored?.state == .final)

        let count = try db.query("SELECT COUNT(*) as n FROM readiness_record WHERE readinessCycleId = ?;",
                                  [.integer(cycleId)]).first?.int("n")
        #expect(count == 1)
    }

    @Test("A nil score is stored as nil, not zero")
    func nilScoreStaysNil() throws {
        let store = ReadinessRecordStore(db: db)
        try store.record(outcome(score: nil, state: .provisional), cycleId: cycleId, anchorDate: "2026-09-17")

        let stored = try store.record(cycleId: cycleId)
        #expect(stored?.score == nil)
        #expect(stored?.colorGrade == ReadinessColor.none)
        #expect(stored?.confidence == .insufficient)
    }

    @Test("Setting feedback stamps a value and a timestamp")
    func setFeedback() throws {
        let store = ReadinessRecordStore(db: db)
        try store.record(outcome(), cycleId: cycleId, anchorDate: "2026-09-17")

        try store.setFeedback(cycleId: cycleId, value: "thumbs_up")

        let stored = try store.record(cycleId: cycleId)
        #expect(stored?.feedbackValue == "thumbs_up")
        #expect(stored?.feedbackTimestamp != nil)
    }

    @Test("The most recent unrated scored record before a date is found for the feedback prompt")
    func latestUnratedRecordBefore() throws {
        let store = ReadinessRecordStore(db: db)
        let yesterdayCycle = try ReadinessCycleStore(db: db).createCycle(anchorDate: "2026-09-16")
        try store.record(outcome(score: 55), cycleId: yesterdayCycle, anchorDate: "2026-09-16")
        try store.record(outcome(score: 72), cycleId: cycleId, anchorDate: "2026-09-17")

        let unrated = try store.latestUnratedRecord(before: "2026-09-17")
        #expect(unrated?.anchorDate == "2026-09-16")
        #expect(unrated?.score == 55)
    }

    @Test("A record that already has feedback is not returned as unrated")
    func ratedRecordExcluded() throws {
        let store = ReadinessRecordStore(db: db)
        let yesterdayCycle = try ReadinessCycleStore(db: db).createCycle(anchorDate: "2026-09-16")
        try store.record(outcome(score: 55), cycleId: yesterdayCycle, anchorDate: "2026-09-16")
        try store.setFeedback(cycleId: yesterdayCycle, value: "thumbs_down")

        #expect(try store.latestUnratedRecord(before: "2026-09-17") == nil)
    }

    @Test("A record with no score (insufficient data) is not offered for feedback")
    func scorelessRecordExcludedFromFeedback() throws {
        let store = ReadinessRecordStore(db: db)
        let yesterdayCycle = try ReadinessCycleStore(db: db).createCycle(anchorDate: "2026-09-16")
        try store.record(outcome(score: nil, state: .provisional), cycleId: yesterdayCycle, anchorDate: "2026-09-16")

        #expect(try store.latestUnratedRecord(before: "2026-09-17") == nil)
    }

    @Test("Setting feedback a second time overwrites the first value, not rejected as already-rated")
    func settingFeedbackTwiceOverwrites() throws {
        let store = ReadinessRecordStore(db: db)
        try store.record(outcome(), cycleId: cycleId, anchorDate: "2026-09-17")

        try store.setFeedback(cycleId: cycleId, value: "thumbs_up")
        let firstTimestamp = try store.record(cycleId: cycleId)?.feedbackTimestamp

        try store.setFeedback(cycleId: cycleId, value: "thumbs_down")
        let stored = try store.record(cycleId: cycleId)

        #expect(stored?.feedbackValue == "thumbs_down", "changing your mind replaces the earlier vote")
        #expect(stored?.feedbackTimestamp != nil)
        #expect(firstTimestamp != nil)
    }

    @Test("Rating the most recent unrated record surfaces the next-oldest one still waiting")
    func ratingRevealsNextOldestBacklog() throws {
        let store = ReadinessRecordStore(db: db)
        let cycleStore = ReadinessCycleStore(db: db)
        let twoDaysAgoCycle = try cycleStore.createCycle(anchorDate: "2026-09-15")
        let yesterdayCycle = try cycleStore.createCycle(anchorDate: "2026-09-16")
        try store.record(outcome(score: 40), cycleId: twoDaysAgoCycle, anchorDate: "2026-09-15")
        try store.record(outcome(score: 55), cycleId: yesterdayCycle, anchorDate: "2026-09-16")
        try store.record(outcome(score: 72), cycleId: cycleId, anchorDate: "2026-09-17")

        let firstPrompt = try store.latestUnratedRecord(before: "2026-09-17")
        #expect(firstPrompt?.anchorDate == "2026-09-16", "the closer backlog day is asked about first")

        try store.setFeedback(cycleId: yesterdayCycle, value: "thumbs_up")

        let secondPrompt = try store.latestUnratedRecord(before: "2026-09-17")
        #expect(secondPrompt?.anchorDate == "2026-09-15",
               "rating the most recent backlog day must surface the next-oldest one still waiting")
    }
}
