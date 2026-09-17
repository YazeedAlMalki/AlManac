import Foundation

/// A report as a list row.
public struct LabReportSummary: Sendable, Hashable {
    public let id: String
    public let laboratoryNameText: String?
    public let reportedAt: PartialDateTime
    public let recordedAt: String
    public let resultCount: Int
    /// True when a version arrived that could not be ranked against this one
    /// and was held instead of applied. A person has to resolve it.
    public let hasUnresolvedConflict: Bool
}

/// One measurement as it currently stands: the observation plus its current
/// revision, resolved for display.
public struct LabResultView: Sendable {
    public let observationID: String
    public let reportID: String?
    public let catalogAnalyteID: String?
    /// The catalog's canonical name where the test is mapped, otherwise the
    /// source's own words. Never blank, never a guess.
    public let displayName: String
    public let isUnmatched: Bool
    /// Populated when matching found several candidates and therefore refused
    /// to choose. These are what a person picks from.
    public let ambiguousCandidates: [String]
    public let specimenKind: SpecimenKind
    public let specimenText: String?
    public let collectedAt: PartialDateTime
    public let currentRevisionID: String
    public let revisionNumber: Int
    public let content: LabRevisionContent
    public var value: ValuePresentation { content.presentation }
}

/// A catalog hit for as-you-type search.
public struct CatalogSuggestion: Sendable, Hashable {
    public let analyteID: String
    public let canonicalName: String
    /// The text that actually matched — the canonical name, an abbreviation,
    /// or an Arabic alias. Shown so a person can see why a row is offered.
    public let matchedText: String
    public let matchedCanonicalName: Bool
}

extension LabCatalogStore {

    /// Canonical names and aliases, matched as a prefix, for a pick list.
    ///
    /// Distinct from `matchCandidates`, which is exact and is what an import
    /// uses. A person typing wants the near misses; an importer must not have
    /// them.
    public func suggest(prefix: String, limit: Int = 20) throws -> [CatalogSuggestion] {
        let folded = TextFold.fold(prefix)
        guard !folded.isEmpty else { return [] }
        let escaped = folded
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")

        let rows = try db.query("""
        SELECT al.analyte_id, al.alias_text, an.canonical_name
        FROM lab_catalog_alias al
        JOIN lab_catalog_analyte an ON an.id = al.analyte_id
        WHERE al.alias_fold LIKE ? ESCAPE '\\'
        ORDER BY an.canonical_name, al.analyte_id, al.alias_text
        LIMIT ?;
        """, [.text(escaped + "%"), .integer(Int64(limit * 8))])

        // One row per analyte, preferring the canonical name as the reason.
        var best: [String: CatalogSuggestion] = [:]
        var order: [String] = []
        for row in rows {
            guard let id = row.string("analyte_id"),
                  let alias = row.string("alias_text"),
                  let canonical = row.string("canonical_name") else { continue }
            let suggestion = CatalogSuggestion(
                analyteID: id, canonicalName: canonical, matchedText: alias,
                matchedCanonicalName: alias == canonical)
            if let held = best[id] {
                if suggestion.matchedCanonicalName && !held.matchedCanonicalName {
                    best[id] = suggestion
                }
            } else {
                best[id] = suggestion
                order.append(id)
            }
        }
        return order.prefix(limit).compactMap { best[$0] }
    }
}

extension LabStore {

    // MARK: - Reports

    /// A page of reports, newest first.
    ///
    /// Ordering is total: placement time, then recording time, then id. Without
    /// the id tie-break, two reports sharing a date could swap places between
    /// pages and a row would be shown twice or skipped.
    public func reports(limit: Int = 50, offset: Int = 0) throws -> [LabReportSummary] {
        try db.query("""
        SELECT r.id, r.laboratory_name_text, r.reported_at, r.reported_precision,
               r.reported_tz_offset_minutes, r.reported_tz_id, r.recorded_at,
               (SELECT COUNT(*) FROM lab_observation o WHERE o.report_id = r.id) AS result_count,
               (SELECT COUNT(*) FROM lab_report_revision v
                 WHERE v.report_id = r.id AND v.kind = 'conflict') AS conflict_count
        FROM lab_report r
        ORDER BY COALESCE(r.reported_at, r.recorded_at) DESC, r.recorded_at DESC, r.id ASC
        LIMIT ? OFFSET ?;
        """, [.integer(Int64(limit)), .integer(Int64(offset))])
            .compactMap(LabStore.summary(from:))
    }

