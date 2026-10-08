import SwiftUI
import AlmanacCore

@MainActor
struct ReportListView: View {
    @ObservedObject var model: LaboratoryModel
    @State private var reports: [LabReportSummary] = []
    @State private var create = false
    @State private var importing = false
    @State private var error: String?
    @State private var limit = 50

    var body: some View {
        List {
            if reports.isEmpty {
                ContentUnavailableView("Your laboratory reports", systemImage: "cross.case",
                    description: Text("Create a report, then record its results exactly as reported."))
                Button("Create your first report") { create = true }
            }
            ForEach(reports, id: \.id) { report in
                NavigationLink {
                    ReportDetailView(model: model, reportID: report.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.laboratoryNameText ?? String(localized: "Laboratory report")).font(.headline)
                        Text("\(dateLabel(report.reportedAt)), \(report.resultCount) results")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if report.hasUnresolvedConflict {
                            Label("Needs review", systemImage: "exclamationmark.bubble").font(.caption)
                        }
                    }.padding(.vertical, 4)
                }
            }
            if reports.count == limit {
                Button("Load more reports") { limit += 50; reload() }
            }
            // A row in the list rather than a `safeAreaInset`: that inset is
            // swallowed by a `NavigationStack` on this screen's own host
            // (`AlmanacApp`'s bar comment explains the trap), and a control
            // nobody can reach is worse than one more row.
            Section {
                NavigationLink {
                    LabImportHistoryView(model: model)
                } label: {
                    Label("Import history", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("Every import you have pasted is recorded here, with how many rows matched the catalog.")
            }
        }
        .navigationTitle("Laboratory")
        .almanacModuleSurface()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Import CSV", systemImage: "square.and.arrow.down") { importing = true }
                Button("New report", systemImage: "plus") { create = true }
            }
        }
        .sheet(isPresented: $create) { ReportEditor(model: model, report: nil) }
        .sheet(isPresented: $importing) { CSVImportView(model: model) }
        .task { reload() }
        .onChange(of: model.generation) { _, _ in reload() }
        .editorError($error)
    }

    private func reload() {
        do { reports = try model.store?.reports(limit: limit) ?? [] }
        catch { self.error = String(describing: error) }
    }
}

@MainActor
struct ReportEditor: View {
    @ObservedObject var model: LaboratoryModel
    let report: LabReportSummary?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var date: String
    @State private var precision: TimePrecision
    @State private var reason = ""
    @State private var error: String?

    init(model: LaboratoryModel, report: LabReportSummary?) {
        self.model = model; self.report = report
        _name = State(initialValue: report?.laboratoryNameText ?? "")
        _date = State(initialValue: report?.reportedAt.text ?? "")
        _precision = State(initialValue: report?.reportedAt.precision ?? .unknown)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Laboratory") { TextField("Name, if known", text: $name) }
                Section("Report date") { PartialDateFields(text: $date, precision: $precision) }
                if report != nil {
                    Section("Correction") { TextField("Reason for this change", text: $reason, axis: .vertical) }
                }
            }
            .navigationTitle(report == nil ? String(localized: "New report") : String(localized: "Edit report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .editorError($error)
        }
    }
    private func save() {
        do {
            guard let store = model.store else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
            let value = try editedDate(text: date, precision: precision, original: report?.reportedAt ?? .unknown)
            if let report {
                guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EditorFailure(message: String(localized: "Enter a reason for the correction."))
                }
                var edit = LabReportEdit()
                edit.laboratoryNameText = name.isEmpty ? .clear : .set(name)
                edit.reportedAt = .set(value)
                edit.reasonText = reason
                _ = try store.updateReport(id: report.id, edit)
            } else {
                var draft = LabReportDraft()
                draft.laboratoryNameText = optionalText(name); draft.reportedAt = value
                _ = try store.saveReport(draft)
            }
            model.changed(); dismiss()
        } catch { self.error = String(describing: error) }
    }
}

@MainActor
struct ReportDetailView: View {
    @ObservedObject var model: LaboratoryModel
    let reportID: String
    @State private var report: LabReportSummary?
    @State private var results: [LabResultView] = []
    @State private var adding = false
    @State private var editingReport = false
    @State private var editingResult: LabResultView?
    @State private var error: String?

