import Foundation

public struct LabReportDraft: Sendable {
    public var id: String = UUID().uuidString
    public var sourceSystem: String? = nil
    public var sourceReportID: String? = nil
    public var laboratoryNameText: String? = nil
    public var reportedAt: PartialDateTime = .unknown
    public var headerText: String? = nil
    public var entryOrigin: String = "manual"
    public init() {}
}

/// Everything needed to locate or create the **stable** observation.
/// Revision content is passed separately, because the two have different
/// lifetimes: this identifies the thing, that versions its content.
public struct LabObservationDraft: Sendable {
    public var reportID: String? = nil
    public var sourceSystem: String? = nil
    public var sourceObservationID: String? = nil
    public var catalogAnalyteID: String? = nil
    public var matchOrigin: String? = nil
    public var matchConfidence: String? = nil
    public var timePointLabel: String? = nil
    /// Distinguishes legitimate repeats that the source did not separately
    /// identify. Never used to disambiguate revisions.
    public var repeatIndex: Int = 0
    public var collectedAt: PartialDateTime = .unknown
    public var specimenText: String? = nil
    public init() {}
}

public enum LabRecordOutcome: Sendable, Hashable {
    case created(observationID: String, revisionID: String)
    case revised(observationID: String, revisionID: String, revisionNumber: Int)
    case unchanged(observationID: String, revisionID: String)

    public var observationID: String {
        switch self {
        case .created(let o, _), .revised(let o, _, _), .unchanged(let o, _): return o
        }
    }
    public var isNoOp: Bool { if case .unchanged = self { return true }; return false }
}

public struct LabRevision: Sendable {
    public let id: String
    public let observationID: String
    public let revisionNumber: Int
    public let isCurrent: Bool
    public let content: LabRevisionContent
    public let recordedAt: String
}

