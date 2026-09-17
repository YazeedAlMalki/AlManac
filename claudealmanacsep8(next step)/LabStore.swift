import Foundation

public struct LabReportDraft: Sendable {
    public var id: String = UUID().uuidString
    public var sourceSystem: String? = nil
    public var sourceReportID: String? = nil
    public var laboratoryNameText: String? = nil
    public var reportedAt: PartialDateTime = .unknown
    public var headerText: String? = nil
    public var entryOrigin: String = "manual"
    /// What the source says about where this version sits in its own sequence.
    /// Left `.unavailable` when the source says nothing, which is common and
    /// is handled by flagging a conflict rather than trusting arrival order.
    public var sourceOrdering: SourceOrdering = .unavailable
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
    /// The specimen as classified. Defaults to `.unknown`, which is a recorded
    /// answer and never blocks an incomplete manual entry.
    public var specimenKind: SpecimenKind = .unknown
    /// The specimen exactly as the source printed it, preserved alongside the
    /// classification and never replaced by it.
    public var specimenText: String? = nil
    public init() {}
}

public enum LabReportOutcome: Sendable, Hashable {
    case created(reportID: String)
    /// The incoming version is identical to what is already current.
    case unchanged(reportID: String)
    /// The live row now carries the new values; `supersededRevisionID` holds
    /// what it said before.
    case updated(reportID: String, supersededRevisionID: String, revisionNumber: Int)
    /// A version already in this report's history arrived again. Nothing
    /// changes: a re-send of an older version is not a correction back to it.
    case replayIgnored(reportID: String, matchedRevisionID: String)
    /// The source ranks this version below the one held. Nothing changes.
    case staleIgnored(reportID: String)
    /// New content that cannot be ranked against what is held, because the
    /// source stated no ordering or an incomparable kind. **The current
    /// version is left alone** and the incoming one is recorded for a human to
    /// resolve — arrival order is not evidence of authority.
    case conflict(reportID: String, conflictingRevisionID: String)

    public var reportID: String {
        switch self {
        case .created(let id), .unchanged(let id), .staleIgnored(let id): return id
        case .updated(let id, _, _): return id
        case .replayIgnored(let id, _), .conflict(let id, _): return id
        }
    }

    /// True when the stored current version is not what just arrived.
    public var needsHumanResolution: Bool {
        if case .conflict = self { return true }
        return false
    }
}

