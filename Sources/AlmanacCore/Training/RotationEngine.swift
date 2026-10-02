import Foundation

/// One exercise on a generated session's sheet.
public struct RotationEntry: Sendable, Hashable, Identifiable {
    /// Position on the sheet, in cycle order from the rotation head.
    public let slot: Int
    public let item: PoolItemEntry
    /// The skipped slot this exercise is standing in for, if it is a substitute.
    ///
    /// Non-nil exactly for entries added because of a per-session skip, so the
    /// sheet can say why an exercise is on it that was not going to be — a
    /// substitution the user cannot see is a substitution they cannot trust.
    public let substitutesForSlot: Int?

    public var id: Int64 { item.id }
}

/// A slot the user skipped for this one session (Decision 3).
///
/// The item is **not** removed and **not** advanced past — that is what "holds
/// its position" means, and it is why this type carries the item rather than
/// only a slot number: the caller has to be handed back the very exercise that
/// is still waiting its turn.
public struct SkippedSlot: Sendable, Hashable, Identifiable {
    public let slot: Int
    /// The held exercise. Still active, same `rotationPosition`, offered again
    /// the next time this day type comes up.
    public let item: PoolItemEntry
    /// What took its place, or nil when the pool has nothing else to offer.
    public let substitute: RotationEntry?

    public var id: Int { slot }
}

/// One generated session's exercise list, plus the slots the user skipped.
///
/// A plan is a **read**, not a record. Building it changes nothing — not the
/// pool, not the rotation index, not any timestamp. The session that carries it
/// into existence is written separately, and `rotationIndex` advances when that
/// session is completed and not before.
public struct RotationPlan: Sendable, Hashable {
    public let programDayId: Int64
    /// The pass this plan is for. Kept so a caller can log a session against
    /// the plan it was generated from, without asking again.
    public let rotationIndex: Int
    /// The exercises to show, in order. Length is the day's slot count unless a
    /// skip had nothing to substitute.
    public let entries: [RotationEntry]
    /// The skipped slots, in sheet order.
    public let skipped: [SkippedSlot]

    /// The exercises actually to be performed — everything except the held ones.
    public var exercises: [PoolItemEntry] { entries.map(\.item) }
}

/// Generates a day's exercise list from its pool, in rotation order.
///
/// **Decision 2 — rotation advances on completed sessions, not on calendar
/// time.** Position is `rotationIndex mod poolCount`, and `rotationIndex` is a
/// count of that day's completed sessions. Nothing here reads a date. A user who
/// skips a week and comes back to Push gets the *next* item, because a week is
/// not a rotation step and this is the whole reason the feature is for athletes
/// on irregular schedules rather than a calendar.
///
/// **Decision 3 — two mechanisms, one prompt.** Permanent removal (`isActive =
/// false`) leaves the cycle entirely, so an exercise the user's gym does not
/// have is never offered again. A per-session skip is the opposite in every
/// respect: it writes nothing, holds its position, and is re-offered next time.
/// Both are implemented here; the asymmetry is the design, not an oversight, and
/// `ExerciseAvailability` exists so that at the call site the difference is a
/// type rather than a convention.
///
/// Reads, in total, **two queries per plan** regardless of pool size: the active
/// pool, and the day's slot count. Both are hoisted out of the per-slot work,
/// which is the handoff §8 rule — "ask what varies within the pass, read the rest
/// once". A rotation built from a query inside a `for` over slots is a
/// per-session cost that grows with the program.
public struct RotationEngine: @unchecked Sendable {
    private let db: Database
    private let poolStore: ProgramDayExercisePoolStore

    public init(db: Database) {
        self.db = db
        self.poolStore = ProgramDayExercisePoolStore(db: db)
    }

    /// The rotation index the next session of this day should be.
    ///
    /// A count of this day's **live** completed sessions, so the first is 0. Not
    /// `MAX(rotationIndex) + 1`: that would keep counting through a session the
    /// user deleted, handing them an exercise set they never did and skipping one
    /// they did — an undo that costs them the work they came back to undo. So the
    /// count compacts, and deleting the first Push day means the next Push day
    /// offers what the first one offered.
    ///
    /// Never derived from a date. That is Decision 2, and it is the whole reason
    /// this is one indexed read.
    public func nextRotationIndex(programDayId: Int64) throws -> Int {
        let rows = try db.query("""
        SELECT COUNT(*) AS passes FROM workoutSession
        WHERE programDayId = ? AND deletedAt IS NULL;
        """, [.integer(programDayId)])
        return Int(rows.first?.int("passes") ?? 0)
    }