/// Persistence for the Laboratory module, and its timeline provider.
///
/// `record` runs in its own transaction; do not call it from inside another.
public struct LabStore: TimelineProviding, @unchecked Sendable {
    public let domain = "laboratory"
    private let db: Database
    private let clock: any Clock
    private let catalog: LabCatalogStore
    private let zone: ZoneContext

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.catalog = LabCatalogStore(db: db, clock: clock)
        self.zone = zone
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }

    // MARK: - Reports

    @discardableResult
    public func saveReport(_ draft: LabReportDraft) throws -> String {
        if let system = draft.sourceSystem, let sourceID = draft.sourceReportID,
           let existing = try db.query("""
               SELECT id FROM lab_report WHERE source_system = ? AND source_report_id = ?;
               """, [.text(system), .text(sourceID)]).first?.string("id") {
            return existing
        }
        try db.run("""
        INSERT INTO lab_report
            (id, source_system, source_report_id, laboratory_name_text, reported_at,
             reported_precision, reported_tz_offset_minutes, reported_tz_id, header_text,
             entry_origin, recorded_at, recorded_tz_offset_minutes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.id),
            draft.sourceSystem.map { SQLValue.text($0) } ?? .null,
            draft.sourceReportID.map { SQLValue.text($0) } ?? .null,
            draft.laboratoryNameText.map { SQLValue.text($0) } ?? .null,
            draft.reportedAt.isKnown ? .text(draft.reportedAt.text) : .null,
            .text(draft.reportedAt.precision.rawValue),
            draft.reportedAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.reportedAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
            draft.headerText.map { SQLValue.text($0) } ?? .null,
            .text(draft.entryOrigin),
            .text(nowText),
            zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null
        ])
        return draft.id
    }

    // MARK: - Observations and revisions

    /// Find-or-create the observation, then append a revision unless identical
    /// content is already held.
    @discardableResult
    public func record(_ draft: LabObservationDraft,
                       content rawContent: LabRevisionContent) throws -> LabRecordOutcome {
        let content = try rawContent.validated()
        var observation = draft

        if observation.catalogAnalyteID == nil,
           let match = try catalog.match(sourceText: content.sourceAnalyteText) {
            observation.catalogAnalyteID = match.analyteID
            observation.matchOrigin = match.origin
            observation.matchConfidence = match.confidence
        }

        return try db.transaction {
            let existingID: String?
            if let system = observation.sourceSystem, let sourceID = observation.sourceObservationID {
                existingID = try db.query("""
                    SELECT id FROM lab_observation
                    WHERE source_system = ? AND source_observation_id = ?;
                    """, [.text(system), .text(sourceID)]).first?.string("id")
            } else {
                existingID = nil
            }

            if let observationID = existingID {
                let fingerprint = content.fingerprint
                if let held = try db.query("""
                    SELECT id FROM lab_observation_revision
                    WHERE observation_id = ? AND content_fingerprint = ?;
                    """, [.text(observationID), .text(fingerprint)]).first?.string("id") {
                    return .unchanged(observationID: observationID, revisionID: held)
                }
                let next = Int(try db.query("""
                    SELECT COALESCE(MAX(revision_number), 0) AS n
                    FROM lab_observation_revision WHERE observation_id = ?;
                    """, [.text(observationID)]).first?.int("n") ?? 0) + 1
                try db.run("""
                    UPDATE lab_observation_revision SET is_current = 0 WHERE observation_id = ?;
                    """, [.text(observationID)])
                let revisionID = try insertRevision(observationID: observationID,
                                                    number: next, content: content)
                return .revised(observationID: observationID, revisionID: revisionID,
                                revisionNumber: next)
            }

            let observationID = UUID().uuidString
            try db.run("""
            INSERT INTO lab_observation
                (id, report_id, source_system, source_observation_id, catalog_analyte_id,
                 match_origin, match_confidence, time_point_label, repeat_index,
                 collected_at, collected_precision, collected_tz_offset_minutes,
                 collected_tz_id, specimen_text, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(observationID),
                observation.reportID.map { SQLValue.text($0) } ?? .null,
                observation.sourceSystem.map { SQLValue.text($0) } ?? .null,
                observation.sourceObservationID.map { SQLValue.text($0) } ?? .null,
                observation.catalogAnalyteID.map { SQLValue.text($0) } ?? .null,
                observation.matchOrigin.map { SQLValue.text($0) } ?? .null,
                observation.matchConfidence.map { SQLValue.text($0) } ?? .null,
                observation.timePointLabel.map { SQLValue.text($0) } ?? .null,
                .integer(Int64(observation.repeatIndex)),
                observation.collectedAt.isKnown ? .text(observation.collectedAt.text) : .null,
                .text(observation.collectedAt.precision.rawValue),
                observation.collectedAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                observation.collectedAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
                observation.specimenText.map { SQLValue.text($0) } ?? .null,
                .text(nowText)
            ])
            let revisionID = try insertRevision(observationID: observationID,
                                                number: 1, content: content)
            return .created(observationID: observationID, revisionID: revisionID)
        }
    }

    private func insertRevision(observationID: String, number: Int,
                                content: LabRevisionContent) throws -> String {
        let id = UUID().uuidString
        try db.run("""
        INSERT INTO lab_observation_revision
            (id, observation_id, revision_number, source_revision_id, is_current, lifecycle,
             value_type, comparator, derivation, missing_reason, numeric_value, coded_value,
             text_value, ratio_numerator, ratio_denominator, titer_numerator, titer_denominator,
             unit_text, lod_text, loq_text, range_text, range_low, range_high, range_unit_text,
             flag_text, comment_text, method_text, source_analyte_text, source_value_text,
             content_origin, actor, recorded_at, reason_text, content_fingerprint)
        VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(id), .text(observationID), .integer(Int64(number)),
            content.sourceRevisionID.map { SQLValue.text($0) } ?? .null,
            .text(content.lifecycle.rawValue), .text(content.valueType.rawValue),
            .text(content.comparator.rawValue), .text(content.derivation.rawValue),
            content.missingReason.map { SQLValue.text($0.rawValue) } ?? .null,
            content.numericValue.map { SQLValue.real($0) } ?? .null,
            content.codedValue.map { SQLValue.text($0) } ?? .null,
            content.textValue.map { SQLValue.text($0) } ?? .null,
            content.ratioNumerator.map { SQLValue.real($0) } ?? .null,
            content.ratioDenominator.map { SQLValue.real($0) } ?? .null,
            content.titerNumerator.map { SQLValue.integer(Int64($0)) } ?? .null,
            content.titerDenominator.map { SQLValue.integer(Int64($0)) } ?? .null,
            content.unitText.map { SQLValue.text($0) } ?? .null,
            content.lodText.map { SQLValue.text($0) } ?? .null,
            content.loqText.map { SQLValue.text($0) } ?? .null,
            content.rangeText.map { SQLValue.text($0) } ?? .null,
            content.rangeLow.map { SQLValue.real($0) } ?? .null,
            content.rangeHigh.map { SQLValue.real($0) } ?? .null,
            content.rangeUnitText.map { SQLValue.text($0) } ?? .null,
            content.flagText.map { SQLValue.text($0) } ?? .null,
            content.commentText.map { SQLValue.text($0) } ?? .null,
            content.methodText.map { SQLValue.text($0) } ?? .null,
            content.sourceAnalyteText.map { SQLValue.text($0) } ?? .null,
            content.sourceValueText.map { SQLValue.text($0) } ?? .null,
            .text(content.contentOrigin.rawValue), .text(content.actor),
            .text(nowText),
            content.reasonText.map { SQLValue.text($0) } ?? .null,
            .text(content.fingerprint)
        ])
        return id
    }

    // MARK: - Reading

    public func currentRevision(of observationID: String) throws -> LabRevision? {
        try revisions(of: observationID).first { $0.isCurrent }
    }

    /// Full history, oldest first. Nothing is ever removed from this.
    public func revisions(of observationID: String) throws -> [LabRevision] {
        try db.query("""
        SELECT * FROM lab_observation_revision
        WHERE observation_id = ? ORDER BY revision_number;
        """, [.text(observationID)]).compactMap(LabStore.revision(from:))
    }

    public func observationIDs(inReport reportID: String) throws -> [String] {
        try db.query("""
        SELECT id FROM lab_observation WHERE report_id = ? ORDER BY repeat_index, created_at;
        """, [.text(reportID)]).compactMap { $0.string("id") }
    }

    public func catalogAnalyteID(of observationID: String) throws -> String? {
        try db.query("SELECT catalog_analyte_id FROM lab_observation WHERE id = ?;",
                     [.text(observationID)]).first?.string("catalog_analyte_id")
    }

    static func revision(from row: Row) -> LabRevision? {
        guard let id = row.string("id"), let observationID = row.string("observation_id"),
              let number = row.int("revision_number") else { return nil }
        var c = LabRevisionContent()
        c.lifecycle = LabLifecycle(rawValue: row.string("lifecycle") ?? "") ?? .unknown
        c.valueType = LabValueType(rawValue: row.string("value_type") ?? "") ?? .absent
        c.comparator = LabComparator(rawValue: row.string("comparator") ?? "") ?? .none
        c.derivation = LabDerivation(rawValue: row.string("derivation") ?? "") ?? .unknown
        c.missingReason = row.string("missing_reason").flatMap(LabMissingReason.init(rawValue:))
        c.numericValue = row.double("numeric_value")
        c.codedValue = row.string("coded_value")
        c.textValue = row.string("text_value")
        c.ratioNumerator = row.double("ratio_numerator")
        c.ratioDenominator = row.double("ratio_denominator")
        c.titerNumerator = row.int("titer_numerator").map(Int.init)
        c.titerDenominator = row.int("titer_denominator").map(Int.init)
        c.unitText = row.string("unit_text")
        c.lodText = row.string("lod_text")
        c.loqText = row.string("loq_text")
        c.rangeText = row.string("range_text")
        c.rangeLow = row.double("range_low")
        c.rangeHigh = row.double("range_high")
        c.rangeUnitText = row.string("range_unit_text")
        c.flagText = row.string("flag_text")
        c.commentText = row.string("comment_text")
        c.methodText = row.string("method_text")
        c.sourceAnalyteText = row.string("source_analyte_text")
        c.sourceValueText = row.string("source_value_text")
        c.contentOrigin = LabContentOrigin(rawValue: row.string("content_origin") ?? "")
            ?? .userTranscription
        c.actor = row.string("actor") ?? "unknown"
        c.reasonText = row.string("reason_text")
        c.sourceRevisionID = row.string("source_revision_id")
        return LabRevision(id: id, observationID: observationID, revisionNumber: Int(number),
                           isCurrent: (row.int("is_current") ?? 0) == 1, content: c,
                           recordedAt: row.string("recorded_at") ?? "")
    }

    // MARK: - TimelineProviding

    /// Current revisions only. History stays reachable through `revisions(of:)`.
    ///
    /// Range filtering happens in Swift because the placing time is chosen per
    /// row (collected, else reported, else recorded) and that choice must be
    /// visible in the entry. Pushing it into SQL is a later optimisation, not a
    /// correctness change.
    public func entries(from: String, to: String) throws -> [TimelineEntry] {
        let rows = try db.query("""
        SELECT o.id            AS obs_id,
               o.collected_at, o.collected_precision,
               o.collected_tz_offset_minutes, o.collected_tz_id,
               o.time_point_label, o.repeat_index, o.created_at,
               o.catalog_analyte_id,
               r.reported_at, r.reported_precision, r.reported_tz_offset_minutes,
               r.reported_tz_id,
               a.canonical_name,
               rev.id AS rev_id, rev.lifecycle, rev.value_type, rev.comparator,
               rev.derivation, rev.missing_reason, rev.numeric_value, rev.coded_value,
               rev.text_value, rev.ratio_numerator, rev.ratio_denominator,
               rev.titer_numerator, rev.titer_denominator, rev.unit_text,
               rev.source_analyte_text, rev.source_value_text
        FROM lab_observation o
        JOIN lab_observation_revision rev
             ON rev.observation_id = o.id AND rev.is_current = 1
        LEFT JOIN lab_report r ON r.id = o.report_id
        LEFT JOIN lab_catalog_analyte a ON a.id = o.catalog_analyte_id;
        """)

        var entries: [TimelineEntry] = []
        for row in rows {
            guard let observationID = row.string("obs_id") else { continue }
            let (occurrence, basis) = LabStore.placement(row)
            guard occurrence.isKnown, occurrence.text >= from, occurrence.text < to else { continue }

            var content = LabRevisionContent()
            content.valueType = LabValueType(rawValue: row.string("value_type") ?? "") ?? .absent
            content.comparator = LabComparator(rawValue: row.string("comparator") ?? "") ?? .none
            content.derivation = LabDerivation(rawValue: row.string("derivation") ?? "") ?? .unknown
            content.missingReason = row.string("missing_reason")
                .flatMap(LabMissingReason.init(rawValue:))
            content.numericValue = row.double("numeric_value")
            content.codedValue = row.string("coded_value")
            content.textValue = row.string("text_value")
            content.ratioNumerator = row.double("ratio_numerator")
            content.ratioDenominator = row.double("ratio_denominator")
            content.titerNumerator = row.int("titer_numerator").map(Int.init)
            content.titerDenominator = row.int("titer_denominator").map(Int.init)
            content.unitText = row.string("unit_text")
            content.sourceValueText = row.string("source_value_text")
            content.sourceAnalyteText = row.string("source_analyte_text")

            let unmatched = row.isNull("catalog_analyte_id")
            let title = row.string("canonical_name")
                ?? row.string("source_analyte_text")
                ?? "(test not named)"
            var detailParts: [String] = []
            if let label = row.string("time_point_label") { detailParts.append(label) }
            if unmatched { detailParts.append("unmatched: not in catalog") }

            entries.append(TimelineEntry(
                domain: domain, kind: "observation",
                recordTable: "lab_observation", recordID: observationID,
                occurrence: occurrence, basis: basis, title: title,
                detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
                value: content.presentation,
                lifecycle: row.string("lifecycle")))
        }
        return entries
    }

    /// Collected time, else the report's time, else when it was entered.
    /// The basis travels with the entry so an entry-date fallback is never
    /// mistaken for an occurrence.
    static func placement(_ row: Row) -> (PartialDateTime, TimeBasis) {
        if let text = row.string("collected_at"),
           let precision = TimePrecision(rawValue: row.string("collected_precision") ?? ""),
           let value = PartialDateTime(storedText: text, precision: precision,
                                       zone: ZoneContext(
                                        offsetMinutes: row.int("collected_tz_offset_minutes").map(Int.init),
                                        identifier: row.string("collected_tz_id"))) {
            return (value, .occurrence)
        }
        if let text = row.string("reported_at"),
           let precision = TimePrecision(rawValue: row.string("reported_precision") ?? ""),
           let value = PartialDateTime(storedText: text, precision: precision,
                                       zone: ZoneContext(
                                        offsetMinutes: row.int("reported_tz_offset_minutes").map(Int.init),
                                        identifier: row.string("reported_tz_id"))) {
            return (value, .reported)
        }
        if let created = row.string("created_at"),
           let value = PartialDateTime(storedText: created, precision: .instant) {
            return (value, .recorded)
        }
        return (.unknown, .recorded)
    }
}
