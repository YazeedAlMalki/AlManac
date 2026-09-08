import SwiftUI
import AlmanacCore

@MainActor
struct ResultEditor: View {
    @ObservedObject var model: LaboratoryModel
    let reportID: String
    let result: LabResultView?
    @Environment(\.dismiss) private var dismiss
    @State private var content: LabRevisionContent
    @State private var analyteID: String?
    @State private var testName: String
    @State private var query = ""
    @State private var suggestions: [CatalogSuggestion] = []
    @State private var number: String
    @State private var numerator: String
    @State private var denominator: String
    @State private var low: String
    @State private var high: String
    @State private var specimen: SpecimenKind
    @State private var specimenText: String
    @State private var date: String
    @State private var precision: TimePrecision
    @State private var reason = ""
    @State private var error: String?

    init(model: LaboratoryModel, reportID: String, result: LabResultView?) {
        self.model = model; self.reportID = reportID; self.result = result
        var c = result?.content ?? LabRevisionContent()
        if result == nil { c.valueType = .quantitative }
        _content = State(initialValue: c)
        _analyteID = State(initialValue: result?.catalogAnalyteID)
        _testName = State(initialValue: result?.displayName ?? "")
        _number = State(initialValue: c.numericValue.map(String.init(describing:)) ?? "")
        _numerator = State(initialValue: c.titerNumerator.map(String.init) ?? c.ratioNumerator.map(String.init(describing:)) ?? "")
        _denominator = State(initialValue: c.titerDenominator.map(String.init) ?? c.ratioDenominator.map(String.init(describing:)) ?? "")
        _low = State(initialValue: c.rangeLow.map(String.init(describing:)) ?? "")
        _high = State(initialValue: c.rangeHigh.map(String.init(describing:)) ?? "")
        _specimen = State(initialValue: result?.specimenKind ?? .unknown)
        _specimenText = State(initialValue: result?.specimenText ?? "")
        _date = State(initialValue: result?.collectedAt.text ?? "")
        _precision = State(initialValue: result?.collectedAt.precision ?? .unknown)
    }

