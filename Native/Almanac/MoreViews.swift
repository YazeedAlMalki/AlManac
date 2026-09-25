import SwiftUI
import AlmanacCore
import Combine
import Foundation

@MainActor
struct MoreView: View {
    let db: Database?
    let labModel: LaboratoryModel
    let hydrationModel: HydrationModel
    let healthModel: HealthModel
    let readinessModel: ReadinessModel
    let trackingModel: TrackingCalendarModel
    let prayerModel: PrayerModel
    let fastingModel: FastingModel

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ReportListView(model: labModel)
                } label: {
                    Label("Laboratory", systemImage: "cross.case")
                }

                NavigationLink {
                    ProfileView(db: db, readinessModel: readinessModel)
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }

                NavigationLink {
                    MeasurementsView(db: db, trackingModel: trackingModel)
                } label: {
                    Label("Measurements", systemImage: "ruler")
                }

                NavigationLink {
                    PrayerView(model: prayerModel)
                } label: {
                    Label("Prayer", systemImage: "sun.horizon")
                }

                NavigationLink {
                    FastingView(model: fastingModel)
                } label: {
                    Label("Fasting", systemImage: "moon.stars")
                }

                NavigationLink {
                    SettingsView(
                        model: hydrationModel,
                        labModel: labModel,
                        healthModel: healthModel,
                        trackingModel: trackingModel
                    )
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("More")
        }
    }
}

@MainActor
struct ProfileView: View {
    let db: Database?
    @ObservedObject var readinessModel: ReadinessModel

    @State private var displayName = ""
    @State private var dateOfBirth = ""
    @State private var biologicalSex = ""
    @State private var height = ""
    @State private var sports = ""
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                TextField("Date of birth (YYYY-MM-DD)", text: $dateOfBirth)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Biological sex", text: $biologicalSex)
                TextField("Height (cm)", text: $height)
                    .keyboardType(.decimalPad)
                TextField("Sports (comma-separated)", text: $sports)
            }

            if saved {
                Section {
                    Label("Profile saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(db == nil)
            }
        }
        .task { load() }
        .editorError($error)
    }

    private func load() {
        guard let db else { return }
        do {
            let profile = try ProfileStore(db: db).profile()
            displayName = profile.displayName
            dateOfBirth = profile.dateOfBirth ?? ""
            biologicalSex = profile.biologicalSex ?? ""
            height = profile.heightCm.map { String(describing: $0) } ?? ""
            sports = profile.sports.joined(separator: ", ")
        } catch {
            self.error = String(describing: error)
        }
    }

    private func save() {
        guard let db else { return }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw EditorFailure(message: "Enter a display name.")
            }

            let heightValue: Double?
            let trimmedHeight = height.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedHeight.isEmpty {
                heightValue = nil
            } else if let value = Double(trimmedHeight), value > 0, value < 300 {
                heightValue = value
            } else {
                throw EditorFailure(message: "Height must be a number between 0 and 300 cm.")
            }

            let store = ProfileStore(db: db)
            try store.updateDisplayName(name)
            try store.updateDateOfBirth(optionalText(dateOfBirth.trimmingCharacters(in: .whitespacesAndNewlines)))
            try store.updateBiologicalSex(optionalText(biologicalSex.trimmingCharacters(in: .whitespacesAndNewlines)))
            try store.updateHeight(heightValue)
            try store.updateSports(
                sports.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            readinessModel.refresh()
            saved = true
        } catch {
            self.error = String(describing: error)
        }
    }
}

@MainActor
struct MeasurementsView: View {
    let db: Database?
    @ObservedObject var trackingModel: TrackingCalendarModel

    @State private var bodyRecords: [BodyCompositionMeasurement] = []
    @State private var customDefinitions: [CustomMeasurementDefinition] = []
    @State private var customRecords: [CustomMeasurementLogEntry] = []
    @State private var addingBody = false
    @State private var addingCustom = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Body composition") {
                if bodyRecords.isEmpty {
                    Text("No measurements yet. Add a weight or body-composition reading below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bodyRecords) { record in
                        measurementRow(
                            title: bodyMetricTitle(record.metric),
                            value: record.value,
                            unit: record.unit,
                            date: record.timestamp,
                            detail: "\(readable(record.source)) · \(readable(record.conditions))"
                        )
                    }
                }
                Button("Log body measurement", systemImage: "plus") { addingBody = true }
                    .disabled(db == nil)
            }

            Section("Custom measurements") {
                if customRecords.isEmpty {
                    Text("No custom measurements yet. Add a circumference or other measurement below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customRecords) { record in
                        let definition = customDefinitions.first { $0.id == record.definitionId }
                        measurementRow(
                            title: definition?.name ?? "Custom measurement",
                            value: record.value,
                            unit: definition?.unit ?? "",
                            date: record.timestamp,
                            detail: record.notes
                        )
                    }
                }
                Button("Add custom measurement", systemImage: "plus") { addingCustom = true }
                    .disabled(db == nil)
            }
        }
        .navigationTitle("Measurements")
        .task { reload() }
        .sheet(isPresented: $addingBody) {
            BodyMeasurementEditor(db: db) {
                reload()
                trackingModel.refresh()
            }
        }
        .sheet(isPresented: $addingCustom) {
            CustomMeasurementEditor(db: db, definitions: customDefinitions) {
                reload()
                trackingModel.refresh()
            }
        }
        .editorError($error)
    }

    private func reload() {
        guard let db else { return }
        do {
            let range = recentLogicalDayRange()
            let bodyStore = BodyCompositionMeasurementStore(db: db)
            var body: [BodyCompositionMeasurement] = []
            for metric in bodyMetricOptions.map(\.id) {
                body.append(contentsOf: try bodyStore.records(metric: metric, from: range.from, to: range.to))
            }
            bodyRecords = body.sorted { $0.timestamp > $1.timestamp }

            let customStore = CustomMeasurementStore(db: db)
            customDefinitions = try customStore.definitions()
            var custom: [CustomMeasurementLogEntry] = []
            for definition in customDefinitions {
                custom.append(contentsOf: try customStore.history(
                    definitionId: definition.id, from: range.from, to: range.to))
            }
            customRecords = custom.sorted { $0.timestamp > $1.timestamp }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func measurementRow(title: String, value: Double, unit: String,
                                date: Date, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(format(value)) \(unit)")
                .font(.body.monospacedDigit())
        }
    }
}

