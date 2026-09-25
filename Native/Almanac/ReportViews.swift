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
                        Text(report.laboratoryNameText ?? "Laboratory report").font(.headline)
                        Text("\(dateLabel(report.reportedAt)) · \(report.resultCount) results")
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
        }
        .navigationTitle("Laboratory")
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
            .navigationTitle(report == nil ? "New report" : "Edit report")
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
            guard let store = model.store else { throw EditorFailure(message: "The database is unavailable.") }
            let value = try editedDate(text: date, precision: precision, original: report?.reportedAt ?? .unknown)
            if let report {
                guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EditorFailure(message: "Enter a reason for the correction.")
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
                    LabeledContent("Laboratory", value: report.laboratoryNameText ?? "Unknown")
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
                            value: "\(outcome.reportsCreated) created · \(outcome.reportsUnchanged) unchanged · \(outcome.reportConflicts) held")
                        LabeledContent("Observations",
                            value: "\(outcome.observationsCreated) added · \(outcome.observationsUnchanged) unchanged")
                        if outcome.invalidRowCount > 0 {
                            Text("\(outcome.invalidRowCount) rows skipped — see the source file").foregroundStyle(.secondary)
                        }
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
            guard let store = model.store else { throw EditorFailure(message: "The database is unavailable.") }
            outcome = try LabReportCSVImport.importReports(csv: csv, into: store)
            model.changed()
        } catch { self.error = String(describing: error) }
    }
}