    public func report(id reportID: String) throws -> LabReportSummary? {
        try db.query("""
        SELECT r.id, r.laboratory_name_text, r.reported_at, r.reported_precision,
               r.reported_tz_offset_minutes, r.reported_tz_id, r.recorded_at,
               (SELECT COUNT(*) FROM lab_observation o WHERE o.report_id = r.id) AS result_count,
               (SELECT COUNT(*) FROM lab_report_revision v
                 WHERE v.report_id = r.id AND v.kind = 'conflict') AS conflict_count
        FROM lab_report r WHERE r.id = ?;
        """, [.text(reportID)]).compactMap(LabStore.summary(from:)).first
    }

    static func summary(from row: Row) -> LabReportSummary? {
        guard let id = row.string("id") else { return nil }
        let reportedAt = PartialDateTime(
            storedText: row.string("reported_at") ?? "",
            precision: TimePrecision(rawValue: row.string("reported_precision") ?? "") ?? .unknown,
            zone: ZoneContext(offsetMinutes: row.int("reported_tz_offset_minutes").map(Int.init),
                              identifier: row.string("reported_tz_id"))) ?? .unknown
        return LabReportSummary(
            id: id,
            laboratoryNameText: row.string("laboratory_name_text"),
            reportedAt: reportedAt,
            recordedAt: row.string("recorded_at") ?? "",
            resultCount: Int(row.int("result_count") ?? 0),
            hasUnresolvedConflict: (row.int("conflict_count") ?? 0) > 0)
    }

    // MARK: - Results

    private static let resultSelect = """
    SELECT o.id AS obs_id, o.report_id, o.catalog_analyte_id, o.match_origin,
           o.match_confidence, o.specimen_kind, o.specimen_text,
           o.collected_at, o.collected_precision, o.collected_tz_offset_minutes,
           o.collected_tz_id, o.created_at, o.repeat_index,
           an.canonical_name,
           rev.id AS rev_id, rev.revision_number, rev.lifecycle, rev.value_type,
           rev.comparator, rev.derivation, rev.missing_reason, rev.numeric_value,
           rev.coded_value, rev.text_value, rev.ratio_numerator, rev.ratio_denominator,
           rev.titer_numerator, rev.titer_denominator, rev.unit_text, rev.lod_text,
           rev.loq_text, rev.range_text, rev.range_low, rev.range_high,
           rev.range_unit_text, rev.flag_text, rev.comment_text, rev.method_text,
           rev.source_analyte_text, rev.source_value_text, rev.content_origin,
           rev.actor, rev.reason_text, rev.source_revision_id
    FROM lab_observation o
    JOIN lab_observation_revision rev
         ON rev.observation_id = o.id AND rev.is_current = 1
    LEFT JOIN lab_catalog_analyte an ON an.id = o.catalog_analyte_id
    """

    /// The current results of one report, in the order they were recorded.
    public func currentResults(inReport reportID: String) throws -> [LabResultView] {
        try db.query(LabStore.resultSelect + """
         WHERE o.report_id = ?
         ORDER BY o.repeat_index, o.created_at, o.id;
        """, [.text(reportID)]).compactMap(LabStore.resultView(from:))
    }

