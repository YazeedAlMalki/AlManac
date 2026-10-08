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
    let programModel: ProgramModel
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
            TrainingDashboardView(model: trainingModel, programModel: programModel, embedded: true)
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
            PrayerView(model: prayerModel, notificationModel: notificationModel)
        case .bodyCircumference:
            BodyCircumferenceView(db: db, healthModel: healthModel)
        case .vitals:
            VitalsView(db: db, readinessModel: readinessModel, healthModel: healthModel)
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
struct MeasurementsView: View {
    let db: Database?
    @ObservedObject var trackingModel: TrackingCalendarModel

    /// The five cards, built in one pass from two queries.
    @State private var bodyCards: [BodyCompositionProgress] = []
    @State private var bodyHistory: [BodyCompositionMeasurement] = []
    @State private var customDefinitions: [CustomMeasurementDefinition] = []
    @State private var customRecords: [CustomMeasurementLogEntry] = []
    @State private var addingBody = false
    @State private var addingCustom = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Body composition") {
                // The cards are the screen. Five of them, every one present even
                // with no reading, because a grid whose layout depends on what
                // happens to be logged is a grid you re-learn every week — and
                // "No target set" on an empty meter is a legible card, not a
                // broken one.
                BodyCompositionGrid(cards: bodyCards)

                Button("Log body measurement", systemImage: "plus") { addingBody = true }
                    .disabled(db == nil)
            }

            // The readings themselves, which is a different question from "where
            // am I". Its own section rather than stacked under the cards so a
            // screen with 200 readings still shows five cards above the fold.
            if !bodyHistory.isEmpty {
                Section("Readings") {
                    ForEach(bodyHistory) { record in
                        measurementRow(
                            title: bodyMetricTitle(record.metric),
                            value: record.value,
                            unit: record.unit,
                            date: record.timestamp,
                            detail: "\(readable(record.source)) · \(readable(record.conditions))"
                        )
                    }
                }
            }

            Section("Custom measurements") {
                if customRecords.isEmpty {
                    Text("No custom measurements yet. Add a circumference or other measurement below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customRecords) { record in
                        let definition = customDefinitions.first { $0.id == record.definitionId }
                        measurementRow(
                            title: definition?.name ?? String(localized: "Custom measurement"),
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
        .navigationTitle("Body composition")
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
            let metrics = BodyMetric.allCases.map(\.rawValue)

            // **Three queries for the whole grid**, and the count is stated because
            // it is the thing to keep flat as the screen grows. The obvious loop is
            // `for metric in metrics { records(metric:) }`, which is five queries
            // to draw five cards on a screen the user opens often, and its cost
            // grows with the metric list rather than with the data.
            //
            // `snapshotsInForce` rather than `activeTargets`, because the two
            // differ in a way the card depends on and only one of them is honest
            // here. `activeTargets` returns resolved numbers, dropping a metric
            // whose target is absent — so "no target" and "no target *row*" arrive
            // as the same missing dictionary key. The snapshot keeps that
            // distinction, which is what lets a card say "No target set" instead
            // of inventing a default.
            //
            // `all(from:targets:unitBasis:)` then builds every card from rows
            // already in memory, so the arithmetic happens once per reading rather
            // than once per card.
            let series = try bodyStore.records(forMetrics: metrics, from: range.from, to: range.to)
            let inForce = try GoalTargetSnapshotStore(db: db).snapshotsInForce(on: range.from)
            let basis = try ProfileStore(db: db).unitBasis()
            bodyCards = BodyCompositionProgress.all(from: series,
                                                   targets: inForce,
                                                   unitBasis: basis)

            // The history list below the grid is a different question — "what have
            // I logged", not "where am I" — and it wants the same rows sorted
            // newest first, which is one sort over what was already read.
            bodyHistory = series.sorted { $0.timestamp > $1.timestamp }

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
    /// The stored raw value, not the enum: `body_composition_measurement.metric`
    /// is a `TEXT` column and `BodyCompositionMeasurementDraft` takes the string.
    @State private var metric = BodyMetric.weight.rawValue
    @State private var value = ""
    @State private var conditions = "unknown"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Metric", selection: $metric) {
                    // From `BodyMetric.allCases`, not a list in this file. The
                    // old `bodyMetricOptions` was the only definition of what may
                    // go in that column and it lived in the view target, so core
                    // could not check a write and this picker could disagree with
                    // the store about what a metric is called.
                    ForEach(BodyMetric.allCases) { option in
                        Text(option.title).tag(option.rawValue)
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
              let number = Double(userInput: value),
              number.isFinite, number > 0 else {
            error = String(localized: "Enter a positive measurement value.")
            return
        }
        do {
            // A metric the picker cannot produce falls back to weight rather than
            // being written through: a row whose metric is not in the vocabulary
            // is a card that can never be drawn, and this is the last point
            // before the write.
            let chosen = BodyMetric(rawValue: metric) ?? .weight
            let now = Date()
            let day = TimeModel(timeZone: .current).logicalDay(now).value
            _ = try BodyCompositionMeasurementStore(db: db).log(
                BodyCompositionMeasurementDraft(
                    metric: chosen.rawValue,
                    value: number,
                    // The *stored* unit token, not the display one: `pct` and `%`
                    // are both display strings and only the first is what a row
                    // holds.
                    unit: chosen.unit,
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
              let number = Double(userInput: value),
              number.isFinite, number > 0 else {
            error = String(localized: "Enter a name, unit and positive value.")
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

/// The title for a stored metric string.
///
/// Falls back to the raw value for anything not in `BodyMetric`, because a row
/// that is somehow there still has to be readable in a list — the fallback is
/// honest about not knowing rather than hiding the row. This replaces a
/// `bodyMetricOptions` array that duplicated the vocabulary in the view target,
/// where core could not see it and a rename of a case would have left the two
/// silently disagreeing about what a column may contain.
private func bodyMetricTitle(_ metric: String) -> String {
    BodyMetric(rawValue: metric)?.title ?? readable(metric)
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
