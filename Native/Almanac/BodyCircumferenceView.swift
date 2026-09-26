import SwiftUI
import AlmanacCore

@MainActor
struct BodyCircumferenceView: View {
    let db: Database
    @ObservedObject var healthModel: HealthModel
    @State private var entries: [BodyMeasurement] = []
    @State private var adding = false
    @State private var editing: BodyMeasurement?
    @State private var error: String?

    var body: some View {
        List {
            Button("Log circumference") { adding = true }
            Text("Centimeters only. Waist can sync with Apple Health; other points are manual.")
            if let problem = healthModel.problem { Text(problem) }
            Section("Recent entries") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading) {
                        Text("\(entry.measurementType.rawValue.capitalized)\(entry.side.map { " · " + $0.rawValue } ?? ""): \(entry.valueCm.formatted()) cm")
                        Text(entry.measuredAt.formatted(date: .abbreviated, time: .shortened))
                        if entry.source == .healthkit { Text("Synced from Health") }
                        if let note = entry.note { Text(note) }
                    }
                    .swipeActions {
                        if entry.source == .manual {
                            Button("Delete", role: .destructive) { delete(entry) }
                            Button("Edit") { editing = entry }
                        }
                    }
                    .contextMenu {
                        if entry.source == .manual {
                            Button("Edit") { editing = entry }
                            Button("Delete", role: .destructive) { delete(entry) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Body circumferences")
        .task { reload() }
        .onChange(of: healthModel.lastSynced) { _, _ in reload() }
        .sheet(isPresented: $adding) {
            CircumferenceEditor(db: db, entry: nil, onSaved: saved)
        }
        .sheet(item: $editing) { entry in
            CircumferenceEditor(db: db, entry: entry, onSaved: saved)
        }
        .editorError($error)
    }

    private func reload() {
        do { entries = try BodyMeasurementStore(db: db).recentEntries() }
        catch { self.error = error.localizedDescription }
    }

    private func saved() {
        reload()
        Task { await healthModel.syncNow(); reload() }
    }

    private func delete(_ entry: BodyMeasurement) {
        do { try BodyMeasurementStore(db: db).delete(id: entry.id); reload() }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
private struct CircumferenceEditor: View {
    let db: Database
    let entry: BodyMeasurement?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type = BodyMeasurementType.waist
    @State private var side = BodyMeasurementSide.left
    @State private var trackSides = false
    @State private var value = ""
    @State private var note = ""
    @State private var measuredAt = Date()
    @State private var error: String?
    @State private var confirmUnusual = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if let entry {
                    Text("\(entry.measurementType.rawValue.capitalized)\(entry.side.map { " · " + $0.rawValue } ?? "")")
                    Text("Corrections and deletions here do not change previously exported Apple Health samples.")
                } else {
                    Picker("Measurement", selection: $type) {
                        ForEach(BodyMeasurementType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .accessibilityIdentifier("circumference-type")
                    if type.supportsSides && trackSides {
                        Picker("Side", selection: $side) {
                            ForEach(BodyMeasurementSide.allCases, id: \.self) { side in
                                Text(side.rawValue.capitalized).tag(side)
                            }
                        }
                        .accessibilityIdentifier("circumference-side")
                        Text("Log each side as a separate entry.")
                    }
                    DatePicker("Measured at", selection: $measuredAt)
                }
                TextField("Circumference (cm)", text: $value).keyboardType(.decimalPad)
                TextField("Note", text: $note, axis: .vertical)
            }
            .navigationTitle(entry == nil ? "Log circumference" : "Correct circumference")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!loaded)
                }
            }
            .task {
                guard !loaded else { return }
                do {
                    trackSides = try ProfileStore(db: db).profile().bodyMeasurementTrackSides
                    if let entry {
                        type = entry.measurementType
                        value = entry.valueCm.formatted(.number.grouping(.never))
                        note = entry.note ?? ""
                    }
                    loaded = true
                } catch { self.error = error.localizedDescription }
            }
            .alert("That looks unusually low or high", isPresented: $confirmUnusual) {
                Button("Save anyway") { save(allowUnusual: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Check the measurement and that it is in centimeters.") }
            .editorError($error)
        }
    }

    private func save(allowUnusual: Bool = false) {
        guard let number = try? Double(value.trimmingCharacters(in: .whitespacesAndNewlines),
                                       format: .number, lenient: false) else {
            error = "Enter a number in centimeters."
            return
        }
        do {
            let store = BodyMeasurementStore(db: db)
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if let entry {
                try store.edit(id: entry.id, valueCm: number, note: cleanNote.isEmpty ? nil : cleanNote,
                               allowUnusualValue: allowUnusual)
            } else {
                try store.log(BodyMeasurementDraft(measuredAt: measuredAt, measurementType: type,
                              side: type.supportsSides && trackSides ? side : nil,
                              valueCm: number, note: cleanNote.isEmpty ? nil : cleanNote),
                              allowUnusualValue: allowUnusual)
            }
            onSaved()
            dismiss()
        } catch BodyMeasurementError.unusuallySized { confirmUnusual = true }
        catch { self.error = error.localizedDescription }
    }
}