    /// **Longitudinal history** — every measurement of one test, across every
    /// report, oldest first.
    ///
    /// Not to be confused with `revisions(of:)`, which is **revision history**:
    /// the corrections made to *one* measurement. Two ferritin results a year
    /// apart are two measurements with one revision each; one ferritin result
    /// the laboratory later amended is one measurement with two revisions. A UI
    /// that mixes them shows a correction as though the value had changed in
    /// the body.
    ///
    /// `specimenKind` filters to one material, since a blood result and a urine
    /// result are not one series (`SpecimenKind.sameSpecimen`).
    public func measurements(analyteID: String,
                             specimenKind: SpecimenKind? = nil) throws -> [LabResultView] {
        let ordering = """
         ORDER BY COALESCE(o.collected_at, o.created_at) ASC, o.repeat_index, o.id;
        """
        if let specimenKind {
            return try db.query(LabStore.resultSelect + """
             WHERE o.catalog_analyte_id = ? AND o.specimen_kind = ?
            """ + ordering, [.text(analyteID), .text(specimenKind.rawValue)])
                .compactMap(LabStore.resultView(from:))
        }
        return try db.query(LabStore.resultSelect + """
         WHERE o.catalog_analyte_id = ?
        """ + ordering, [.text(analyteID)]).compactMap(LabStore.resultView(from:))
    }

    static func resultView(from row: Row) -> LabResultView? {
        guard let observationID = row.string("obs_id"),
              let revisionID = row.string("rev_id"),
              let revisionNumber = row.int("revision_number") else { return nil }

        var content = LabRevisionContent()
        content.lifecycle = LabLifecycle(rawValue: row.string("lifecycle") ?? "") ?? .unknown
        content.valueType = LabValueType(rawValue: row.string("value_type") ?? "") ?? .absent
        content.comparator = LabComparator(rawValue: row.string("comparator") ?? "") ?? .none
        content.derivation = LabDerivation(rawValue: row.string("derivation") ?? "") ?? .unknown
        content.missingReason = row.string("missing_reason").flatMap(LabMissingReason.init(rawValue:))
        content.numericValue = row.double("numeric_value")
        content.codedValue = row.string("coded_value")
        content.textValue = row.string("text_value")
        content.ratioNumerator = row.double("ratio_numerator")
        content.ratioDenominator = row.double("ratio_denominator")
        content.titerNumerator = row.int("titer_numerator").map(Int.init)
        content.titerDenominator = row.int("titer_denominator").map(Int.init)
        content.unitText = row.string("unit_text")
        content.lodText = row.string("lod_text")
        content.loqText = row.string("loq_text")
        content.rangeText = row.string("range_text")
        content.rangeLow = row.double("range_low")
        content.rangeHigh = row.double("range_high")
        content.rangeUnitText = row.string("range_unit_text")
        content.flagText = row.string("flag_text")
        content.commentText = row.string("comment_text")
        content.methodText = row.string("method_text")
        content.sourceAnalyteText = row.string("source_analyte_text")
        content.sourceValueText = row.string("source_value_text")
        content.contentOrigin = LabContentOrigin(rawValue: row.string("content_origin") ?? "")
            ?? .userTranscription
        content.actor = row.string("actor") ?? "unknown"
        content.reasonText = row.string("reason_text")
        content.sourceRevisionID = row.string("source_revision_id")

        let unmatched = row.isNull("catalog_analyte_id")
        let ambiguous = row.string("match_origin") == "ambiguous"
            ? (row.string("match_confidence") ?? "").split(separator: " ").map(String.init)
            : []
        let collectedAt = PartialDateTime(
            storedText: row.string("collected_at") ?? "",
            precision: TimePrecision(rawValue: row.string("collected_precision") ?? "") ?? .unknown,
            zone: ZoneContext(offsetMinutes: row.int("collected_tz_offset_minutes").map(Int.init),
                              identifier: row.string("collected_tz_id"))) ?? .unknown

        return LabResultView(
            observationID: observationID,
            reportID: row.string("report_id"),
            catalogAnalyteID: row.string("catalog_analyte_id"),
            displayName: row.string("canonical_name")
                ?? content.sourceAnalyteText
                ?? "(test not named)",
            isUnmatched: unmatched,
            ambiguousCandidates: ambiguous,
            specimenKind: row.string("specimen_kind").flatMap(SpecimenKind.init(rawValue:))
                ?? .unknown,
            specimenText: row.string("specimen_text"),
            collectedAt: collectedAt,
            currentRevisionID: revisionID,
            revisionNumber: Int(revisionNumber),
            content: content)
    }
}
