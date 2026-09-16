import Testing
import Foundation
@testable import AlmanacCore

@Suite("FastingSessionStore Tests")
struct FastingSessionStoreTests {
    let db = try! TestDatabase()
    var store: FastingSessionStore { FastingSessionStore(db: db) }

    private func draft(start: TimeInterval, type: FastingSessionType = .ifConfirmedSuggestion) -> FastingSessionDraft {
        FastingSessionDraft(startTimestamp: Date(timeIntervalSince1970: start), sessionType: type)
    }

    @Test("Start a session and read it back as active")
    func startSession() throws {
        let id = try store.start(draft(start: 1_000_000), logicalDay: "2026-09-16")
        let active = try store.activeSession()

        #expect(active?.id == id)
        #expect(active?.isActive == true)
        #expect(active?.endTimestamp == nil)
        #expect(active?.sessionType == .ifConfirmedSuggestion)
    }

    @Test("Water and caffeine-only entries (zero calories) do not break the fast")
    func zeroCaloriesDoesNotBreak() throws {
        try store.start(draft(start: 1_000_000), logicalDay: "2026-09-16")

        let outcome = try store.recordNutritionEntry(calories: 0, at: Date(timeIntervalSince1970: 1_050_000))

        #expect(outcome == .noOp)
        #expect(try store.activeSession()?.isActive == true)
    }

    @Test("A calorie entry ends the active session and records duration")
    func calorieEntryEndsActiveSession() throws {
        let id = try store.start(draft(start: 1_000_000), logicalDay: "2026-09-16")

        // 7 hours later.
        let outcome = try store.recordNutritionEntry(calories: 450, at: Date(timeIntervalSince1970: 1_000_000 + 7 * 3600))

        #expect(outcome == .ended(sessionId: id, durationMinutes: 420))
        let session = try store.session(id: id)
        #expect(session?.isActive == false)
        #expect(session?.finalDurationMinutes == 420)
        #expect(try store.activeSession() == nil)
    }

    @Test("A calorie entry before the active session's start invalidates it")
    func calorieEntryBeforeActiveStartInvalidates() throws {
        let id = try store.start(draft(start: 1_000_000), logicalDay: "2026-09-16")

        let outcome = try store.recordNutritionEntry(calories: 300, at: Date(timeIntervalSince1970: 900_000))

        #expect(outcome == .invalidated(sessionId: id))
        let session = try store.session(id: id)
        #expect(session?.isInvalidated == true)
        #expect(session?.correctionHistory.count == 1)
    }

    @Test("A backdated calorie entry inside an already-ended session shortens it")
    func backdatedEntryShortensEndedSession() throws {
        let id = try store.start(draft(start: 1_000_000), logicalDay: "2026-09-16")
        // First break, at +8h — as if logged at the time.
        try store.recordNutritionEntry(calories: 500, at: Date(timeIntervalSince1970: 1_000_000 + 8 * 3600))

        // Correction: the meal was actually backdated to +5h, inside the recorded span.
        let correctionTimestamp = Date(timeIntervalSince1970: 1_000_000 + 5 * 3600)
        let outcome = try store.recordNutritionEntry(calories: 500, at: correctionTimestamp)

        #expect(outcome == .shortened(sessionId: id, durationMinutes: 300))
        let session = try store.session(id: id)
        #expect(session?.endTimestamp == correctionTimestamp)
        #expect(session?.finalDurationMinutes == 300)
        #expect(session?.correctionHistory.count == 1)
    }

    @Test("A calorie entry after an ended session's end does not touch it")
    func entryAfterEndedSessionIsNoOp() throws {
        let id = try store.start(draft(start: 1_000_000), logicalDay: "2026-09-16")
        try store.recordNutritionEntry(calories: 500, at: Date(timeIntervalSince1970: 1_000_000 + 8 * 3600))

        let outcome = try store.recordNutritionEntry(calories: 300, at: Date(timeIntervalSince1970: 1_000_000 + 12 * 3600))

        #expect(outcome == .noOp)
        #expect(try store.session(id: id)?.finalDurationMinutes == 480)
    }

    @Test("A calorie entry with no session at all is a no-op")
    func noSessionAtAllIsNoOp() throws {
        let outcome = try store.recordNutritionEntry(calories: 200, at: Date())
        #expect(outcome == .noOp)
    }
}

@Suite("IFSuggestion Tests")
struct IFSuggestionTests {
    @Test("Suggests fasting once the gap reaches the threshold")
    func suggestsAtThreshold() {
        #expect(IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: 14, thresholdHours: 14) == true)
        #expect(IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: 15, thresholdHours: 14) == true)
    }

    @Test("Does not suggest before the threshold")
    func doesNotSuggestBeforeThreshold() {
        #expect(IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: 13.9, thresholdHours: 14) == false)
    }

    @Test("Threshold is configurable")
    func customThreshold() {
        #expect(IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: 12, thresholdHours: 12) == true)
        #expect(IFSuggestion.shouldSuggest(hoursSinceLastCalorieEntry: 11, thresholdHours: 12) == false)
    }
}
