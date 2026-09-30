import SwiftUI
import AlmanacCore
import Combine
import Foundation

/// The Modules menu.
///
/// **Generated from `AppRoute.menu`, not written out.** The list of screens and
/// the list of things you can be navigated to are the same list, which is the
/// only reason they cannot drift. A hand-written `NavigationLink { Body… }` per
/// row is a second inventory of the app's screens, and the day a screen is
/// added to one and not the other nobody finds out until someone taps a button
/// that goes nowhere.
///
/// The group and the title of each row are data on the route, so adding a screen
/// is one `case` plus one `switch` arm in `AppRoute.tab` — the latter
/// compiler-enforced.
@MainActor
struct ModulesView: View {
    /// Non-optional, and the callers make that true.
    ///
    /// Half the screens behind this menu need a database outright — they open
    /// their own store on it — and the old shape was `Database?` with an
    /// `if let db` per row, which is a screen list that is quietly half as long
    /// as the app when the database is missing. `appShell` is only rendered
    /// when the laboratory store opened, and `db` is assigned immediately
    /// before it, so the optional was never load-bearing; it only existed to
    /// be unwrapped again at every row.
    let db: Database
    let labModel: LaboratoryModel
    let hydrationModel: HydrationModel
    let nutritionModel: NutritionModel
    let trainingModel: TrainingModel
    let healthModel: HealthModel
    let readinessModel: ReadinessModel
    let trackingModel: TrackingCalendarModel
    let prayerModel: PrayerModel
    let fastingModel: FastingModel
    let notificationModel: NotificationModel

    @Environment(\.tabCoordinator) private var tabs

    /// A stack that never pushes. Used only when this screen is rendered with
    /// no coordinator in its environment — a preview, or a host that has not
    /// wired one up. The menu rows then do nothing rather than crashing, which
    /// is the right failure for a view whose whole job is to be embedded.
    private var emptyPath: Binding<[AppRoute]> { .constant([]) }

    var body: some View {
        NavigationStack(path: tabs?.path(for: .modules) ?? emptyPath) {
            List {
                Section {
                    Text("Everything you enter stays in Almanac’s local database on this device. Apple Health is used only for the connections you enable.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .listRowBackground(AlmanacPalette.surface)
                }

                ForEach(AppRoute.menu) { group in
                    Section(group.section.title) {
                        ForEach(group.routes) { route in
                            NavigationLink(value: route) {
                                Label(route.title, systemImage: route.icon)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AlmanacPalette.canvas)
            .navigationTitle("Modules")
            .toolbarBackground(AlmanacPalette.canvas, for: .navigationBar)
            .almanacScreen()
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
    }

    /// The one place a route becomes a screen.
    ///
    /// A `switch`, not a table, so adding a route without a screen is a
    /// non-exhaustive switch — a build failure rather than a menu row that
    /// pushes nothing.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .training:
            TrainingDashboardView(model: trainingModel, embedded: true)
        case .hydration:
            HydrationDashboardView(model: hydrationModel, embedded: true)
        case .nutrition:
            NutritionQuickEntryView(model: nutritionModel, embedded: true)
        case .fasting:
            FastingView(model: fastingModel)
        case .supplements:
            SupplementView(db: db, trackingModel: trackingModel)
        case .context:
            ContextTagsView(db: db, trackingModel: trackingModel)
        case .prayer:
            PrayerView(model: prayerModel)
        case .bodyCircumference:
            BodyCircumferenceView(db: db, healthModel: healthModel)
        case .laboratory:
            ReportListView(model: labModel)
        case .laboratoryImportHistory:
            LabImportHistoryView(model: labModel)
        case .timeline:
            DayTimelineView(db: db)
        case .bodyComposition:
            MeasurementsView(db: db, trackingModel: trackingModel)
        case .profile:
            ProfileView(db: db, readinessModel: readinessModel)
        case .settings:
            SettingsView(
                model: hydrationModel,
                labModel: labModel,
                healthModel: healthModel,
                trackingModel: trackingModel,
                notificationModel: notificationModel
            )
        // The tab roots. Reached by pushing a tab's own root onto itself, which
        // no caller does — the bar switches tabs instead — so they are here only
        // because `AppRoute` is exhaustive and this switch has to be too.
        case .todayRoot, .trendsRoot, .trendsDetail:
            EmptyView()
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
                        .foregroundStyle(AlmanacPalette.good)
                }
            }
        }
        .navigationTitle("Profile")
        .almanacModuleSurface()
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
        .almanacModuleSurface()
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

struct BodyMetricOption: Identifiable {
    let id: String
    let title: String
    let unit: String
}

let bodyMetricOptions = [
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
