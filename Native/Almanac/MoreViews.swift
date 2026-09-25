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
                    SettingsView(model: hydrationModel, labModel: labModel, healthModel: healthModel)
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

struct TrackingDaySummary: Hashable {
    let day: String
    let items: [TrackingTimelineItem]

    var isEmpty: Bool { items.isEmpty }
}

@MainActor
final class TrackingCalendarModel: ObservableObject {
    @Published var selectedDate: Date
    @Published private(set) var todayDate: Date
    @Published private(set) var summary = TrackingDaySummary(day: "", items: [])
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var db: Database?
    private var timeModel: TimeModel { TimeModel(timeZone: .current) }
    private var lastToday: LogicalDay
    private var lastZoneSignature = ""
    private var selectedDay: LogicalDay
    private var followsToday = true

    init() {
        let model = TimeModel(timeZone: .current)
        let today = model.logicalDay(Date())
        let todayDate = Self.date(on: today, timeZone: model.timeZone)
        lastToday = today
        lastZoneSignature = Self.zoneSignature(model, at: Date())
        selectedDay = today
        self.todayDate = todayDate
        selectedDate = todayDate
    }

    func configure(db: Database?) {
        guard let db, self.db == nil else { return }
        self.db = db
        refresh()
    }

    func select(_ date: Date) {
        let day = calendarDayLabel(date)
        let model = timeModel
        let today = model.logicalDay(Date())
        selectedDay = LogicalDay(day)
        followsToday = day == today.value
        selectedDate = date
        refresh()
    }

    func tick() {
        let model = timeModel
        let now = Date()
        guard model.logicalDay(now) != lastToday
                || Self.zoneSignature(model, at: now) != lastZoneSignature else { return }
        refresh()
    }

    func refresh() {
        let model = timeModel
        let now = Date()
        let today = model.logicalDay(now)
        let currentTodayDate = Self.date(on: today, timeZone: model.timeZone)
        let zoneChanged = Self.zoneSignature(model, at: now) != lastZoneSignature
        if todayDate != currentTodayDate { todayDate = currentTodayDate }
        if followsToday, today != lastToday || zoneChanged {
            selectedDay = today
            selectedDate = currentTodayDate
        } else if !followsToday {
            // The picker stores a Date for SwiftUI, but the user's choice is a
            // logical day. Re-materialize it after a timezone/DST change so a
            // noon date never silently becomes a different calendar day.
            selectedDate = Self.date(on: selectedDay, timeZone: model.timeZone)
        }
        lastToday = today
        lastZoneSignature = Self.zoneSignature(model, at: now)

        guard let db else { return }
        isLoading = true
        defer { isLoading = false }

        let logicalDay = selectedDay
        guard model.bounds(of: logicalDay) != nil else {
            error = "That calendar date is invalid."
            return
        }

        do {
            let items = try TrackingTimeline(db: db).items(for: logicalDay.value, timeModel: model)
            summary = TrackingDaySummary(day: logicalDay.value, items: items)
            error = nil
        } catch {
            self.error = String(describing: error)
            summary = TrackingDaySummary(day: logicalDay.value, items: [])
        }
    }

    private static func zoneSignature(_ model: TimeModel, at instant: Date) -> String {
        "\(model.timeZone.identifier)|\(model.timeZone.secondsFromGMT(for: instant))"
    }

    private static func date(on day: LogicalDay, timeZone: TimeZone) -> Date {
        let parts = day.value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }

    private func calendarDayLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

@MainActor
struct TrackingCalendarView: View {
    @ObservedObject var model: TrackingCalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Tracking date",
                selection: Binding(
                    get: { model.selectedDate },
                    set: { model.select($0) }
                ),
                in: Date(timeIntervalSince1970: 0)...model.todayDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                model.tick()
            }

            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if model.summary.isEmpty {
                Text("No tracked records on \(model.summary.day).")
                    .foregroundStyle(.secondary)
            } else {
                Text("Tracked on \(model.summary.day)")
                    .font(.headline)
                ForEach(model.summary.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        if let value = item.value, !value.isEmpty {
                            Text(value).font(.caption)
                        }
                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Text("Almanac logical days start at 04:00 local time.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
