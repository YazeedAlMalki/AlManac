import Testing
import Foundation
@testable import AlmanacCore

@Suite("SleepEpisodeStore Tests")
struct SleepEpisodeStoreTests {
    let db = try! TestDatabase()
    var store: SleepEpisodeStore { SleepEpisodeStore(db: db) }

    private func episode(uuid: String, start: TimeInterval, end: TimeInterval,
                          type: SleepEpisodeType = .primary) -> SleepEpisode {
        SleepEpisode(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                     type: type, source: .healthkit, asleepMinutes: Int((end - start) / 60),
                     sourceApp: "com.apple.health", healthKitUUIDs: [uuid])
    }

    @Test("Upsert a classified episode and read it back")
    func upsertAndRead() throws {
        let e = episode(uuid: "hk-night-1", start: 1_000_000, end: 1_028_800)  // 8 hours

        let id = try store.upsert(e, timezoneOffset: 180, logicalDay: "2026-09-16")
        let stored = try store.episode(id: id)

        #expect(stored?.episodeType == .primary)
        #expect(stored?.source == .healthkit)
        #expect(stored?.durationMinutes == 480)
        #expect(stored?.healthKitUUID == "hk-night-1")
        #expect(stored?.logicalDay == "2026-09-16")
    }

    @Test("Re-classifying the same night updates the same row, not a duplicate")
    func idempotentReclassification() throws {
        let e1 = episode(uuid: "hk-night-1", start: 1_000_000, end: 1_028_800, type: .nap)
        let firstId = try store.upsert(e1, timezoneOffset: 180, logicalDay: "2026-09-16")

        // Same underlying HealthKit samples, reclassified after a later
        // episode made this one look like the primary instead of a nap.
        let e2 = episode(uuid: "hk-night-1", start: 1_000_000, end: 1_028_800, type: .primary)
        let secondId = try store.upsert(e2, timezoneOffset: 180, logicalDay: "2026-09-16")

        #expect(firstId == secondId)
        #expect(try store.episode(id: firstId)?.episodeType == .primary)

        let count = try db.query("SELECT COUNT(*) AS n FROM sleep_episode;").first?.int("n")
        #expect(count == 1)
    }

    @Test("Different nights produce different rows")
    func distinctNights() throws {
        let night1 = episode(uuid: "hk-night-1", start: 1_000_000, end: 1_028_800)
        let night2 = episode(uuid: "hk-night-2", start: 1_100_000, end: 1_128_800)

        let id1 = try store.upsert(night1, timezoneOffset: 180, logicalDay: "2026-09-15")
        let id2 = try store.upsert(night2, timezoneOffset: 180, logicalDay: "2026-09-16")

        #expect(id1 != id2)
    }

    @Test("A user-corrected type is preserved on write")
    func userCorrectedTypeWritten() throws {
        var e = episode(uuid: "hk-night-1", start: 1_000_000, end: 1_028_800, type: .nap)
        e.userCorrectedType = .primary

        let id = try store.upsert(e, timezoneOffset: 180, logicalDay: "2026-09-16")
        let stored = try store.episode(id: id)

        #expect(stored?.userCorrectedType == .primary)
        #expect(stored?.episodeType == .nap, "stored episodeType is the classifier's raw call; effectiveType wins at read time")
    }

    @Test("Episodes for a logical day come back ordered by start time")
    func episodesForDay() throws {
        let later = episode(uuid: "hk-nap", start: 1_050_000, end: 1_053_600, type: .nap)
        let earlier = episode(uuid: "hk-night-1", start: 1_000_000, end: 1_028_800, type: .primary)

        try store.upsert(later, timezoneOffset: 180, logicalDay: "2026-09-16")
        try store.upsert(earlier, timezoneOffset: 180, logicalDay: "2026-09-16")

        let episodes = try store.episodes(for: "2026-09-16")
        #expect(episodes.map { $0.healthKitUUID } == ["hk-night-1", "hk-nap"])
    }
}
