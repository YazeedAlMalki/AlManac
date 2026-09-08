import SwiftUI
import AlmanacCore

@MainActor
struct ResultSummary: View {
    let result: LabResultView
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.displayName).font(.headline)
            ContentDetails(content: result.content)
            Text("Collected: \(dateLabel(result.collectedAt))")
            Text("Specimen: \(result.specimenText ?? readable(result.specimenKind.rawValue))")
            if result.isUnmatched { Label("Unmatched test", systemImage: "questionmark.circle") }
        }.font(.subheadline)
    }
}

/// Structured value and source transcription are deliberately separate. A
/// corrected numeric value must not be hidden by an older sourceValueText.
@MainActor
struct ContentDetails: View {
    let content: LabRevisionContent
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.monospacedDigit()).foregroundStyle(.primary)
            Text("Original unit: \(content.unitText ?? "Not stated")")
            Text("Reference: \(content.rangeText ?? "Not stated")")
            if content.rangeLow != nil || content.rangeHigh != nil {
                Text("Bounds: \(content.rangeLow.map { String($0) } ?? "Not stated") – \(content.rangeHigh.map { String($0) } ?? "Not stated")")
            }
            if let unit = content.rangeUnitText { Text("Reference unit: \(unit)") }
            if let name = content.sourceAnalyteText { Text("Original test: \(name)") }
            if let source = content.sourceValueText { Text("Original result: \(source)") }
            if let flag = content.flagText { Text("Reported flag: \(flag)") }
            Text("Derivation: \(readable(content.derivation.rawValue))")
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
    private var value: String {
        let raw: String
        switch content.valueType {
        case .quantitative, .semiQuantitative:
            raw = content.numericValue.map { String($0) } ?? "No structured value"
        case .qualitativeCoded, .ordinal: raw = content.codedValue ?? "No structured value"
        case .text: raw = content.textValue ?? "No structured value"
        case .ratio:
            raw = "\(content.ratioNumerator.map { String($0) } ?? "?"):\(content.ratioDenominator.map { String($0) } ?? "?")"
        case .titer:
            raw = "\(content.titerNumerator.map { String($0) } ?? "?"):\(content.titerDenominator.map { String($0) } ?? "?")"
        case .absent: raw = "Missing: \(readable((content.missingReason ?? .unknown).rawValue))"
        }
        return [content.comparator.symbol, raw, content.unitText].compactMap { $0 }.joined(separator: " ")
    }
}

@MainActor
struct MeasurementHistoryView: View {
    @ObservedObject var model: LaboratoryModel
    let analyteID: String
    let title: String
    @State private var measurements: [LabResultView] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("Each entry is a separate measurement. Corrections are available in its revision history.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(measurements, id: \.observationID) { result in
                Section {
                    ResultSummary(result: result)
                    if let reportID = result.reportID {
                        NavigationLink("Open source report") { ReportDetailView(model: model, reportID: reportID) }
                    } else { Text("No source report linked").foregroundStyle(.secondary) }
                    NavigationLink("Revision history") {
                        RevisionHistoryView(model: model, observationID: result.observationID, title: title)
                    }
                }
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { reload() }.onChange(of: model.generation) { _, _ in reload() }
        .editorError($error)
    }
    private func reload() {
        do { measurements = try model.store?.measurements(analyteID: analyteID) ?? [] }
        catch { self.error = String(describing: error) }
    }
}

