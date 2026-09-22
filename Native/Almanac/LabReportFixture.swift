import Foundation
import AlmanacCore

/// DEBUG-only demo data: one conflicting report pair, so the report-review
/// screen (`ReportConflictView`) has something to show in a fresh install.
///
/// A laboratory reissue with a corrected header arrives without any ordering
/// marker, so the store holds it for a person to review instead of applying
/// it — the exact path a real CSV import of an amended report takes.
@MainActor
enum LabReportFixture {

    /// Seeds once, and only for an app that has no reports yet. The seed is
    /// also idempotent at the store level: the amended draft resolves to
    /// `.conflict` the first time and `replayIgnored` afterwards, so repeated
    /// launches never duplicate or reopen the proposal.
    static func seedIfNeeded(into store: LabStore) throws {
        guard try store.reports(limit: 1).isEmpty else { return }

        var baseline = LabReportDraft()
        baseline.sourceSystem = "almanac.dev-fixture"
        baseline.sourceReportID = "annual-2026-09"
        baseline.laboratoryNameText = "HealthCheck Laboratory"
        baseline.reportedAt = PartialDateTime(storedText: "2026-09-08", precision: .day,
                                              zone: ZoneContext(TimeZone.current)) ?? .unknown
        baseline.headerText = "Initial issue"
        baseline.entryOrigin = "dev_fixture"
        _ = try store.upsertReport(baseline)

        var amended = baseline
        amended.headerText = "Amended — corrected header text"
        _ = try store.upsertReport(amended)
    }
}