@MainActor
private struct BodyMeasurementEditor: View {
    let db: Database?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metric = "weight"
    @State private var value = ""
    @State private var conditions = "unknown"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Metric", selection: $metric) {
                    ForEach(bodyMetricOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                TextField("Value", text: $value)
                    .keyboardType(.decimalPad)
                Picker("Conditions", selection: $conditions) {
                    Text("Unknown").tag("unknown")
                    Text("Fasted").tag("fasted")
                    Text("Not fasted").tag("non_fasted")
                }
            }
            .navigationTitle("Body measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(db == nil)
                }
            }
            .editorError($error)
        }
    }

    private func save() {
        guard let db,
              let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number.isFinite, number > 0 else {
            error = "Enter a positive measurement value."
            return
        }
        do {
            let option = bodyMetricOptions.first { $0.id == metric } ?? bodyMetricOptions[0]
            let now = Date()
            let day = TimeModel(timeZone: .current).logicalDay(now).value
            _ = try BodyCompositionMeasurementStore(db: db).log(
                BodyCompositionMeasurementDraft(
                    metric: option.id,
                    value: number,
                    unit: option.unit,
                    timestamp: now,
                    source: "manual",
                    conditions: conditions,
                    timezoneOffset: TimeZone.current.secondsFromGMT(for: now) / 60,
                    timezoneIdentifier: TimeZone.current.identifier
                ),
                logicalDay: day
            )
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

@MainActor
private struct CustomMeasurementEditor: View {
    let db: Database?
    let definitions: [CustomMeasurementDefinition]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "cm"
    @State private var value = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Measurement") {
                    TextField("Name (for example, waist)", text: $name)
                    TextField("Unit", text: $unit)
                    TextField("Value", text: $value)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Custom measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(db == nil)
                }
            }
            .editorError($error)
        }
    }

    private func save() {
        guard let db else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanUnit.isEmpty,
              let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number.isFinite, number > 0 else {
            error = "Enter a name, unit and positive value."
            return
        }
        do {
            let store = CustomMeasurementStore(db: db)
            let definitionID: Int64
            if let existing = definitions.first(where: { $0.name == cleanName }) {
                guard existing.unit == cleanUnit else {
                    throw EditorFailure(message: "\(cleanName) already uses \(existing.unit), not \(cleanUnit).")
                }
                definitionID = existing.id
            } else {
                definitionID = try store.createDefinition(name: cleanName, unit: cleanUnit)
            }
            let now = Date()
            let day = TimeModel(timeZone: .current).logicalDay(now).value
            _ = try store.log(
                CustomMeasurementLogDraft(
                    definitionId: definitionID,
                    value: number,
                    timestamp: now,
                    notes: optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines)),
                    timezoneOffset: TimeZone.current.secondsFromGMT(for: now) / 60,
                    timezoneIdentifier: TimeZone.current.identifier
                ),
                logicalDay: day
            )
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct BodyMetricOption: Identifiable {
    let id: String
    let title: String
    let unit: String
}

private let bodyMetricOptions = [
    BodyMetricOption(id: "weight", title: "Weight", unit: "kg"),
    BodyMetricOption(id: "body_fat_pct", title: "Body fat", unit: "pct"),
    BodyMetricOption(id: "lean_mass_kg", title: "Lean mass", unit: "kg"),
    BodyMetricOption(id: "skeletal_muscle_kg", title: "Skeletal muscle", unit: "kg"),
    BodyMetricOption(id: "visceral_rating", title: "Visceral rating", unit: "rating")
]

private func bodyMetricTitle(_ metric: String) -> String {
    bodyMetricOptions.first { $0.id == metric }?.title ?? readable(metric)
}

private func recentLogicalDayRange() -> (from: String, to: String) {
    let timeModel = TimeModel(timeZone: .current)
    var day = timeModel.logicalDay(Date())
    for _ in 0..<30 {
        guard let previous = timeModel.day(before: day) else { break }
        day = previous
    }
    let today = timeModel.logicalDay(Date())
    return (day.value, timeModel.day(after: today)?.value ?? today.value)
}

private func format(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}