    var body: some View {
        List {
            if let report {
                Section {
                    LabeledContent("Laboratory", value: report.laboratoryNameText ?? String(localized: "Unknown"))
                    LabeledContent("Report date", value: dateLabel(report.reportedAt))
                    Button("Edit report") { editingReport = true }
                    if report.hasUnresolvedConflict {
                        NavigationLink("Review conflicting report versions") {
                            ReportConflictView(model: model, reportID: reportID)
                        }
                    }
                }
            }
            Section("Results") {
                if results.isEmpty { Text("No results yet. Add a test from this report.").foregroundStyle(.secondary) }
                ForEach(results, id: \.observationID) { result in
                    VStack(alignment: .leading, spacing: 10) {
                        ResultSummary(result: result)
                        Button("Edit result") { editingResult = result }
                        if let analyte = result.catalogAnalyteID {
                            NavigationLink("Test history") {
                                MeasurementHistoryView(model: model, analyteID: analyte, title: result.displayName)
                            }
                        }
                        NavigationLink("Revision history") {
                            RevisionHistoryView(model: model, observationID: result.observationID, title: result.displayName)
                        }
                    }.padding(.vertical, 5)
                }
                Button("Add result", systemImage: "plus") { adding = true }
            }
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { ResultEditor(model: model, reportID: reportID, result: nil) }
        .sheet(isPresented: $editingReport) {
            if let report { ReportEditor(model: model, report: report) }
        }
        .sheet(isPresented: Binding(get: { editingResult != nil }, set: { if !$0 { editingResult = nil } })) {
            if let result = editingResult { ResultEditor(model: model, reportID: reportID, result: result) }
        }
        .task { reload() }
        .onChange(of: model.generation) { _, _ in reload() }
        .editorError($error)
    }
    private func reload() {
        do {
            report = try model.store?.report(id: reportID)
            results = try model.store?.currentResults(inReport: reportID) ?? []
        } catch { self.error = String(describing: error) }
    }
}

/// Paste-in CSV import for laboratory reports. The import runs through the
/// same `upsertReport` / `record` seams as manual entry, so re-imports are
/// fingerprint-idempotent and unranked changes are held as conflicts for the
/// review screen rather than silently applied.
///
/// It calls the *recording* overload of `importReports`, so every import is
/// written down as an `import_job` and can be read back from the import history.
/// The plain overload still exists and is what the parser tests use; this view
/// deliberately does not have a second path that forgets to record.
@MainActor
struct CSVImportView: View {
    @ObservedObject var model: LaboratoryModel
    @Environment(\.dismiss) private var dismiss
    @State private var csv = ""
    @State private var outcome: LabCSVImportResult?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Columns (no header row)") {
                    Text("source_report_id, report_date, laboratory_name, header_text, test_name, value, unit, range, flag, comment, source_observation_id")
                        .font(.caption)
                    Text("Rows sharing a source_report_id form one report. Values, units, ranges and flags are stored verbatim; blank dates stay unknown; non-numeric values stay text; unranked re-imports are held for review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("CSV") {
                    TextEditor(text: $csv)
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let outcome {
                    Section("Import result") {
                        LabeledContent("Reports",
                            value: String(localized: "\(outcome.reportsCreated) created · \(outcome.reportsUnchanged) unchanged · \(outcome.reportConflicts) held"))
                        LabeledContent("Observations",
                            value: String(localized: "\(outcome.observationsCreated) added · \(outcome.observationsUnchanged) unchanged"))
                        if outcome.invalidRowCount > 0 {
                            Text("\(outcome.invalidRowCount) rows skipped — see the source file").foregroundStyle(.secondary)
                        }
                        // What the import *did* is known immediately; what it
                        // *matched* is not, because that depends on the catalog
                        // as it stands when the question is asked. Saying so is
                        // better than showing a count that will change later
                        // with no explanation.
                        Text("Saved to import history. Whether each test name matched the catalog is worked out next time Almanac opens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import lab CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import", action: importCSV) }
            }
            .editorError($error)
        }
    }

    private func importCSV() {
        do {
            guard let store = model.store else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
            guard let jobs = model.importJobs else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
            outcome = try LabReportCSVImport.importReports(csv: csv, into: store, recording: jobs)
            model.changed()
        } catch { self.error = String(describing: error) }
    }
}

