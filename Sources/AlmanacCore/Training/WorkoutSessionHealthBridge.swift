import Foundation

/// Turns a HealthKit activity identifier into the label stored in
/// `workoutSession.sessionType`.
///
/// `sessionType` is free text and nothing in Almanac consumes these labels
/// semantically yet, so this is deliberately **not** the ~80-row per-value
/// decision table `docs/features/training.md` §6 step 1(c) anticipated. Nearly
/// every one of those rows would just re-spell what `spaced(_:)` already
/// produces, and a hand-maintained table of Apple's identifiers would rot
/// against every iOS release. When something *does* need to group activity types
/// — session templates, training focus, calorie estimation — that is the moment
/// to promote the values worth grouping into a closed enum, with real data in
/// hand to choose them from.
public enum WorkoutActivity {
    /// The label for a HealthKit activity identifier, or nil when there is none.
    public static func label(for activity: String?) -> String? {
        guard let activity, !activity.isEmpty else { return nil }
        return spaced(activity)
    }

    /// `traditionalStrengthTraining` → `Traditional Strength Training`.
    /// Camel case is split on its capitals, and connectives are left lowercase
    /// unless they open the label, so a type added by a future iOS release reads
    /// as a sentence rather than a raw identifier or a dropped sample.
    static func spaced(_ activity: String) -> String {
        let words = activity
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        let connectives: Set<String> = ["and", "of", "the", "to", "with", "for"]
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            // Lowercased only mid-label; the first word always leads.
            return index > 0 && connectives.contains(lower) ? lower : capitalized(word)
        }.joined(separator: " ")
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }
}

/// Writes HealthKit workouts into `workoutSession`.
///
/// One HealthKit workout maps to exactly one Almanac session, never two. A
/// workout the user also logged by hand is **claimed** — the manual session is
/// enriched and linked — rather than duplicated, because two sessions for one
/// workout would double the day's training load. A workout with no confident
/// match becomes a session of its own with no bouts: a watch records time and
/// activity, not sets and reps.
///
/// The claim is deliberately reversible in one direction only. A session this
/// bridge created is soft-deleted when its workout is withdrawn, but a session
/// the *user* logged is not — that record is theirs, and a source withdrawing
/// its own sample is not permission to erase something Almanac never owned. The
/// claim is released instead.
public struct WorkoutSessionHealthBridge: HealthSampleWriting, @unchecked Sendable {
    private let db: Database
    private let clock: any Clock
    private let timeModel: TimeModel
    private let zone: ZoneContext
    private let sourceSystem = "healthkit"

