import SwiftUI
import AlmanacCore
import Foundation

struct TrackingDaySummary: Hashable {
    let day: String
    let items: [TrackingTimelineItem]

    var isEmpty: Bool { items.isEmpty }
}

@MainActor
final class TrackingCalendarModel: ObservableObject {
    @Published private(set) var monthDate: Date
    @Published private(set) var todayDay: LogicalDay
    @Published private(set) var selectedDay: LogicalDay
    @Published private(set) var month = ActivityRingMonth(id: "", days: [])
    @Published private(set) var summary = TrackingDaySummary(day: "", items: [])
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var db: Database?
    private var timeModel: TimeModel { TimeModel(timeZone: .current) }
    private var lastToday: LogicalDay
    private var lastZoneSignature = ""
    private var followsToday = true

    init() {
        let model = TimeModel(timeZone: .current)
        let today = model.logicalDay(Date())
        let todayDate = Self.date(on: today, timeZone: model.timeZone)
        lastToday = today
        lastZoneSignature = Self.zoneSignature(model, at: Date())
        self.monthDate = todayDate
        self.todayDay = today
        self.selectedDay = today
    }

    func configure(db: Database?) {
        guard let db, self.db == nil else { return }
        self.db = db
        refresh()
    }

    func select(_ day: ActivityRingDay) {
        selectedDay = day.day
        followsToday = selectedDay == todayDay
        refresh()
    }

    func previousMonth() {
        moveMonth(by: -1)
    }

    func nextMonth() {
        moveMonth(by: 1)
    }

    var selectedActivity: ActivityRingDay? {
        month.day(on: selectedDay)
    }

    var database: Database? { db }

    var monthTitle: String {
        let parts = month.id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeModel.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    var leadingBlankCount: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    var weekdaySymbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeModel.timeZone
        guard let symbols = formatter.veryShortStandaloneWeekdaySymbols else { return [] }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    func tick() {
        let model = timeModel
        let now = Date()
        let today = model.logicalDay(now)
        let zoneChanged = Self.zoneSignature(model, at: now) != lastZoneSignature
        guard today != lastToday || zoneChanged else { return }
        todayDay = today
        if followsToday {
            selectedDay = today
            monthDate = Self.date(on: today, timeZone: model.timeZone)
        } else if zoneChanged {
            monthDate = Self.date(on: selectedDay, timeZone: model.timeZone)
        }
        refresh()
    }

    func refresh() {
        let model = timeModel
        let now = Date()
        let today = model.logicalDay(now)
        let currentTodayDate = Self.date(on: today, timeZone: model.timeZone)
        let zoneChanged = Self.zoneSignature(model, at: now) != lastZoneSignature
        todayDay = today
        if followsToday, today != lastToday || zoneChanged {
            selectedDay = today
            monthDate = currentTodayDate
        } else if zoneChanged {
            monthDate = Self.date(on: selectedDay, timeZone: model.timeZone)
        }
        lastToday = today
        lastZoneSignature = Self.zoneSignature(model, at: now)

        guard let db else { return }
        isLoading = true
        defer { isLoading = false }

        guard model.bounds(of: selectedDay) != nil else {
            error = "That calendar date is invalid."
            return
        }

        do {
            month = try ActivityRingCalendar(db: db, timeModel: model).month(containing: monthDate)
            let items = try TrackingTimeline(db: db).items(for: selectedDay.value, timeModel: model)
            summary = TrackingDaySummary(day: selectedDay.value, items: items)
            error = nil
        } catch {
            self.error = String(describing: error)
            summary = TrackingDaySummary(day: selectedDay.value, items: [])
        }
    }

    private func moveMonth(by value: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        guard let target = calendar.date(byAdding: .month, value: value, to: monthDate),
              let range = calendar.range(of: .day, in: .month, for: target)
        else { return }
        let currentDay = calendar.dateComponents([.day], from: Self.date(on: selectedDay, timeZone: calendar.timeZone)).day ?? 1
        let day = min(currentDay, range.count)
        let parts = calendar.dateComponents([.year, .month], from: target)
        selectedDay = LogicalDay(String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, day))
        monthDate = target
        followsToday = selectedDay == todayDay
        refresh()
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
}

@MainActor
struct ActivityRingDayEditor: View {
    let db: Database?
    let day: LogicalDay
    let onChanged: () -> Void