/// Every import that has run, newest first, and what each one came to.
///
/// This is the answer to "did I lose data", and it only exists because an
/// import that half-failed three weeks ago would otherwise leave no trace. The
/// numbers shown are the reconciled view of the rows, not a tally frozen at
/// import time — so a row fixed by hand, or a test name the catalog learned
/// since, changes what this screen says.
@MainActor
struct LabImportHistoryView: View {
    let model: LaboratoryModel
    @State private var jobs: [LabImportJob] = []
    @State private var error: String?

    var body: some View {
        List {
            if jobs.isEmpty {
                ContentUnavailableView("No imports yet", systemImage: "square.and.arrow.down",
                    description: Text("Imports you paste into the laboratory screen are recorded here, with how many rows matched."))
            }
            ForEach(jobs) { job in
                LabImportJobRow(job: job)
            }
        }
        .navigationTitle("Import history")
        .almanacModuleSurface()
        .task { reload() }
        .onChange(of: model.generation) { _, _ in reload() }
        .editorError($error)
    }

    private func reload() {
        do { jobs = try model.importJobs?.jobs(limit: 50) ?? [] }
        catch { self.error = String(describing: error) }
    }
}

/// One import, as a person reads it: when, how it went, and whether anything
/// needs them.
private struct LabImportJobRow: View {
    let job: LabImportJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.sourceName ?? String(localized: "Pasted import"))
                    .font(.headline)
                Spacer()
                Text(job.startedAt.almanacFormatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reason = job.failureReason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(AlmanacPalette.critical)
            } else {
                AlmanacStatusMark(text: job.status.displayText, tone: job.status.tone)
                if job.rowsUsable > 0 {
                    Text("\(job.rowsMatched) of \(job.rowsUsable) rows matched the catalog"
                         + (job.rowsAmbiguous > 0 ? " · \(job.rowsAmbiguous) need choosing" : "")
                         + (job.rowsUnmatched > 0 ? " · \(job.rowsUnmatched) did not match" : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if job.observationsCreated + job.observationsUnchanged + job.observationsRevised > 0 {
                Text("\(job.observationsCreated) results added · \(job.observationsUnchanged) unchanged · \(job.observationsRevised) revised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if job.invalidRows > 0 {
                Text("\(job.invalidRows) rows were not laboratory lines and were skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(job.accessibilityDescription)
    }
}

extension LabImportStatus {
    /// The sentence a person reads. Written per case rather than derived from
    /// the raw value, because `rawValue` is a storage key and not English.
    var displayText: String {
        switch self {
        case .matched: return String(localized: "Every row matched")
        case .partial: return String(localized: "Some rows did not match")
        case .unmatched: return String(localized: "No rows matched")
        case .invalid: return String(localized: "No usable rows")
        case .conflicted: return String(localized: "Report details need review")
        case .failed: return String(localized: "The import did not finish")
        // Never shown as a problem: it is this app's own pending work, and a
        // person cannot act on it.
        case .unresolved: return String(localized: "Checking")
        }
    }

    var tone: AlmanacStatusTone {
        switch self {
        case .matched: return .good
        case .partial: return .warning
        case .unmatched, .invalid: return .warning
        case .conflicted, .failed: return .critical
        case .unresolved: return .neutral
        }
    }
}

extension LabImportJob {
    /// One sentence, read in place of the four rows of text above it. A status
    /// mark plus three counts is four separate announcements otherwise, and a
    /// screen reader user has to hold all four to learn that nothing was lost.
    var accessibilityDescription: String {
        let when = startedAt.almanacFormatted(date: .abbreviated, time: .shortened)
        if let reason = failureReason {
            return String(localized: "Import on \(when) did not finish. \(reason)")
        }
        guard rowsUsable > 0 else {
            return String(localized: "Import on \(when): \(status.displayText).")
        }
        var parts = [String(localized: "\(rowsMatched) of \(rowsUsable) rows matched the catalog")]
        if rowsAmbiguous > 0 { parts.append(String(localized: "\(rowsAmbiguous) need a choice from candidates")) }
        if rowsUnmatched > 0 { parts.append(String(localized: "\(rowsUnmatched) did not match")) }
        if invalidRows > 0 { parts.append(String(localized: "\(invalidRows) were not laboratory lines")) }
        return String(localized: "Import on \(when). ") + parts.joined(separator: ". ") + "."
    }
}
