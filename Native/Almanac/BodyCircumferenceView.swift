import SwiftUI
import Charts
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
            // One row, not the list of points: the points and their charts are
            // their own screen, so this screen's recent entries stay where a
            // person (and the UI test) expects them.
            NavigationLink {
                CircumferencePointsView(db: db)
            } label: {
                Label("Points and charts", systemImage: "chart.xyaxis.line")
            }
            .accessibilityIdentifier("circumference-points")
            Text("Centimeters only. Waist can sync with Apple Health; other points are manual.")
            if let problem = healthModel.problem { Text(problem) }
            Section("Recent entries") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading) {
                        Text("\(entry.measurementType.rawValue.capitalized)\(entry.side.map { " · " + $0.rawValue } ?? ""): \(entry.valueCm.formatted()) cm")
                        Text(entry.measuredAt.almanacFormatted(date: .abbreviated, time: .shortened))
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
    /// What the picker chose: a built-in point or one the owner named. `type`
    /// follows it for built-ins, because the side rule and the typo guard are
    /// the built-in's.
    @State private var point = CircumferencePoint.builtIn(.waist)
    @State private var points: [CircumferencePoint] = BodyMeasurementType.allCases.map(CircumferencePoint.builtIn)
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
                    Picker("Measurement", selection: $point) {
                        ForEach(points) { point in
                            Text(point.name).tag(point)
                        }
                    }
                    .accessibilityIdentifier("circumference-type")
                    .onChange(of: point) { _, chosen in
                        if case let .builtIn(builtIn) = chosen { type = builtIn }
                    }
                    if point.isBuiltIn && type.supportsSides && trackSides {
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
            .navigationTitle(entry == nil ? String(localized: "Log circumference") : String(localized: "Correct circumference"))
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
                    points = try CircumferencePointCatalog(db: db).points()
                    if let first = points.first, !points.contains(point) { point = first }
                    if case let .builtIn(builtIn) = point { type = builtIn }
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(userInput: trimmed)
                ?? (try? Double(trimmed, format: .number, lenient: false)) else {
            error = String(localized: "Enter a number in centimeters.")
            return
        }
        do {
            let store = BodyMeasurementStore(db: db)
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if let entry {
                try store.edit(id: entry.id, valueCm: number, note: cleanNote.isEmpty ? nil : cleanNote,
                               allowUnusualValue: allowUnusual)
            } else {
                try CircumferencePointCatalog(db: db).log(
                    to: point, valueCm: number, at: measuredAt,
                    side: point.isBuiltIn && type.supportsSides && trackSides ? side : nil,
                    note: cleanNote.isEmpty ? nil : cleanNote,
                    allowUnusualValue: allowUnusual)
            }
            onSaved()
            dismiss()
        } catch BodyMeasurementError.unusuallySized { confirmUnusual = true }
        catch { self.error = error.localizedDescription }
    }
}

/// The owner's circumference points, each opening its chart, with the
/// built-ins they can hide and the points they can add (BRD §6.6:
/// "user-definable, charted").
@MainActor
struct CircumferencePointsView: View {
    let db: Database
    @State private var points: [CircumferencePoint] = []
    @State private var hidden: Set<BodyMeasurementType> = []
    @State private var newName = ""
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(points) { point in
                    NavigationLink {
                        CircumferencePointHistoryView(db: db, point: point)
                    } label: {
                        Text(point.name)
                    }
                    .accessibilityIdentifier("circumference-point-\(point.name)")
                }
            } header: {
                Text("Your points")
            } footer: {
                Text("Hiding a point keeps its readings. Owner points are in centimetres and have no sides.")
            }
            Section("Add a point") {
                TextField("Name, for example forearm", text: $newName)
                    .accessibilityIdentifier("circumference-new-point")
                Button("Add point") { add() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("circumference-add-point")
            }
            Section("Built-in points") {
                ForEach(BodyMeasurementType.allCases, id: \.self) { type in
                    Toggle(type.rawValue.capitalized, isOn: Binding(
                        get: { !hidden.contains(type) },
                        set: { setShown(type, $0) }))
                    .accessibilityIdentifier("circumference-show-\(type.rawValue)")
                }
            }
        }
        .navigationTitle("Points and charts")
        .task { reload() }
        .editorError($error)
    }

    private func reload() {
        do {
            let catalog = CircumferencePointCatalog(db: db)
            points = try catalog.points()
            hidden = try catalog.hiddenBuiltIns()
        } catch { self.error = error.localizedDescription }
    }

    private func add() {
        do {
            try CircumferencePointCatalog(db: db).addPoint(name: newName)
            newName = ""
            reload()
        } catch CircumferencePointError.duplicateName {
            error = String(localized: "There is already a point with that name.")
        } catch { self.error = error.localizedDescription }
    }

    private func setShown(_ type: BodyMeasurementType, _ shown: Bool) {
        do {
            try CircumferencePointCatalog(db: db).setHidden(type, !shown)
            reload()
        } catch { self.error = error.localizedDescription }
    }
}

/// One point over the last year: a line per side, and the readings beneath it.
@MainActor
struct CircumferencePointHistoryView: View {
    let db: Database
    let point: CircumferencePoint
    @State private var series: [CircumferenceSeries] = []
    @State private var error: String?

    var body: some View {
        List {
            if series.isEmpty {
                Text("No readings for this point in the last year.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("circumference-chart-empty")
            } else {
                Section {
                    Chart {
                        ForEach(series, id: \.side) { line in
                            ForEach(line.values, id: \.self) { value in
                                LineMark(x: .value("Date", value.date), y: .value("cm", value.value))
                                    .foregroundStyle(by: .value("Side", sideName(line.side)))
                                PointMark(x: .value("Date", value.date), y: .value("cm", value.value))
                                    .foregroundStyle(by: .value("Side", sideName(line.side)))
                            }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityIdentifier("circumference-chart")
                }
                ForEach(series, id: \.side) { line in
                    Section(sideName(line.side)) {
                        ForEach(line.values.reversed(), id: \.self) { value in
                            HStack {
                                Text(value.date.almanacFormatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(value.value.formatted()) cm").monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .navigationTitle(point.name)
        .task { reload() }
        .editorError($error)
    }

    private func sideName(_ side: BodyMeasurementSide?) -> String {
        switch side {
        case .left: return String(localized: "Left")
        case .right: return String(localized: "Right")
        case nil: return String(localized: "Readings")
        }
    }

    private func reload() {
        let now = Date()
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        do {
            series = try CircumferencePointCatalog(db: db).series(
                for: point, from: yearAgo, to: now.addingTimeInterval(60))
        } catch { self.error = error.localizedDescription }
    }
}
