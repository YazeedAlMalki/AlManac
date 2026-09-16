import Foundation

// MARK: - Values

/// A closed set, enforced here rather than by a SQL CHECK (see Migration017's
/// header). Nil at the call site means "not stated" — the same distinction
/// `grams` already draws — not "none of these".
public enum NutritionMealType: String, Sendable, Hashable, CaseIterable {
    case breakfast, lunch, dinner, snack

    public var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }
}

public enum NutritionLogError: Error, CustomStringConvertible, Sendable {
    case entryNotFound(String)
    case invalidGrams(Double)
    case foodRefRequired

    public var description: String {
        switch self {
        case .entryNotFound(let id):
            return "no food log entry with id '\(id)'."
        case .invalidGrams(let g):
            return "grams must be a finite amount greater than zero; got \(g). "
                 + "Leave it nil for 'amount not stated' — that is a different fact from zero."
        case .foodRefRequired:
            return "a log entry is always of some food; food_ref cannot be cleared, only set."
        }
    }
}

/// What a person (or an importer) says was eaten.
///
/// `grams` is optional on purpose: "some rice, amount not stated" is a real
/// entry, and writing 0 for it would claim the meal had no mass.
/// `quantityText` keeps what was actually typed — "2 cups", "one medium" —
/// so that the portions table can re-derive the grams without asking the user
/// again, and so an entry made before a measure exists is not lossy.
public struct NutritionLogDraft: Sendable, Hashable {
    public var sourceSystem: String
    /// The source's own id for this entry. Nil for a manual entry: two
    /// helpings of the same food are two meals, not a duplicate import.
    public var externalID: String?
    public var foodRef: SourceIdentifier
    /// What the food was called when it was logged. Survives the reference
    /// row being removed, which is the point.
    public var foodNameText: String?
    public var grams: Double?
    public var quantityText: String?
    public var eatenAt: PartialDateTime
    public var mealType: NutritionMealType?

    public init(foodRef: SourceIdentifier,
                grams: Double? = nil,
                eatenAt: PartialDateTime = .unknown,
                foodNameText: String? = nil,
                quantityText: String? = nil,
                sourceSystem: String = "manual",
                externalID: String? = nil,
                mealType: NutritionMealType? = nil) {
        self.foodRef = foodRef
        self.grams = grams
        self.eatenAt = eatenAt
        self.foodNameText = foodNameText
        self.quantityText = quantityText
        self.sourceSystem = sourceSystem
        self.externalID = externalID
        self.mealType = mealType
    }
}

/// A correction to a log entry. Same three-case field semantics as the
/// laboratory edit types: leaving a field alone and emptying it are different
/// instructions, and an optional cannot say which was meant.
public struct NutritionLogEdit: Sendable, Hashable {
    public var foodRef: FieldEdit<SourceIdentifier> = .leaveUnchanged
    public var foodNameText: FieldEdit<String> = .leaveUnchanged
    public var grams: FieldEdit<Double> = .leaveUnchanged
    public var quantityText: FieldEdit<String> = .leaveUnchanged
    public var eatenAt: FieldEdit<PartialDateTime> = .leaveUnchanged
    public var mealType: FieldEdit<NutritionMealType> = .leaveUnchanged

    public var actor: String = "user"
    public var reasonText: String? = nil

    public init() {}

    public var touchesAnything: Bool {
        foodRef.isChange || foodNameText.isChange || grams.isChange
            || quantityText.isChange || eatenAt.isChange || mealType.isChange
    }
}

public enum NutritionLogOutcome: Sendable, Hashable {
    case inserted(logID: String)
    case revised(logID: String, revisionID: String, revisionNumber: Int, changedFields: [String])
    case unchanged(logID: String)

    public var logID: String {
        switch self {
        case .inserted(let id), .unchanged(let id): return id
        case .revised(let id, _, _, _): return id
        }
    }
    public var changedFields: [String] {
        if case .revised(_, _, _, let fields) = self { return fields }
        return []
    }
}