    @State private var hydrationEntries: [HydrationEntry] = []
    @State private var nutritionEntries: [NutritionLogStore.PlacedLogEntry] = []
    @State private var trainingSessions: [WorkoutSessionEntry] = []
    @State private var error: String?

    var body: some View {
        List {
            Section("Hydration") {
                if hydrationEntries.isEmpty {
                    Text("No hydration entries on this day.").foregroundStyle(.secondary)
                }
                ForEach(hydrationEntries) { entry in
                    NavigationLink {
                        ActivityRingHydrationEditor(db: db, entry: entry) {
                            reload()
                            onChanged()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ringFormat(entry.amount.value)) mL")
                            Text(entry.loggedAt.text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteHydration(entry.id) }
                    }
                }
            }

            Section("Nutrition") {
                if nutritionEntries.isEmpty {
                    Text("No nutrition entries on this day.").foregroundStyle(.secondary)
                }
                ForEach(nutritionEntries, id: \.entry.id) { placed in
                    NavigationLink {
                        ActivityRingNutritionEditor(db: db, entry: placed.entry) {
                            reload()
                            onChanged()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(placed.entry.foodNameText ?? placed.entry.foodRef.description)
                            Text(placed.entry.grams.map { "\(ringFormat($0)) g" } ?? "Amount not stated")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteNutrition(placed.entry.id) }
                    }
                }
            }

            Section("Training") {
                if trainingSessions.isEmpty {
                    Text("No training sessions on this day.").foregroundStyle(.secondary)
                }
                ForEach(trainingSessions) { session in
                    NavigationLink {
                        ActivityRingTrainingEditor(db: db, session: session) {
                            reload()
                            onChanged()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.sessionType ?? "Training")
                            Text(session.durationMinutes.map { "\($0) min" } ?? "Session logged")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteTraining(session.id) }
                    }
                }
            }

            Section {
                Text("Corrections are versioned by the owning log. Ring states recalculate after every save or deletion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit \(day.value)")
        .task { reload() }
        .editorError($error)
    }

    private func reload() {
        guard let db,
              let bounds = TimeModel(timeZone: .current).bounds(of: day) else { return }
        let range = DateRange(start: bounds.start, end: bounds.end).utcTextBounds
        do {
            hydrationEntries = try HydrationStore(db: db).logs(from: range.start, to: range.end)
            nutritionEntries = try NutritionLogStore(db: db).logged(from: range.start, to: range.end)
            trainingSessions = try WorkoutSessionStore(db: db).sessions(date: day.value)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func performDelete(_ operation: () throws -> Void) {
        do {
            try operation()
            reload()
            onChanged()
        } catch { self.error = String(describing: error) }
    }

    private func deleteHydration(_ id: String) {
        guard let db else { return }
        performDelete { try HydrationStore(db: db).delete(id: id) }
    }

    private func deleteNutrition(_ id: String) {
        guard let db else { return }
        performDelete { try NutritionLogStore(db: db).delete(id: id) }
    }

    private func deleteTraining(_ id: Int64) {
        guard let db else { return }
        performDelete {
            let bouts = try WorkoutBoutStore(db: db).bouts(sessionId: id)
            for bout in bouts {
                _ = try WorkoutBoutStore(db: db).delete(id: bout.id)
            }
            try WorkoutSessionStore(db: db).delete(id: id)
        }
    }
}

@MainActor
private struct ActivityRingHydrationEditor: View {
    let db: Database?
    let entry: HydrationEntry
    let onSaved: () -> Void

    @State private var amountText: String
    @State private var date: Date
    @State private var error: String?

    init(db: Database?, entry: HydrationEntry, onSaved: @escaping () -> Void) {
        self.db = db
        self.entry = entry
        self.onSaved = onSaved
        _amountText = State(initialValue: String(format: "%g", entry.amount.value))
        _date = State(initialValue: entry.loggedAt.span?.start ?? Date())
    }

    var body: some View {
        Form {
            TextField("Amount (mL)", text: $amountText)
                .keyboardType(.decimalPad)
            DatePicker("Occurred", selection: $date)
            Button("Save correction") { save() }
        }
        .navigationTitle("Edit hydration")
        .editorError($error)
    }

    private func save() {
        guard let db,
              let amount = Double(amountText),
              amount.isFinite,
              amount > 0 else {
            error = "Enter an amount greater than zero."
            return
        }
        do {
            let store = HydrationStore(db: db)
            try store.editAmount(id: entry.id, to: Milliliters(amount))
            try store.editLoggedAt(id: entry.id, to: date)
            onSaved()
        } catch { self.error = String(describing: error) }
    }
}

@MainActor
private struct ActivityRingNutritionEditor: View {
    let db: Database?
    let entry: NutritionLogEntry
    let onSaved: () -> Void

    private let canEditDate: Bool
    @State private var gramsText: String
    @State private var date: Date
    @State private var error: String?

    init(db: Database?, entry: NutritionLogEntry, onSaved: @escaping () -> Void) {
        self.db = db
        self.entry = entry
        self.onSaved = onSaved
        canEditDate = entry.eatenAt.precision == .instant
        _gramsText = State(initialValue: entry.grams.map { String(format: "%g", $0) } ?? "")
        _date = State(initialValue: entry.eatenAt.span?.start ?? Date())
    }

    var body: some View {
        Form {
            TextField("Amount (g, leave blank if unknown)", text: $gramsText)
                .keyboardType(.decimalPad)
            if canEditDate {
                DatePicker("Eaten", selection: $date)
            } else {
                LabeledContent("Original eaten time", value: entry.eatenAt.text)
                Text("The source did not state a precise time; it is preserved rather than replaced with the current time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save correction") { save() }
        }
        .navigationTitle("Edit nutrition")
        .editorError($error)
    }

    private func save() {
        guard let db else {
            error = "The database is unavailable."
            return
        }
        var edit = NutritionLogEdit()
        if gramsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            edit.grams = .clear
        } else if let grams = Double(gramsText), grams.isFinite, grams > 0 {
            edit.grams = .set(grams)
        } else {
            error = "Enter a positive amount or leave it blank."
            return
        }
        if canEditDate {
            edit.eatenAt = .set(PartialDateTime(instant: date, zone: ZoneContext(TimeZone.current)))
        }
        edit.reasonText = "Corrected from Activity Rings day detail"
        do {
            try NutritionLogStore(db: db).update(id: entry.id, edit)
            onSaved()
        } catch { self.error = String(describing: error) }
    }
}

@MainActor
private struct ActivityRingTrainingEditor: View {
    let db: Database?
    let session: WorkoutSessionEntry
    let onSaved: () -> Void

    @State private var date: Date
    @State private var error: String?

    init(db: Database?, session: WorkoutSessionEntry, onSaved: @escaping () -> Void) {
        self.db = db
        self.session = session
        self.onSaved = onSaved
        _date = State(initialValue: Self.date(on: LogicalDay(session.date)))
    }

    var body: some View {
        Form {
            DatePicker("Training day", selection: $date, displayedComponents: .date)
            Button("Save correction") { save() }
        }
        .navigationTitle("Edit training")
        .editorError($error)
    }

    private func save() {
        guard let db else {
            error = "The database is unavailable."
            return
        }
        do {
            let day = TimeModel(timeZone: .current).logicalDay(date).value
            try WorkoutSessionStore(db: db).updateDate(id: session.id, to: day)
            onSaved()
        } catch { self.error = String(describing: error) }
    }

    private static func date(on day: LogicalDay) -> Date {
        let parts = day.value.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            year: parts.first, month: parts.count > 1 ? parts[1] : nil,
            day: parts.count > 2 ? parts[2] : nil, hour: 12
        )) ?? Date()
    }
}

private func ringFormat(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}