@MainActor
struct RevisionHistoryView: View {
    @ObservedObject var model: LaboratoryModel
    let observationID: String
    let title: String
    @State private var revisions: [LabRevision] = []
    @State private var metadata: [LabMetadataRevision] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text(title).font(.headline)
                Text("Changes to one measurement. These are not new measurements.")
                    .foregroundStyle(.secondary)
            }
            ForEach(revisions, id: \.id) { revision in
                Section("Revision \(revision.revisionNumber)\(revision.isCurrent ? " · Current" : "")") {
                    ContentDetails(content: revision.content)
                    Text("Recorded: \(revision.recordedAt)")
                    Text("By: \(revision.content.actor)")
                    Text("Origin: \(readable(revision.content.contentOrigin.rawValue))")
                    Text("Reason: \(revision.content.reasonText ?? "Not stated")")
                    if let note = revision.content.commentText { Text("Notes: \(note)") }
                }
            }
            ForEach(metadata, id: \.id) { edit in
                Section("Metadata correction \(edit.revisionNumber)") {
                    Text("Changed: \(edit.changedFields.map(readable).joined(separator: ", "))")
                    Text("Previous collection date: \(edit.collectedAtText ?? "Unknown")")
                    Text("Previous specimen: \(edit.specimenText ?? readable(edit.specimenKind.rawValue))")
                    Text("Previous test: \(edit.catalogAnalyteID ?? "Unmatched")")
                    Text("Previous report: \(edit.reportID ?? "None")")
                    Text("By: \(edit.actor) · \(edit.recordedAt)")
                    Text("Reason: \(edit.reasonText ?? "Not stated")")
                }
            }
        }
        .navigationTitle("Revision history").navigationBarTitleDisplayMode(.inline)
        .task { reload() }.onChange(of: model.generation) { _, _ in reload() }
        .editorError($error)
    }
    private func reload() {
        do {
            revisions = try model.store?.revisions(of: observationID) ?? []
            metadata = try model.store?.metadataRevisions(of: observationID) ?? []
        } catch { self.error = String(describing: error) }
    }
}

@MainActor
struct ReportConflictView: View {
    @ObservedObject var model: LaboratoryModel
    let reportID: String
    @State private var proposals: [LabReportRevision] = []
    @State private var current: LabReportSummary?
    @State private var reason = ""
    @State private var error: String?
    var body: some View {
        List {
            Section("Current report") {
                Text(current?.laboratoryNameText ?? "Laboratory unknown")
                Text(dateLabel(current?.reportedAt ?? .unknown))
            }
            Section("Resolution") {
                TextField("Reason for your decision", text: $reason, axis: .vertical)
                Text("Accept replaces the report metadata with the incoming version. Existing results remain attached.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(proposals, id: \.id) { proposal in
                Section("Incoming version") {
                    Text(proposal.laboratoryNameText ?? "Laboratory unknown")
                    Text(proposal.reportedAtText ?? "Date unknown")
                    if let header = proposal.headerText { Text(header) }
                    Text("Source ordering: \(ordering(proposal.sourceOrdering))")
                    Text("Received: \(proposal.supersededAt)")
                    Button("Accept incoming version") { resolve(proposal, accept: true) }
                    Button("Reject incoming version", role: .destructive) { resolve(proposal, accept: false) }
                }
            }
            if proposals.isEmpty { Text("No unresolved conflicts").foregroundStyle(.secondary) }
        }
        .navigationTitle("Report review").navigationBarTitleDisplayMode(.inline)
        .task { reload() }.editorError($error)
    }
    private func ordering(_ value: SourceOrdering) -> String {
        switch value {
        case .unavailable: return "Not stated"
        case .sequence(let n): return "Version \(n)"
        case .issuedAt(let text): return text
        }
    }
    private func reload() {
        do {
            proposals = try model.store?.reportRevisions(of: reportID).filter { $0.kind == "conflict" } ?? []
            current = try model.store?.report(id: reportID)
        } catch { self.error = String(describing: error) }
    }
    private func resolve(_ proposal: LabReportRevision, accept: Bool) {
        do {
            guard let store = model.store else { throw EditorFailure(message: "The database is unavailable.") }
            try store.resolveReportConflict(id: proposal.id, accept: accept, actor: "user", reason: reason)
            reason = ""; model.changed(); reload()
        } catch { self.error = String(describing: error) }
    }
}
