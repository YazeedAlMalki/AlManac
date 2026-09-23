import Foundation

/// A hydration entry not yet written to storage.
///
/// `loggedAt` is always resolved to a full instant — see `Migration012`'s
/// doc comment for why imprecise/backfilled hydration entries are out of
/// scope for this pass.
///
/// `drink` is optional: a plain "logged 250ml" entry has none, exactly as it
/// did before Migration013. When present, every field of `DrinkAttachment`
/// is a snapshot taken at logging time — see `Migration013`'s doc comment
/// for why these are columns on the row rather than a join.
public struct HydrationLogDraft: Sendable {
    public var amount: Milliliters
    public var loggedAt: Date
    public var note: String?
    public var drink: DrinkAttachment?

    public init(amount: Milliliters, loggedAt: Date, note: String? = nil, drink: DrinkAttachment? = nil) {
        self.amount = amount
        self.loggedAt = loggedAt
        self.note = note
        self.drink = drink
    }
}

/// A snapshot of a drink's nutrition figures at the moment they were logged,
/// already scaled to the amount actually drunk — never the drink's raw
/// per-serving figures. `qualifier` travels with the snapshot permanently so
/// a later reader can never mistake an unsourced catalog estimate for a
/// measured value.
public struct DrinkAttachment: Sendable, Hashable {
    public var drinkID: String
    public var drinkName: String
    public var caloriesKcal: Double
    public var sodiumMg: Double
    public var sugarG: Double?
    public var qualifier: DrinkValueQualifier

    public init(drinkID: String, drinkName: String, caloriesKcal: Double, sodiumMg: Double,
                sugarG: Double?, qualifier: DrinkValueQualifier) {
        self.drinkID = drinkID
        self.drinkName = drinkName
        self.caloriesKcal = caloriesKcal
        self.sodiumMg = sodiumMg
        self.sugarG = sugarG
        self.qualifier = qualifier
    }
}

public struct HydrationEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let amount: Milliliters
    public let loggedAt: PartialDateTime
    public let note: String?
    public let sourceSystem: String
    /// `true` once this entry has been pushed to HealthKit. Always `false`
    /// for entries that originated *from* HealthKit — there is nothing to
    /// push back.
    public let healthKitSynced: Bool
    public let drink: DrinkAttachment?

    public init(id: String, amount: Milliliters, loggedAt: PartialDateTime, note: String?,
                sourceSystem: String, healthKitSynced: Bool, drink: DrinkAttachment? = nil) {
        self.id = id
        self.amount = amount
        self.loggedAt = loggedAt
        self.note = note
        self.sourceSystem = sourceSystem
        self.healthKitSynced = healthKitSynced
        self.drink = drink
    }
}

/// Hydration logging and querying, over `hydration_log`.
///
/// Same shape as `LabStore`/`HealthSampleStore`: a plain struct holding a
/// `Database`, time injected through `Clock`, raw SQL. Conforms to
/// `TimelineProviding` so hydration entries merge into the app's one merged
/// `Timeline` feed, and to `HealthSampleWriting` so it plugs directly into
/// the existing `HealthSyncService` for inbound HealthKit sync with no new
/// sync code (see `HydrationWriteback` for the outbound half).
public struct HydrationStore: HealthSampleWriting, TimelineProviding, @unchecked Sendable {
    public let domain = "hydration"
    let db: Database
    private let clock: any Clock
    private let zone: ZoneContext
    private let healthKitSourceSystem = "healthkit"
    private let manualSourceSystem = "manual"

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.zone = zone
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Writes