/// A superseded set of report-level metadata.
public struct LabReportRevision: Sendable, Hashable {
    public let id: String
    public let reportID: String
    public let revisionNumber: Int
    public let laboratoryNameText: String?
    public let reportedAtText: String?
    public let supersededAt: String
    /// `superseded` · `superseded_unranked` · `conflict`. A conflict is not a
    /// past version of the live row; it is a version that was never applied.
    public let kind: String
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
    let db: Database
    private let clock: any Clock
    private let catalog: LabCatalogStore
    private let zone: ZoneContext
    private let unrankedImports: UnrankedImportPolicy

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current),
                unrankedImports: UnrankedImportPolicy = .applyAndFlag) {
        self.db = db
        self.clock = clock
        self.catalog = LabCatalogStore(db: db, clock: clock)
        self.zone = zone
        self.unrankedImports = unrankedImports
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }

    // MARK: - Reports

    /// Returns the report's id. See `upsertReport` for what happened to it.
    @discardableResult
    public func saveReport(_ draft: LabReportDraft) throws -> String {
        try upsertReport(draft).reportID
    }

    /// Find-or-create by `(source_system, source_report_id)`, and — the point
    /// of this method — **never silently discard changed report metadata**.
    ///
    /// A laboratory that reissues a report with a corrected draw date or a
    /// corrected name is stating a fact. The previous values move to
    /// `lab_report_revision` and the live row takes the new ones, so neither
    /// the correction nor what it replaced is lost.
    @discardableResult
    public func upsertReport(_ draft: LabReportDraft) throws -> LabReportOutcome {
        if let system = draft.sourceSystem, let sourceID = draft.sourceReportID,
           let existing = try db.query("""
               SELECT id, laboratory_name_text, reported_at, reported_precision,
                      reported_tz_offset_minutes, reported_tz_id, header_text,
                      source_ordering_kind, source_ordering_text
               FROM lab_report WHERE source_system = ? AND source_report_id = ?;
               """, [.text(system), .text(sourceID)]).first,
           let reportID = existing.string("id") {

            let stored = LabStore.reportFingerprint(
                laboratoryName: existing.string("laboratory_name_text"),
                reportedAt: existing.string("reported_at"),
                precision: existing.string("reported_precision") ?? TimePrecision.unknown.rawValue,
                offsetMinutes: existing.int("reported_tz_offset_minutes").map(Int.init),
                zoneID: existing.string("reported_tz_id"),
                header: existing.string("header_text"))
            let incoming = LabStore.reportFingerprint(
                laboratoryName: draft.laboratoryNameText,
                reportedAt: draft.reportedAt.isKnown ? draft.reportedAt.text : nil,
                precision: draft.reportedAt.precision.rawValue,
                offsetMinutes: draft.reportedAt.zone.offsetMinutes,
                zoneID: draft.reportedAt.zone.identifier,
                header: draft.headerText)

            if stored == incoming { return .unchanged(reportID: reportID) }

            let held = SourceOrdering.from(kind: existing.string("source_ordering_kind"),
                                           value: existing.string("source_ordering_text"))
            let ranking = draft.sourceOrdering.compare(to: held)

            // Ordering first, history second. A source that explicitly ranks
            // this version above the one held is correcting the record, and it
            // is allowed to correct it *back* to an earlier value — that is a
            // deliberate revert, not a replay, and the two are only
            // distinguishable by the ordering marker.
            if ranking == .orderedDescending {
                return try supersedeReport(reportID: reportID, existing: existing,
                                           storedFingerprint: stored, draft: draft,
                                           kind: "superseded")
            }
            if ranking == .orderedAscending || ranking == .orderedSame {
                return .staleIgnored(reportID: reportID)
            }

            // Unrankable. If this exact content is already somewhere in the
            // history, it is a re-send of a version we have seen — the stale
            // reimport case — and it must not become current again.
            if let seen = try db.query("""
                SELECT id FROM lab_report_revision
                WHERE report_id = ? AND content_fingerprint = ?
                ORDER BY revision_number LIMIT 1;
                """, [.text(reportID), .text(incoming)]).first?.string("id") {
                return .replayIgnored(reportID: reportID, matchedRevisionID: seen)
            }

            switch unrankedImports {
            case .applyAndFlag:
                // Applied, and recorded as unranked so the assumption is
                // visible rather than implied. `.holdAsConflict` is the
                // stricter policy for a source that must never do this.
                return try supersedeReport(reportID: reportID, existing: existing,
                                           storedFingerprint: stored, draft: draft,
                                           kind: "superseded_unranked")
            case .holdAsConflict:
                return try recordReportConflict(reportID: reportID, draft: draft,
                                                fingerprint: incoming)
            }
        }
        try db.run("""
        INSERT INTO lab_report
            (id, source_system, source_report_id, laboratory_name_text, reported_at,
             reported_precision, reported_tz_offset_minutes, reported_tz_id, header_text,
             entry_origin, recorded_at, recorded_tz_offset_minutes,
             source_ordering_kind, source_ordering_text)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.sourceOrdering.kindText.map { SQLValue.text($0) } ?? .null,
            draft.sourceOrdering.valueText.map { SQLValue.text($0) } ?? .null
        ])
        return .created(reportID: draft.id)
    }

    /// Moves the held values into the history and puts the draft's on the live
    /// row. `kind` records whether the source ranked this change or not.
    private func supersedeReport(reportID: String, existing: Row, storedFingerprint: String,
                                 draft: LabReportDraft, kind: String) throws -> LabReportOutcome {
        try db.transaction {
            let number = try nextReportRevisionNumber(reportID)
            let revisionID = UUID().uuidString
            try db.run("""
            INSERT INTO lab_report_revision
                (id, report_id, revision_number, laboratory_name_text, reported_at,
                 reported_precision, reported_tz_offset_minutes, reported_tz_id,
                 header_text, content_fingerprint, actor, superseded_at, kind,
                 source_ordering_kind, source_ordering_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(revisionID), .text(reportID), .integer(Int64(number)),
                existing.string("laboratory_name_text").map { SQLValue.text($0) } ?? .null,
                existing.string("reported_at").map { SQLValue.text($0) } ?? .null,
                .text(existing.string("reported_precision") ?? TimePrecision.unknown.rawValue),
                existing.int("reported_tz_offset_minutes").map { SQLValue.integer($0) } ?? .null,
                existing.string("reported_tz_id").map { SQLValue.text($0) } ?? .null,
                existing.string("header_text").map { SQLValue.text($0) } ?? .null,
                .text(storedFingerprint), .text(draft.entryOrigin), .text(nowText), .text(kind),
                existing.string("source_ordering_kind").map { SQLValue.text($0) } ?? .null,
                existing.string("source_ordering_text").map { SQLValue.text($0) } ?? .null
            ])
            try db.run("""
            UPDATE lab_report SET
                laboratory_name_text       = ?,
                reported_at                = ?,
                reported_precision         = ?,
                reported_tz_offset_minutes = ?,
                reported_tz_id             = ?,
                header_text                = ?,
                source_ordering_kind       = ?,
                source_ordering_text       = ?
            WHERE id = ?;
            """, [
                draft.laboratoryNameText.map { SQLValue.text($0) } ?? .null,
                draft.reportedAt.isKnown ? .text(draft.reportedAt.text) : .null,
                .text(draft.reportedAt.precision.rawValue),
                draft.reportedAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                draft.reportedAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
                draft.headerText.map { SQLValue.text($0) } ?? .null,
                draft.sourceOrdering.kindText.map { SQLValue.text($0) } ?? .null,
                draft.sourceOrdering.valueText.map { SQLValue.text($0) } ?? .null,
                .text(reportID)
            ])
            return .updated(reportID: reportID, supersededRevisionID: revisionID,
                            revisionNumber: number)
        }
    }

    /// Records the *incoming* version without touching what is current.
    private func recordReportConflict(reportID: String, draft: LabReportDraft,
                                      fingerprint: String) throws -> LabReportOutcome {
        // A conflict already logged for this exact content is not logged twice.
        if let existing = try db.query("""
            SELECT id FROM lab_report_revision
            WHERE report_id = ? AND content_fingerprint = ? AND kind = 'conflict' LIMIT 1;
            """, [.text(reportID), .text(fingerprint)]).first?.string("id") {
            return .conflict(reportID: reportID, conflictingRevisionID: existing)
        }
        return try db.transaction {
            let number = try nextReportRevisionNumber(reportID)
            let revisionID = UUID().uuidString
            try db.run("""
            INSERT INTO lab_report_revision
                (id, report_id, revision_number, laboratory_name_text, reported_at,
                 reported_precision, reported_tz_offset_minutes, reported_tz_id,
                 header_text, content_fingerprint, actor, superseded_at, kind,
                 source_ordering_kind, source_ordering_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'conflict', ?, ?);
            """, [
                .text(revisionID), .text(reportID), .integer(Int64(number)),
                draft.laboratoryNameText.map { SQLValue.text($0) } ?? .null,
                draft.reportedAt.isKnown ? .text(draft.reportedAt.text) : .null,
                .text(draft.reportedAt.precision.rawValue),
                draft.reportedAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                draft.reportedAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
                draft.headerText.map { SQLValue.text($0) } ?? .null,
                .text(fingerprint), .text(draft.entryOrigin), .text(nowText),
                draft.sourceOrdering.kindText.map { SQLValue.text($0) } ?? .null,
                draft.sourceOrdering.valueText.map { SQLValue.text($0) } ?? .null
            ])
            return .conflict(reportID: reportID, conflictingRevisionID: revisionID)
        }
    }

    private func nextReportRevisionNumber(_ reportID: String) throws -> Int {
        Int(try db.query("""
            SELECT COALESCE(MAX(revision_number), 0) AS n
            FROM lab_report_revision WHERE report_id = ?;
            """, [.text(reportID)]).first?.int("n") ?? 0) + 1
    }

    static func reportFingerprint(laboratoryName: String?, reportedAt: String?,
                                  precision: String, offsetMinutes: Int?,
                                  zoneID: String?, header: String?) -> String {
        let parts: [String?] = [laboratoryName, reportedAt, precision,
                                offsetMinutes.map { String($0) }, zoneID, header]
        return SHA256File.hex(of: Array(parts.map { $0 ?? "\u{0}" }
            .joined(separator: "\u{1}").utf8))
    }

    /// Superseded report metadata, oldest first.
    public func reportRevisions(of reportID: String) throws -> [LabReportRevision] {
        try db.query("""
        SELECT id, report_id, revision_number, laboratory_name_text, reported_at,
               superseded_at, kind
        FROM lab_report_revision WHERE report_id = ? ORDER BY revision_number;
        """, [.text(reportID)]).compactMap { row in
            guard let id = row.string("id"), let reportID = row.string("report_id"),
                  let number = row.int("revision_number") else { return nil }
            return LabReportRevision(
                id: id, reportID: reportID, revisionNumber: Int(number),
                laboratoryNameText: row.string("laboratory_name_text"),
                reportedAtText: row.string("reported_at"),
                supersededAt: row.string("superseded_at") ?? "",
                kind: row.string("kind") ?? "superseded")
        }
    }

    // MARK: - Editing by Almanac-owned identity

    /// Corrects a report a person owns, addressed by Almanac's id.
    ///
    /// No source system, no source report id, no ordering marker: a person
    /// editing their own record is the authority on it, so this never has to
    /// invent an external identifier to get a correction accepted.
    @discardableResult
    public func updateReport(id reportID: String,
                             _ edit: LabReportEdit) throws -> LabReportOutcome {
        guard let existing = try db.query("""
            SELECT id, laboratory_name_text, reported_at, reported_precision,
                   reported_tz_offset_minutes, reported_tz_id, header_text,
                   source_ordering_kind, source_ordering_text
            FROM lab_report WHERE id = ?;
            """, [.text(reportID)]).first else {
            throw LabError.reportNotFound(reportID)
        }
        guard edit.touchesAnything else { return .unchanged(reportID: reportID) }

        let currentReportedAt = PartialDateTime(
            storedText: existing.string("reported_at") ?? "",
            precision: TimePrecision(rawValue: existing.string("reported_precision") ?? "")
                ?? .unknown,
            zone: ZoneContext(offsetMinutes: existing.int("reported_tz_offset_minutes").map(Int.init),
                              identifier: existing.string("reported_tz_id"))) ?? .unknown

        var draft = LabReportDraft()
        draft.id = reportID
        draft.laboratoryNameText = edit.laboratoryNameText
            .resolve(existing.string("laboratory_name_text"))
        draft.reportedAt = edit.reportedAt.resolve(currentReportedAt, cleared: .unknown)
        draft.headerText = edit.headerText.resolve(existing.string("header_text"))
        draft.entryOrigin = edit.actor
        // Ordering is not carried by a human edit; the held marker survives.
        draft.sourceOrdering = SourceOrdering.from(
            kind: existing.string("source_ordering_kind"),
            value: existing.string("source_ordering_text"))

        let stored = LabStore.reportFingerprint(
            laboratoryName: existing.string("laboratory_name_text"),
            reportedAt: existing.string("reported_at"),
            precision: existing.string("reported_precision") ?? TimePrecision.unknown.rawValue,
            offsetMinutes: existing.int("reported_tz_offset_minutes").map(Int.init),
            zoneID: existing.string("reported_tz_id"),
            header: existing.string("header_text"))
        let incoming = LabStore.reportFingerprint(
            laboratoryName: draft.laboratoryNameText,
            reportedAt: draft.reportedAt.isKnown ? draft.reportedAt.text : nil,
            precision: draft.reportedAt.precision.rawValue,
            offsetMinutes: draft.reportedAt.zone.offsetMinutes,
            zoneID: draft.reportedAt.zone.identifier,
            header: draft.headerText)
        if stored == incoming { return .unchanged(reportID: reportID) }

        return try supersedeReport(reportID: reportID, existing: existing,
                                   storedFingerprint: stored, draft: draft,
                                   kind: "superseded")
    }

    /// Corrects a result, addressed by Almanac's observation id.
    ///
    /// The observation keeps its identity; the correction is a new attributable
    /// revision. Nothing about this needs an external observation id, which is
    /// what makes a manually entered result editable at all.
    @discardableResult
    public func reviseObservation(id observationID: String,
                                  content rawContent: LabRevisionContent) throws -> LabRecordOutcome {
        let content = try rawContent.validated()
        guard try db.query("SELECT id FROM lab_observation WHERE id = ?;",
                           [.text(observationID)]).first != nil else {
            throw LabError.observationNotFound(observationID)
        }
        return try db.transaction {
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
    }

    /// Corrects an observation's **metadata** — what it measured, in what, and
    /// when — leaving the measured value alone.
    ///
    /// This exists because `record` compares result content, so a correction
    /// that changed only the specimen or the collection date previously did
    /// nothing at all. Previous values move to
    /// `lab_observation_metadata_revision` with the actor, the reason and the
    /// list of fields touched.
    @discardableResult
    public func updateObservationMetadata(
        id observationID: String, _ edit: LabObservationMetadataEdit
    ) throws -> LabMetadataOutcome {
        guard let existing = try db.query("""
            SELECT id, report_id, catalog_analyte_id, match_origin, match_confidence,
                   specimen_kind, specimen_text, collected_at, collected_precision,
                   collected_tz_offset_minutes, collected_tz_id
            FROM lab_observation WHERE id = ?;
            """, [.text(observationID)]).first else {
            throw LabError.observationNotFound(observationID)
        }
        guard edit.touchesAnything else { return .unchanged(observationID: observationID) }

        let oldReportID = existing.string("report_id")
        let oldAnalyteID = existing.string("catalog_analyte_id")
        let oldSpecimenKind = existing.string("specimen_kind")
            .flatMap(SpecimenKind.init(rawValue:)) ?? .unknown
        let oldSpecimenText = existing.string("specimen_text")
        let oldCollectedAt = PartialDateTime(
            storedText: existing.string("collected_at") ?? "",
            precision: TimePrecision(rawValue: existing.string("collected_precision") ?? "")
                ?? .unknown,
            zone: ZoneContext(
                offsetMinutes: existing.int("collected_tz_offset_minutes").map(Int.init),
                identifier: existing.string("collected_tz_id"))) ?? .unknown

        let newReportID = edit.reportID.resolve(oldReportID)
        let newAnalyteID = edit.catalogAnalyteID.resolve(oldAnalyteID)
        let newSpecimenKind = edit.specimenKind.resolve(oldSpecimenKind, cleared: .unknown)
        let newSpecimenText = edit.specimenText.resolve(oldSpecimenText)
        let newCollectedAt = edit.collectedAt.resolve(oldCollectedAt, cleared: .unknown)

        var changed: [String] = []
        if newReportID != oldReportID { changed.append("report_id") }
        if newAnalyteID != oldAnalyteID { changed.append("catalog_analyte_id") }
        if newSpecimenKind != oldSpecimenKind { changed.append("specimen_kind") }
        if newSpecimenText != oldSpecimenText { changed.append("specimen_text") }
        if newCollectedAt != oldCollectedAt { changed.append("collected_at") }
        guard !changed.isEmpty else { return .unchanged(observationID: observationID) }

        return try db.transaction {
            let number = Int(try db.query("""
                SELECT COALESCE(MAX(revision_number), 0) AS n
                FROM lab_observation_metadata_revision WHERE observation_id = ?;
                """, [.text(observationID)]).first?.int("n") ?? 0) + 1
            let revisionID = UUID().uuidString
            try db.run("""
            INSERT INTO lab_observation_metadata_revision
                (id, observation_id, revision_number, report_id, catalog_analyte_id,
                 match_origin, match_confidence, specimen_kind, specimen_text,
                 collected_at, collected_precision, collected_tz_offset_minutes,
                 collected_tz_id, changed_fields, actor, reason_text, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(revisionID), .text(observationID), .integer(Int64(number)),
                oldReportID.map { SQLValue.text($0) } ?? .null,
                oldAnalyteID.map { SQLValue.text($0) } ?? .null,
                existing.string("match_origin").map { SQLValue.text($0) } ?? .null,
                existing.string("match_confidence").map { SQLValue.text($0) } ?? .null,
                .text(oldSpecimenKind.rawValue),
                oldSpecimenText.map { SQLValue.text($0) } ?? .null,
                oldCollectedAt.isKnown ? .text(oldCollectedAt.text) : .null,
                .text(oldCollectedAt.precision.rawValue),
                oldCollectedAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                oldCollectedAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
                .text(changed.joined(separator: ",")), .text(edit.actor),
                edit.reasonText.map { SQLValue.text($0) } ?? .null, .text(nowText)
            ])
            try db.run("""
            UPDATE lab_observation SET
                report_id                   = ?,
                catalog_analyte_id          = ?,
                match_origin                = ?,
                match_confidence            = ?,
                specimen_kind               = ?,
                specimen_text               = ?,
                collected_at                = ?,
                collected_precision         = ?,
                collected_tz_offset_minutes = ?,
                collected_tz_id             = ?
            WHERE id = ?;
            """, [
                newReportID.map { SQLValue.text($0) } ?? .null,
                newAnalyteID.map { SQLValue.text($0) } ?? .null,
                // A mapping a person set is attributed to the person, and a
                // cleared mapping carries no origin at all.
                edit.catalogAnalyteID.isChange
                    ? (newAnalyteID == nil ? .null : .text("user"))
                    : (existing.string("match_origin").map { SQLValue.text($0) } ?? .null),
                edit.catalogAnalyteID.isChange
                    ? (newAnalyteID == nil ? .null : .text("user_assigned"))
                    : (existing.string("match_confidence").map { SQLValue.text($0) } ?? .null),
                .text(newSpecimenKind.rawValue),
                newSpecimenText.map { SQLValue.text($0) } ?? .null,
                newCollectedAt.isKnown ? .text(newCollectedAt.text) : .null,
                .text(newCollectedAt.precision.rawValue),
                newCollectedAt.zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                newCollectedAt.zone.identifier.map { SQLValue.text($0) } ?? .null,
                .text(observationID)
            ])
            return .updated(observationID: observationID, revisionID: revisionID,
                            revisionNumber: number, changedFields: changed)
        }
    }

    /// Previous metadata for an observation, oldest first.
    public func metadataRevisions(of observationID: String) throws -> [LabMetadataRevision] {
        try db.query("""
        SELECT id, revision_number, report_id, catalog_analyte_id, specimen_kind,
               specimen_text, collected_at, collected_precision, changed_fields,
               actor, reason_text, recorded_at
        FROM lab_observation_metadata_revision
        WHERE observation_id = ? ORDER BY revision_number;
        """, [.text(observationID)]).compactMap { row in
            guard let id = row.string("id"), let number = row.int("revision_number") else {
                return nil
            }
            return LabMetadataRevision(
                id: id, observationID: observationID, revisionNumber: Int(number),
                reportID: row.string("report_id"),
                catalogAnalyteID: row.string("catalog_analyte_id"),
                specimenKind: row.string("specimen_kind")
                    .flatMap(SpecimenKind.init(rawValue:)) ?? .unknown,
                specimenText: row.string("specimen_text"),
                collectedAtText: row.string("collected_at"),
                collectedPrecision: TimePrecision(rawValue: row.string("collected_precision") ?? "")
                    ?? .unknown,
                changedFields: (row.string("changed_fields") ?? "")
                    .split(separator: ",").map(String.init),
                actor: row.string("actor") ?? "unknown",
                reasonText: row.string("reason_text"),
                recordedAt: row.string("recorded_at") ?? "")
        }
    }

    // MARK: - Observations and revisions

    /// Find-or-create the observation, then append a revision unless identical
    /// content is already held.
    @discardableResult
    public func record(_ draft: LabObservationDraft,
                       content rawContent: LabRevisionContent) throws -> LabRecordOutcome {
        let content = try rawContent.validated()
        var observation = draft

        if observation.catalogAnalyteID == nil {
            switch try catalog.matchCandidates(sourceText: content.sourceAnalyteText) {
            case .unique(let match):
                observation.catalogAnalyteID = match.analyteID
                observation.matchOrigin = match.origin
                observation.matchConfidence = match.confidence
            case .ambiguous(let candidates):
                // Left unmatched on purpose. Recording *why* it is unmatched
                // means the interface can offer the candidates instead of
                // showing an unexplained gap.
                observation.matchOrigin = "ambiguous"
                observation.matchConfidence = candidates.map(\.analyteID).joined(separator: " ")
            case .none:
                break
            }
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
                 collected_tz_id, specimen_kind, specimen_text, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                .text(observation.specimenKind.rawValue),
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

    public func specimenKind(of observationID: String) throws -> SpecimenKind {
        try db.query("SELECT specimen_kind FROM lab_observation WHERE id = ?;",
                     [.text(observationID)]).first?.string("specimen_kind")
            .flatMap(SpecimenKind.init(rawValue:)) ?? .unknown
    }

    public func observationIDs(analyteID: String, specimenKind: SpecimenKind? = nil) throws -> [String] {
        if let specimenKind {
            return try db.query("""
            SELECT id FROM lab_observation
            WHERE catalog_analyte_id = ? AND specimen_kind = ? ORDER BY created_at;
            """, [.text(analyteID), .text(specimenKind.rawValue)]).compactMap { $0.string("id") }
        }
        return try db.query("""
        SELECT id FROM lab_observation WHERE catalog_analyte_id = ? ORDER BY created_at;
        """, [.text(analyteID)]).compactMap { $0.string("id") }
    }

    /// Observations of one analyte, split by specimen so that nothing which
    /// must not be merged can be merged by accident.
    ///
    /// A blood result and a urine result for the same analyte land in different
    /// groups, and an observation whose specimen was never stated lands in the
    /// `.unknown` group rather than being folded into a stated one.
    public func observationsBySpecimen(analyteID: String) throws -> [SpecimenKind: [String]] {
        let rows = try db.query("""
        SELECT id, specimen_kind FROM lab_observation
        WHERE catalog_analyte_id = ? ORDER BY created_at;
        """, [.text(analyteID)])
        var groups: [SpecimenKind: [String]] = [:]
        for row in rows {
            guard let id = row.string("id") else { continue }
            let kind = row.string("specimen_kind").flatMap(SpecimenKind.init(rawValue:)) ?? .unknown
            groups[kind, default: []].append(id)
        }
        return groups
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

        guard let range = DateRange(from: from, to: to) else { return [] }

        var entries: [TimelineEntry] = []
        for row in rows {
            guard let observationID = row.string("obs_id") else { continue }
            let (occurrence, basis) = LabStore.placement(row)
            // Span-based, not prefix-based. A record placed at "2019-03" covers
            // the whole of March, so a range starting on the 15th still
            // overlaps it and the record is returned as `.potential` rather
            // than vanishing because its span start sorts before the boundary.
            guard let fit = occurrence.fit(in: range) else { continue }

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
                lifecycle: row.string("lifecycle"), rangeFit: fit))
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