    var body: some View {
        NavigationStack {
            Form {
                testSection
                valueSection
                Section("Original laboratory text") {
                    TextField("Test name on report", text: text(\.sourceAnalyteText))
                    TextField("Result exactly as printed", text: text(\.sourceValueText), axis: .vertical)
                    TextField("Original unit (e.g. g/dL)", text: text(\.unitText))
                    Text("Source text is retained separately from the structured value above.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Laboratory reference interval") {
                    TextField("Range exactly as printed", text: text(\.rangeText), axis: .vertical)
                    TextField("Lower bound, if stated", text: $low)
                    TextField("Upper bound, if stated", text: $high)
                    TextField("Range unit, if stated", text: text(\.rangeUnitText))
                    TextField("Flag exactly as printed", text: text(\.flagText))
                }
                Section("Specimen") {
                    Picker("Type", selection: $specimen) {
                        ForEach(SpecimenKind.allCases, id: \.self) { Text(readable($0.rawValue)).tag($0) }
                    }
                    TextField("Specimen exactly as printed", text: $specimenText)
                }
                Section("Collection date") { PartialDateFields(text: $date, precision: $precision) }
                Section("Additional report details") {
                    Picker("Status", selection: $content.lifecycle) {
                        ForEach(LabLifecycle.allCases, id: \.self) { Text(readable($0.rawValue)).tag($0) }
                    }
                    Picker("How the value was produced", selection: $content.derivation) {
                        ForEach(LabDerivation.allCases, id: \.self) { Text(readable($0.rawValue)).tag($0) }
                    }
                    TextField("Method, if stated", text: text(\.methodText))
                    TextField("Detection limit, if stated", text: text(\.lodText))
                    TextField("Quantification limit, if stated", text: text(\.loqText))
                    TextField("Notes", text: text(\.commentText), axis: .vertical)
                }
                if result != nil {
                    Section("Correction") {
                        TextField("Reason for this correction", text: $reason, axis: .vertical)
                        Text("Saving retains the previous revision and records who changed it and when.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(result == nil ? "Add result" : "Edit result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .editorError($error)
        }
    }

    private var testSection: some View {
        Section("Test") {
            if !testName.isEmpty {
                LabeledContent(analyteID == nil ? "Unmatched test" : "Selected test", value: testName)
            }
            TextField("Search names or aliases", text: $query)
                .autocorrectionDisabled()
                .onChange(of: query) { _, value in
                    do { suggestions = try model.catalog?.suggest(prefix: value) ?? [] }
                    catch { self.error = String(describing: error) }
                }
            ForEach(suggestions, id: \.analyteID) { item in
                Button {
                    analyteID = item.analyteID; testName = item.canonicalName
                    query = ""; suggestions = []
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.canonicalName)
                        if !item.matchedCanonicalName { Text(item.matchedText).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if analyteID != nil {
                Button(result == nil ? "Clear selection" : "Remove catalog mapping") { analyteID = nil; testName = content.sourceAnalyteText ?? "" }
            }
            Text("If a test is not listed, enter its original name below. It can be mapped later.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var valueSection: some View {
        Section("Result") {
            Picker("Value type", selection: $content.valueType) {
                ForEach(LabValueType.allCases, id: \.self) { Text(readable($0.rawValue)).tag($0) }
            }
            Picker("Comparator", selection: $content.comparator) {
                ForEach(LabComparator.allCases, id: \.self) { Text($0.symbol ?? "None").tag($0) }
            }
            switch content.valueType {
            case .quantitative, .semiQuantitative:
                TextField("Value (e.g. 16.27)", text: $number)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            case .ordinal, .qualitativeCoded:
                TextField("Result (e.g. Negative)", text: text(\.codedValue))
            case .text:
                TextField("Descriptive result", text: text(\.textValue), axis: .vertical)
            case .ratio, .titer:
                TextField("Numerator", text: $numerator)
                TextField("Denominator", text: $denominator)
            case .absent:
                Picker("Reason", selection: Binding(
                    get: { content.missingReason ?? .unknown },
                    set: { content.missingReason = $0 }
                )) {
                    ForEach(LabMissingReason.allCases, id: \.self) { Text(readable($0.rawValue)).tag($0) }
                }
            }
        }
    }

    private func text(_ key: WritableKeyPath<LabRevisionContent, String?>) -> Binding<String> {
        Binding(get: { content[keyPath: key] ?? "" }, set: { content[keyPath: key] = optionalText($0) })
    }
    private func decimal(_ value: String, field: String, required: Bool = false) throws -> Double? {
        if value.isEmpty && !required { return nil }
        guard let number = Double(value), number.isFinite else {
            throw EditorFailure(message: "Enter a finite number for \(field), using a decimal point.")
        }
        return number
    }

    private func save() {
        do {
            guard let store = model.store else { throw EditorFailure(message: "The database is unavailable.") }
            guard analyteID != nil || !(content.sourceAnalyteText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EditorFailure(message: "Select a test or enter its original name.")
            }
            if result != nil && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw EditorFailure(message: "Enter a reason for this correction.")
            }
            let collected = try editedDate(text: date, precision: precision, original: result?.collectedAt ?? .unknown)
            var saved = content
            // Clear obsolete structured slots only when changing the type.
            // The prior revision and original text remain evidence.
            if result?.content.valueType != saved.valueType {
                saved.numericValue = nil; saved.codedValue = nil; saved.textValue = nil
                saved.ratioNumerator = nil; saved.ratioDenominator = nil
                saved.titerNumerator = nil; saved.titerDenominator = nil
            }
            saved.missingReason = saved.valueType == .absent ? (content.missingReason ?? .unknown) : nil
            switch saved.valueType {
            case .quantitative, .semiQuantitative:
                saved.numericValue = try decimal(number, field: "the value", required: true)
            case .qualitativeCoded, .ordinal:
                guard let value = content.codedValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EditorFailure(message: "Enter the reported result.")
                }
                saved.codedValue = value
            case .text:
                guard let value = content.textValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EditorFailure(message: "Enter the descriptive result.")
                }
                saved.textValue = value
            case .ratio:
                saved.ratioNumerator = try decimal(numerator, field: "numerator", required: true)
                saved.ratioDenominator = try decimal(denominator, field: "denominator", required: true)
                guard saved.ratioDenominator != 0 else { throw EditorFailure(message: "The denominator cannot be zero.") }
            case .titer:
                guard let n = Int(numerator), let d = Int(denominator), n > 0, d > 0 else {
                    throw EditorFailure(message: "A titer needs two positive whole numbers, such as 1 and 160.")
                }
                saved.titerNumerator = n; saved.titerDenominator = d
            case .absent: break
            }
            saved.rangeLow = try decimal(low, field: "lower reference bound")
            saved.rangeHigh = try decimal(high, field: "upper reference bound")
            saved.actor = "user"
            saved.contentOrigin = result == nil ? .userTranscription : .userCorrection
            saved.reasonText = result == nil ? nil : reason
            if let result {
                var edit = LabObservationMetadataEdit()
                if analyteID != result.catalogAnalyteID { edit.catalogAnalyteID = analyteID.map(FieldEdit.set) ?? .clear }
                edit.specimenKind = .set(specimen)
                edit.specimenText = specimenText.isEmpty ? .clear : .set(specimenText)
                edit.collectedAt = .set(collected); edit.reasonText = reason
                try store.saveManualEdit(id: result.observationID, content: saved, metadata: edit)
            } else {
                var draft = LabObservationDraft()
                draft.reportID = reportID; draft.catalogAnalyteID = analyteID
                if analyteID != nil { draft.matchOrigin = "user"; draft.matchConfidence = "user_assigned" }
                draft.collectedAt = collected; draft.specimenKind = specimen
                draft.specimenText = optionalText(specimenText)
                _ = try store.record(draft, content: saved)
            }
            model.changed(); dismiss()
        } catch { self.error = String(describing: error) }
    }
}