    @discardableResult
    public func log(_ draft: HydrationLogDraft) throws -> String {
        let id = UUID().uuidString
        try db.run("""
        INSERT INTO hydration_log
            (id, source_system, external_id, amount_ml, note_text,
             logged_at, logged_precision, logged_tz_offset_minutes, logged_tz_id,
             recorded_at, recorded_tz_offset_minutes,
             drink_id, drink_name, calories_kcal, sodium_mg, sugar_g, value_qualifier)
        VALUES (?, ?, NULL, ?, ?, ?, 'instant', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(id), .text(manualSourceSystem), .real(draft.amount.value),
            draft.note.map { SQLValue.text($0) } ?? .null,
            .text(iso(draft.loggedAt)),
            zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            zone.identifier.map { SQLValue.text($0) } ?? .null,
            .text(nowText),
            zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.drink.map { SQLValue.text($0.drinkID) } ?? .null,
            draft.drink.map { SQLValue.text($0.drinkName) } ?? .null,
            draft.drink.map { SQLValue.real($0.caloriesKcal) } ?? .null,
            draft.drink.map { SQLValue.real($0.sodiumMg) } ?? .null,
            draft.drink?.sugarG.map { SQLValue.real($0) } ?? .null,
            draft.drink.map { SQLValue.text($0.qualifier.rawValue) } ?? .null
        ])
        return id
    }

    public func editAmount(id: String, to amount: Milliliters) throws {
        try db.run("""
        UPDATE hydration_log SET amount_ml = ? WHERE id = ? AND deleted_at IS NULL;
        """, [.real(amount.value), .text(id)])
    }

    public func editLoggedAt(id: String, to date: Date) throws {
        try db.run("""
        UPDATE hydration_log SET logged_at = ? WHERE id = ? AND deleted_at IS NULL;
        """, [.text(iso(date)), .text(id)])
    }

    /// Soft delete. A HealthKit-sourced row deleted here must stay deleted
    /// even after the next inbound sync re-reads the same anchor range —
    /// which is exactly what a hard delete would not guarantee.
    public func delete(id: String) throws {
        try db.run("""
        UPDATE hydration_log SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL;
        """, [.text(nowText), .text(id)])
    }

    // MARK: - Reads

    private static let entryColumns = """
    id, amount_ml, note_text, logged_at, logged_precision, source_system, healthkit_synced_at,
    drink_id, drink_name, calories_kcal, sodium_mg, sugar_g, value_qualifier
    """

    public func entry(id: String) throws -> HydrationEntry? {
        try db.query("""
        SELECT \(Self.entryColumns)
        FROM hydration_log WHERE id = ? AND deleted_at IS NULL;
        """, [.text(id)]).first.flatMap(rowToEntry)
    }

    public func logs(from: String, to: String) throws -> [HydrationEntry] {
        guard let range = DateRange(from: from, to: to) else { return [] }
        let bounds = range.utcTextBounds
        return try db.query("""
        SELECT \(Self.entryColumns)
        FROM hydration_log
        WHERE deleted_at IS NULL AND logged_at >= ? AND logged_at < ?
        ORDER BY logged_at;
        """, [.text(bounds.start), .text(bounds.end)]).compactMap(rowToEntry)
    }

    public func total(from: String, to: String) throws -> Milliliters {
        guard let range = DateRange(from: from, to: to) else { return .zero }
        let bounds = range.utcTextBounds
        let sum = try db.query("""
        SELECT COALESCE(SUM(amount_ml), 0) AS total FROM hydration_log
        WHERE deleted_at IS NULL AND logged_at >= ? AND logged_at < ?;
        """, [.text(bounds.start), .text(bounds.end)]).first?.double("total") ?? 0
        return Milliliters(sum)
    }

    private func rowToEntry(_ row: Row) -> HydrationEntry? {
        guard let id = row.string("id"), let amount = row.double("amount_ml"),
              let loggedAtText = row.string("logged_at"),
              let source = row.string("source_system"),
              let precisionRaw = row.string("logged_precision"),
              let precision = TimePrecision(rawValue: precisionRaw),
              let loggedAt = PartialDateTime(storedText: loggedAtText, precision: precision, zone: .unknown)
        else { return nil }
        return HydrationEntry(id: id, amount: Milliliters(amount), loggedAt: loggedAt,
                              note: row.string("note_text"), sourceSystem: source,
                              healthKitSynced: !row.isNull("healthkit_synced_at"),
                              drink: rowToDrinkAttachment(row))
    }

    /// A drink attachment is present only when every one of its fields is —
    /// a partially-written attachment would mean an insert bug elsewhere,
    /// and this refuses to guess the missing part rather than surface a
    /// half-formed one.
    private func rowToDrinkAttachment(_ row: Row) -> DrinkAttachment? {
        guard let drinkID = row.string("drink_id"), let drinkName = row.string("drink_name"),
              let calories = row.double("calories_kcal"), let sodium = row.double("sodium_mg"),
              let qualifierRaw = row.string("value_qualifier"),
              let qualifier = DrinkValueQualifier(rawValue: qualifierRaw)
        else { return nil }
        return DrinkAttachment(drinkID: drinkID, drinkName: drinkName, caloriesKcal: calories,
                                sodiumMg: sodium, sugarG: row.double("sugar_g"), qualifier: qualifier)
    }

    // MARK: - TimelineProviding

    public func entries(from: String, to: String) throws -> [TimelineEntry] {
        guard let range = DateRange(from: from, to: to) else { return [] }
        let bounds = range.utcTextBounds
        return try db.query("""
        SELECT id, amount_ml, note_text, logged_at
        FROM hydration_log
        WHERE deleted_at IS NULL AND logged_at >= ? AND logged_at < ?
        ORDER BY logged_at;
        """, [.text(bounds.start), .text(bounds.end)]).compactMap { row in
            // Hydration entries always carry a full instant, so their span is a
            // point and the fit is always `.definite` — same reasoning as
            // HealthSampleStore.entries.
            guard let id = row.string("id"), let loggedAtText = row.string("logged_at"),
                  let amount = row.double("amount_ml"),
                  let occurrence = PartialDateTime(storedText: loggedAtText, precision: .instant, zone: .unknown),
                  let fit = occurrence.fit(in: range) else { return nil }
            return TimelineEntry(
                domain: domain, kind: "log", recordTable: "hydration_log", recordID: id,
                occurrence: occurrence, basis: .occurrence,
                title: "Hydration", detail: row.string("note_text"),
                value: .quantity(text: String(amount), unit: "ml"),
                lifecycle: nil, rangeFit: fit)
        }
    }

    // MARK: - HealthSampleWriting (inbound HealthKit sync)

    @discardableResult
    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        var inserted = 0, updated = 0, deleted = 0

        for sample in changeSet.added where sample.domain == .water {
            let existingRow = try db.query("""
                SELECT id, deleted_at FROM hydration_log WHERE source_system = ? AND external_id = ?;
                """, [.text(healthKitSourceSystem), .text(sample.externalID)]).first
            // A soft delete is sticky: once the user has deleted a HealthKit-
            // sourced entry in-app, re-reading the same sample from a later
            // (or replayed) anchor range must not bring it back.
            if let existingRow, !existingRow.isNull("deleted_at") { continue }
            let existing = existingRow?.string("id")
            // HealthKit tells us nothing about what was drunk, only a volume
            // — a synced sample never carries a drink attachment.
            try db.run("""
            INSERT INTO hydration_log
                (id, source_system, external_id, amount_ml, note_text,
                 logged_at, logged_precision, logged_tz_offset_minutes, logged_tz_id,
                 recorded_at, recorded_tz_offset_minutes, deleted_at)
            VALUES (?, ?, ?, ?, NULL, ?, 'instant', NULL, NULL, ?, NULL, NULL)
            ON CONFLICT(source_system, external_id) WHERE external_id IS NOT NULL DO UPDATE SET
                amount_ml   = excluded.amount_ml,
                logged_at   = excluded.logged_at,
                recorded_at = excluded.recorded_at;
            """, [
                .text(existing ?? UUID().uuidString), .text(healthKitSourceSystem),
                .text(sample.externalID), sample.value.map { SQLValue.real($0) } ?? .real(0),
                .text(iso(sample.start)), .text(nowText)
            ])
            if existing == nil { inserted += 1 } else { updated += 1 }
        }

        // Soft delete, as HealthSampleStore does: a source withdrawing a
        // sample is a fact about the source, not permission to erase it.
        for externalID in changeSet.deletedExternalIDs {
            deleted += try db.run("""
                UPDATE hydration_log SET deleted_at = ?
                WHERE source_system = ? AND external_id = ? AND deleted_at IS NULL;
                """, [.text(nowText), .text(healthKitSourceSystem), .text(externalID)])
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }

    // MARK: - Restore reconcile (HealthKit)

    /// Collapses hydration entries duplicated by the manual-writeback + re-sync
    /// overlap after a restore. Returns how many duplicates were dropped.
    ///
    /// The Slice 12 handoff's overlap case has exactly one provable shape in
    /// this schema: a manual entry pushed to HealthKit carries
    /// `healthkit_external_id`, and a later inbound sync can read that same
    /// sample back as a `healthkit`-sourced row keyed on the same UUID in
    /// `external_id`. That is the same drink twice — one user-authored, one
    /// machine-imported. The manual row wins: it can carry a note or drink
    /// attachment the bare HealthKit row never has.
    ///
    /// Soft delete, matching this table's sticky-delete semantics: the HealthKit
    /// row must stay gone even if the next sync re-reads the same anchor range.
    ///
    /// Timestamp-window matching between *different* sources (a HealthKit entry
    /// and an unlinked manual tap at the same time) is deliberately **not**
    /// resolved here — the handoff leaves that "keep both, or confirm?" as a
    /// product decision, so this only collapses rows linked by the sample UUID.
    @discardableResult
    public func reconcileAfterRestore() throws -> Int {
        try db.run("""
        UPDATE hydration_log SET deleted_at = ?
        WHERE source_system = ? AND deleted_at IS NULL
          AND external_id IN (
              SELECT healthkit_external_id FROM hydration_log
              WHERE source_system = ? AND healthkit_external_id IS NOT NULL
                AND deleted_at IS NULL
        );
        """, [.text(nowText), .text(healthKitSourceSystem), .text(manualSourceSystem)])
    }
}