    /// Generates the exercise list for one pass through a day's pool.
    ///
    /// - Parameters:
    ///   - programDayId: the day whose pool to rotate.
    ///   - rotationIndex: the pass. Values beyond one full cycle are fine and mean
    ///     the same thing modulo the pool size, because a user on their twentieth
    ///     Push day is not an error case.
    ///   - skipping: slots the user has skipped for this session, by sheet index.
    ///     Out-of-range indices are ignored — a stale tap is not worth throwing
    ///     over — and a repeated index is one skip, not two.
    public func plan(programDayId: Int64,
                     rotationIndex: Int,
                     skipping: Set<Int> = []) throws -> RotationPlan {
        // The two reads, once each.
        let cycle = try poolStore.activeItems(programDayId: programDayId)
        guard !cycle.isEmpty else {
            return RotationPlan(programDayId: programDayId, rotationIndex: rotationIndex,
                                entries: [], skipped: [])
        }
        let slotCount = try poolStore.sessionSlotCount(programDayId: programDayId)

        // Decision 2: position is a function of the pass count and the pool size,
        // and of nothing else. No date is consulted anywhere in this file.
        let head = ((rotationIndex % cycle.count) + cycle.count) % cycle.count
        let window = (0..<Swift.min(slotCount, cycle.count)).map { cycle[(head + $0) % cycle.count] }

        // Which sheet indices are actually being skipped. Clamped to the window,
        // because a slot the session does not have cannot be skipped — and the
        // window can be shorter than `slotCount` when the pool is.
        let skippedSlots = Set(skipping.filter { $0 >= 0 && $0 < window.count })

        // Every exercise already spoken for on this sheet, so no substitute is
        // ever the same movement twice. Grows as substitutes are taken, which is
        // why the skips are walked in sheet order rather than resolved
        // independently: two skips in one session compete for the same next item,
        // and whichever is resolved first would otherwise be the only one filled.
        var used = Set(window.map(\.id))
        var entries: [RotationEntry] = []
        var held: [SkippedSlot] = []

        for (slot, item) in window.enumerated() {
            guard skippedSlots.contains(slot) else {
                entries.append(RotationEntry(slot: slot, item: item, substitutesForSlot: nil))
                continue
            }
            // Decision 3: the item holds. No write, no advance, same
            // `rotationPosition`, re-offered next time. The only question left is
            // what stands in for it on this sheet.
            guard let replacement = Self.nextUnused(after: item, in: cycle, used: used) else {
                held.append(SkippedSlot(slot: slot, item: item, substitute: nil))
                continue
            }
            used.insert(replacement.id)
            let entry = RotationEntry(slot: slot, item: replacement, substitutesForSlot: slot)
            entries.append(entry)
            held.append(SkippedSlot(slot: slot, item: item, substitute: entry))
        }

        // Sheet order is cycle order from the head, with each substitute placed
        // where the exercise it replaces was. With the natural authoring
        // (`positionWithinSession == rotationPosition % slotCount`) this is
        // identical to sorting by slot, and it stays well-defined when the day
        // was not authored that way.
        entries.sort { $0.slot < $1.slot }
        return RotationPlan(programDayId: programDayId, rotationIndex: rotationIndex,
                            entries: entries, skipped: held.sorted { $0.slot < $1.slot })
    }

    /// The next exercise in the cycle after `item` that nothing else has claimed.
    ///
    /// Scanning forward from `item`'s own position and wrapping, so a substitute
    /// is always the exercise that would have come next — which is what leaves
    /// the skipped exercise's neighbours in place and keeps the sheet a run of the
    /// rotation. Nil when the pool holds nothing else, and a slot with no
    /// substitute is left out of the session rather than filled with a repeat.
    private static func nextUnused(after item: PoolItemEntry,
                                   in cycle: [PoolItemEntry],
                                   used: Set<Int64>) -> PoolItemEntry? {
        guard let start = cycle.firstIndex(where: { $0.id == item.id }) else { return nil }
        for step in 1...cycle.count {
            let candidate = cycle[(start + step) % cycle.count]
            if used.contains(candidate.id) { continue }
            return candidate
        }
        return nil
    }
}