/// A log entry as currently held.
public struct NutritionLogEntry: Sendable, Hashable {
    public let id: String
    public let sourceSystem: String
    public let externalID: String?
    public let foodRef: SourceIdentifier
    public let foodNameText: String?
    public let grams: Double?
    public let quantityText: String?
    public let eatenAt: PartialDateTime
    public let mealType: NutritionMealType?
    public let recordedAt: String
    public let deletedAt: String?

    public var isDeleted: Bool { deletedAt != nil }
}

/// A previous state of a log entry, with who changed it and why.
public struct NutritionLogRevision: Sendable, Hashable {
    public let id: String
    public let logID: String
    public let revisionNumber: Int
    public let foodRef: SourceIdentifier
    public let foodNameText: String?
    public let grams: Double?
    public let quantityText: String?
    public let eatenAt: PartialDateTime
    public let mealType: NutritionMealType?
    /// Which fields this revision is the *previous* value of.
    public let changedFields: [String]
    public let actor: String
    public let reasonText: String?
    public let recordedAt: String
}

// MARK: - Store

/// Persistence for the food log, and its timeline provider.
///
/// Holds what was eaten, not what it contained. Energy and nutrient totals are
/// a read-side join against `NutritionCatalog`: keeping them out of here means
/// a corrected reference value corrects every meal already logged against it,
/// instead of leaving thousands of frozen numbers behind.
public struct NutritionLogStore: TimelineProviding, @unchecked Sendable {
    public let domain = "nutrition"
    private let db: Database
    private let clock: any Clock
    private let zone: ZoneContext

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.zone = zone
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }

    private static func validate(grams: Double?) throws {
        guard let g = grams else { return }
        guard g.isFinite, g > 0 else { throw NutritionLogError.invalidGrams(g) }
    }

    // MARK: Writing

    /// Records a meal, or revises the one this source already sent.
    ///
    /// An entry carrying an `externalID` is identified by
    /// `(source_system, external_id)`: re-importing it revises the held entry
    /// rather than adding a second meal, and revives it if the source had
    /// previously withdrawn it. A manual entry has no external id and is
    /// always a new meal.
    ///
    /// The outcome describes what happened to the entry's *values*, so a
    /// re-import that revives a withdrawn entry without changing anything comes
    /// back `.unchanged`. A caller that needs to know the entry is live again
    /// reads `entry(id:)`; treating `.unchanged` as "nothing happened" would
    /// miss the revival.
    @discardableResult
    public func record(_ draft: NutritionLogDraft) throws -> NutritionLogOutcome {
        try NutritionLogStore.validate(grams: draft.grams)
        return try db.transaction { () throws -> NutritionLogOutcome in
            if let externalID = draft.externalID,
               let held = try loadRow(sourceSystem: draft.sourceSystem, externalID: externalID) {
                var edit = NutritionLogEdit()
                edit.actor = draft.sourceSystem
                edit.foodRef = .set(draft.foodRef)
                edit.foodNameText = draft.foodNameText.map { FieldEdit<String>.set($0) } ?? .clear
                edit.grams = draft.grams.map { FieldEdit<Double>.set($0) } ?? .clear
                edit.quantityText = draft.quantityText.map { FieldEdit<String>.set($0) } ?? .clear
                edit.eatenAt = .set(draft.eatenAt)
                edit.mealType = draft.mealType.map { FieldEdit<NutritionMealType>.set($0) } ?? .clear
                let outcome = try applyEdit(to: held, edit)
                // A source re-sending an entry it had withdrawn is asserting it
                // again. Matches HealthSampleStore's revival on re-arrival.
                if held.isDeleted {
                    try db.run("UPDATE nutrition_log SET deleted_at = NULL WHERE id = ?;",
                               [.text(held.id)])
                }
                return outcome
            }

            let id = UUID().uuidString
            try db.run("""
            INSERT INTO nutrition_log
                (id, source_system, external_id, food_ref, food_name_text, grams,
                 quantity_text, eaten_at, eaten_precision, eaten_tz_offset_minutes,
                 eaten_tz_id, recorded_at, recorded_tz_offset_minutes, deleted_at, meal_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?);
            """, [
                .text(id), .text(draft.sourceSystem),
                draft.externalID.map { SQLValue.text($0) } ?? .null,
                .text(draft.foodRef.description),
                draft.foodNameText.map { SQLValue.text($0) } ?? .null,
                draft.grams.map { SQLValue.real($0) } ?? .null,
                draft.quantityText.map { SQLValue.text($0) } ?? .null,
                draft.eatenAt.isKnown ? .text(draft.eatenAt.text) : .null,
                .text(draft.eatenAt.precision.rawValue),
                draft.eatenAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                draft.eatenAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
                .text(nowText),
                zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                draft.mealType.map { SQLValue.text($0.rawValue) } ?? .null
            ])
            return .inserted(logID: id)
        }
    }

    /// Corrects a held entry. Previous values move to
    /// `nutrition_log_revision` with the actor, the reason, and the list of
    /// fields touched — never an unrecorded in-place overwrite.
    @discardableResult
    public func update(id logID: String, _ edit: NutritionLogEdit) throws -> NutritionLogOutcome {
        if case .clear = edit.foodRef { throw NutritionLogError.foodRefRequired }
        guard let held = try loadRow(id: logID) else {
            throw NutritionLogError.entryNotFound(logID)
        }
        guard edit.touchesAnything else { return .unchanged(logID: logID) }
        return try db.transaction { try applyEdit(to: held, edit) }
    }

    /// Soft delete. The entry stops counting and stops appearing on the
    /// timeline; it is not erased, so a mistaken delete is recoverable and an
    /// importer re-asserting the entry revives it.
    @discardableResult
    public func delete(id logID: String) throws -> Bool {
        try db.run("""
            UPDATE nutrition_log SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL;
            """, [.text(nowText), .text(logID)]) == 1
    }

    /// Writes the revision and the new row. Caller owns the transaction.
    private func applyEdit(to held: NutritionLogEntry,
                           _ edit: NutritionLogEdit) throws -> NutritionLogOutcome {
        let foodRef = edit.foodRef.resolve(held.foodRef, cleared: held.foodRef)
        let foodNameText = edit.foodNameText.resolve(held.foodNameText)
        let grams = edit.grams.resolve(held.grams)
        let quantityText = edit.quantityText.resolve(held.quantityText)
        let eatenAt = edit.eatenAt.resolve(held.eatenAt, cleared: .unknown)
        let mealType = edit.mealType.resolve(held.mealType)
        try NutritionLogStore.validate(grams: grams)

        var changed: [String] = []
        if foodRef != held.foodRef { changed.append("food_ref") }
        if foodNameText != held.foodNameText { changed.append("food_name_text") }
        if grams != held.grams { changed.append("grams") }
        if quantityText != held.quantityText { changed.append("quantity_text") }
        if eatenAt != held.eatenAt { changed.append("eaten_at") }
        if mealType != held.mealType { changed.append("meal_type") }
        guard !changed.isEmpty else { return .unchanged(logID: held.id) }

        let next = Int(try db.query("""
            SELECT COALESCE(MAX(revision_number), 0) AS n
            FROM nutrition_log_revision WHERE log_id = ?;
            """, [.text(held.id)]).first?.int("n") ?? 0) + 1
        let revisionID = UUID().uuidString
        try db.run("""
        INSERT INTO nutrition_log_revision
            (id, log_id, revision_number, food_ref, food_name_text, grams, quantity_text,
             eaten_at, eaten_precision, eaten_tz_offset_minutes, eaten_tz_id,
             changed_fields, actor, reason_text, recorded_at, meal_type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(revisionID), .text(held.id), .integer(Int64(next)),
            .text(held.foodRef.description),
            held.foodNameText.map { SQLValue.text($0) } ?? .null,
            held.grams.map { SQLValue.real($0) } ?? .null,
            held.quantityText.map { SQLValue.text($0) } ?? .null,
            held.eatenAt.isKnown ? .text(held.eatenAt.text) : .null,
            .text(held.eatenAt.precision.rawValue),
            held.eatenAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            held.eatenAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
            .text(changed.joined(separator: ",")), .text(edit.actor),
            edit.reasonText.map { SQLValue.text($0) } ?? .null, .text(nowText),
            held.mealType.map { SQLValue.text($0.rawValue) } ?? .null
        ])

        try db.run("""
        UPDATE nutrition_log SET
            food_ref = ?, food_name_text = ?, grams = ?, quantity_text = ?,
            eaten_at = ?, eaten_precision = ?, eaten_tz_offset_minutes = ?, eaten_tz_id = ?,
            meal_type = ?
        WHERE id = ?;
        """, [
            .text(foodRef.description),
            foodNameText.map { SQLValue.text($0) } ?? .null,
            grams.map { SQLValue.real($0) } ?? .null,
            quantityText.map { SQLValue.text($0) } ?? .null,
            eatenAt.isKnown ? .text(eatenAt.text) : .null,
            .text(eatenAt.precision.rawValue),
            eatenAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            eatenAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
            mealType.map { SQLValue.text($0.rawValue) } ?? .null,
            .text(held.id)
        ])
        return .revised(logID: held.id, revisionID: revisionID,
                        revisionNumber: next, changedFields: changed)
    }

    // MARK: Reading

    private static let columns = """
        id, source_system, external_id, food_ref, food_name_text, grams, quantity_text,
        eaten_at, eaten_precision, eaten_tz_offset_minutes, eaten_tz_id,
        recorded_at, deleted_at, meal_type
        """

    public func entry(id logID: String) throws -> NutritionLogEntry? {
        try loadRow(id: logID)
    }

    private func loadRow(id logID: String) throws -> NutritionLogEntry? {
        try db.query("SELECT \(NutritionLogStore.columns) FROM nutrition_log WHERE id = ?;",
                     [.text(logID)]).first.flatMap(NutritionLogStore.entry(from:))
    }

    private func loadRow(sourceSystem: String, externalID: String) throws -> NutritionLogEntry? {
        try db.query("""
            SELECT \(NutritionLogStore.columns) FROM nutrition_log
            WHERE source_system = ? AND external_id = ?;
            """, [.text(sourceSystem), .text(externalID)])
            .first.flatMap(NutritionLogStore.entry(from:))
    }

    public func revisions(of logID: String) throws -> [NutritionLogRevision] {
        try db.query("""
            SELECT id, log_id, revision_number, food_ref, food_name_text, grams,
                   quantity_text, eaten_at, eaten_precision, eaten_tz_offset_minutes,
                   eaten_tz_id, changed_fields, actor, reason_text, recorded_at, meal_type
            FROM nutrition_log_revision WHERE log_id = ? ORDER BY revision_number;
            """, [.text(logID)]).compactMap { row in
            guard let id = row.string("id"), let rowLogID = row.string("log_id"),
                  let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let eaten = NutritionLogStore.eatenAt(row) else { return nil }
            return NutritionLogRevision(
                id: id, logID: rowLogID,
                revisionNumber: Int(row.int("revision_number") ?? 0),
                foodRef: ref, foodNameText: row.string("food_name_text"),
                grams: row.double("grams"), quantityText: row.string("quantity_text"),
                eatenAt: eaten,
                mealType: row.string("meal_type").flatMap(NutritionMealType.init(rawValue:)),
                changedFields: (row.string("changed_fields") ?? "")
                    .split(separator: ",").map(String.init),
                actor: row.string("actor") ?? "", reasonText: row.string("reason_text"),
                recordedAt: row.string("recorded_at") ?? "")
        }
    }

    private static func eatenAt(_ row: Row) -> PartialDateTime? {
        PartialDateTime(
            storedText: row.string("eaten_at") ?? "",
            precision: TimePrecision(rawValue: row.string("eaten_precision") ?? "") ?? .unknown,
            zone: ZoneContext(offsetMinutes: row.int("eaten_tz_offset_minutes").map(Int.init),
                              identifier: row.string("eaten_tz_id")))
    }

    private static func entry(from row: Row) -> NutritionLogEntry? {
        guard let id = row.string("id"),
              let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
              let eaten = eatenAt(row) else { return nil }
        return NutritionLogEntry(
            id: id, sourceSystem: row.string("source_system") ?? "",
            externalID: row.string("external_id"), foodRef: ref,
            foodNameText: row.string("food_name_text"), grams: row.double("grams"),
            quantityText: row.string("quantity_text"), eatenAt: eaten,
            mealType: row.string("meal_type").flatMap(NutritionMealType.init(rawValue:)),
            recordedAt: row.string("recorded_at") ?? "",
            deletedAt: row.string("deleted_at"))
    }

    /// Live entries placed in `[from, to)`, with their placement.
    ///
    /// The domain-value counterpart of `entries(from:to:)`: the timeline gets
    /// presentation, a totals or day screen gets the grams and the food ref it
    /// needs to join on. Both go through `placed` so the two can never disagree
    /// about which meals fall in a range.
    public func logged(from: String, to: String) throws -> [PlacedLogEntry] {
        guard let range = DateRange(from: from, to: to) else { return [] }
        return try liveRows().compactMap { NutritionLogStore.placed($0, in: range) }
    }

    /// A log entry with the time the timeline would place it at.
    public struct PlacedLogEntry: Sendable, Hashable {
        public let entry: NutritionLogEntry
        public let occurrence: PartialDateTime
        public let basis: TimeBasis
        public let rangeFit: RangeFit
    }

    private func liveRows() throws -> [Row] {
        try db.query("""
            SELECT \(NutritionLogStore.columns) FROM nutrition_log
            WHERE deleted_at IS NULL;
            """)
    }

    /// Placement is the eaten time, else when it was recorded. There is no
    /// `reported` basis here: a meal has no report, and falling back to
    /// `recorded_at` is the same weaker claim Laboratory marks that way.
    /// Nil when the entry cannot belong to the range at all.
    private static func placed(_ row: Row, in range: DateRange) -> PlacedLogEntry? {
        guard let held = entry(from: row) else { return nil }
        let occurrence: PartialDateTime
        let basis: TimeBasis
        if held.eatenAt.isKnown {
            occurrence = held.eatenAt
            basis = .occurrence
        } else if let recorded = PartialDateTime(storedText: held.recordedAt,
                                                 precision: .instant) {
            occurrence = recorded
            basis = .recorded
        } else {
            return nil
        }
        guard let fit = occurrence.fit(in: range) else { return nil }
        return PlacedLogEntry(entry: held, occurrence: occurrence, basis: basis, rangeFit: fit)
    }

    // MARK: - TimelineProviding

    public func entries(from: String, to: String) throws -> [TimelineEntry] {
        guard let range = DateRange(from: from, to: to) else { return [] }
        return try liveRows().compactMap { row in
            guard let placed = NutritionLogStore.placed(row, in: range) else { return nil }
            let held = placed.entry

            let value: ValuePresentation
            if let grams = held.grams {
                value = .quantity(text: String(grams), unit: "g")
            } else {
                // Not zero. Nobody said how much, which is a different fact —
                // the same distinction NutrientQualifier draws for nutrients.
                value = .missing(reason: "amount not stated")
            }
            return TimelineEntry(
                domain: domain, kind: "food", recordTable: "nutrition_log",
                recordID: held.id, occurrence: placed.occurrence, basis: placed.basis,
                title: held.foodNameText ?? held.foodRef.description,
                detail: held.quantityText, value: value, lifecycle: nil,
                rangeFit: placed.rangeFit)
        }
    }
}