    public init(db: Database, clock: any Clock = SystemClock(),
                timeModel: TimeModel = TimeModel(timeZone: .current),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.timeModel = timeModel
        self.zone = zone
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
    private func parse(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    @discardableResult
    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        var inserted = 0, updated = 0, deleted = 0

        for sample in changeSet.added where sample.domain == .workouts {
            switch try link(sample, in: db) {
            case .created: inserted += 1
            case .claimed: updated += 1
            }
        }

        for externalID in changeSet.deletedExternalIDs {
            deleted += try releaseOrWithdraw(externalID, in: db)
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }

    private enum Outcome { case created, claimed }

    /// A logged session that a HealthKit workout could be the same workout as.
    private struct Candidate {
        let id: Int64
        let sample: HealthKitWorkoutSample
    }

    /// Claims a confident existing session, or inserts a new one.
    private func link(_ sample: HealthSample, in db: Database) throws -> Outcome {
        // Already linked by an earlier sync: refresh the facts, don't re-link.
        if try existingClaim(for: sample.externalID, in: db) != nil {
            try refreshClaimed(sample, in: db)
            return .claimed
        }

        // Only unclaimed sessions can be candidates — a session already claimed
        // by a *different* workout is that workout's, not this one's. The
        // matcher is symmetric, so the workout is the window here.
        let candidates = try unclaimedSessions(in: db)
        let best = WorkoutHealthKitMatcher.match(
            sessionStart: sample.start, sessionEnd: sample.end,
            candidates: candidates.map(\.sample))
        guard let best,
              let candidate = candidates.first(where: { $0.sample.externalID == best.externalID }) else {
            try insert(sample, in: db)
            return .created
        }

        try claim(sessionId: candidate.id, with: sample, in: db)
        return .claimed
    }

    private func insert(_ sample: HealthSample, in db: Database) throws {
        // The day it *ended*, matching the 04:00 boundary every other entry
        // uses: a 22:00–02:00 workout belongs to the day it started.
        let day = timeModel.logicalDay(sample.end).value
        let minutes = Int((sample.end.timeIntervalSince(sample.start) / 60).rounded())
        try db.run("""
        INSERT INTO workoutSession
            (date, startTimestamp, endTimestamp, durationMinutes, sessionType,
             source, healthKitUUID, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(day), .text(iso(sample.start)), .text(iso(sample.end)),
            .integer(Int64(minutes)),
            WorkoutActivity.label(for: sample.activity).map { SQLValue.text($0) } ?? .null,
            .text(sourceSystem), .text(sample.externalID), .text(nowText), .text(nowText),
        ])
    }

    /// Links a manual session, filling only what it left blank. A user's own
    /// `rpe`, `notes` and `sessionType` are theirs to keep.
    ///
    /// Deliberately does **not** set `source`. That column means "this row was
    /// created by this source", and a session the user logged was not — it only
    /// *claims* a HealthKit workout. Keeping the two meanings apart is what
    /// lets `releaseOrWithdraw` tell a session this bridge created (withdraw it)
    /// from a session the user owns (release the claim, keep the record).
    private func claim(sessionId: Int64, with sample: HealthSample, in db: Database) throws {
        let minutes = Int((sample.end.timeIntervalSince(sample.start) / 60).rounded())
        let activity = WorkoutActivity.label(for: sample.activity)
        try db.run("""
        UPDATE workoutSession SET
            healthKitUUID = ?,
            startTimestamp = COALESCE(startTimestamp, ?),
            endTimestamp = COALESCE(endTimestamp, ?),
            durationMinutes = COALESCE(durationMinutes, ?),
            sessionType = COALESCE(sessionType, ?),
            updatedAt = ?
        WHERE id = ?;
        """, [
            .text(sample.externalID),
            .text(iso(sample.start)), .text(iso(sample.end)), .integer(Int64(minutes)),
            activity.map { SQLValue.text($0) } ?? .null,
            .text(nowText), .integer(sessionId),
        ])
    }

    /// Re-sync of a workout already linked: keep the link, refresh the times.
    private func refreshClaimed(_ sample: HealthSample, in db: Database) throws {
        let minutes = Int((sample.end.timeIntervalSince(sample.start) / 60).rounded())
        try db.run("""
        UPDATE workoutSession SET
            startTimestamp = ?, endTimestamp = ?, durationMinutes = ?,
            sessionType = COALESCE(sessionType, ?), updatedAt = ?
        WHERE healthKitUUID = ?;
        """, [
            .text(iso(sample.start)), .text(iso(sample.end)), .integer(Int64(minutes)),
            WorkoutActivity.label(for: sample.activity).map { SQLValue.text($0) } ?? .null,
            .text(nowText), .text(sample.externalID),
        ])
    }

    private func existingClaim(for externalID: String, in db: Database) throws -> Int64? {
        try db.query("SELECT id FROM workoutSession WHERE healthKitUUID = ?;",
                     [.text(externalID)]).first?.int("id")
    }

    /// Withdrawing a workout soft-deletes a session this bridge created, and
    /// merely releases the claim on one the user logged. Returns rows affected.
    ///
    /// `source` is the discriminator: set means Almanac created the row from the
    /// workout, null with a `healthKitUUID` means the user created it and this
    /// bridge only linked it.
    private func releaseOrWithdraw(_ externalID: String, in db: Database) throws -> Int {
        let row = try db.query("SELECT id, source FROM workoutSession WHERE healthKitUUID = ?;",
                               [.text(externalID)]).first
        // No row claims this workout, so there is nothing to undo. Note the row
        // may legitimately have a NULL `source` — that is a session the *user*
        // created, which this bridge only linked.
        guard row != nil else { return 0 }

        if row?.string("source") == sourceSystem {
            return try db.run("""
            UPDATE workoutSession SET deletedAt = ?, updatedAt = ?
            WHERE healthKitUUID = ? AND deletedAt IS NULL;
            """, [.text(nowText), .text(nowText), .text(externalID)])
        }
        return try db.run("""
        UPDATE workoutSession SET healthKitUUID = NULL, updatedAt = ?
        WHERE healthKitUUID = ?;
        """, [.text(nowText), .text(externalID)])
    }

    /// Live sessions nothing has claimed yet, as match candidates.
    ///
    /// `externalID` is the row id rendered as a string — a key the matcher can
    /// order by deterministically, which is what keeps an equal-overlap
    /// tiebreak from depending on query order.
    private func unclaimedSessions(in db: Database) throws -> [Candidate] {
        try db.query("""
        SELECT id, startTimestamp, endTimestamp
        FROM workoutSession
        WHERE healthKitUUID IS NULL AND deletedAt IS NULL
          AND startTimestamp IS NOT NULL AND endTimestamp IS NOT NULL
        ORDER BY id;
        """, []).compactMap { row in
            guard let id = row.int("id"),
                  let startText = row.string("startTimestamp"),
                  let endText = row.string("endTimestamp"),
                  let start = parse(startText), let end = parse(endText) else { return nil }
            return Candidate(id: id,
                             sample: HealthKitWorkoutSample(externalID: String(id),
                                                             start: start, end: end))
        }
    }
}
