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
struct TrackingCalendarView: View {
    @ObservedObject var model: TrackingCalendarModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.previousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Previous month")

                Spacer()
                Text(model.monthTitle)
                    .font(.headline)
                    .id(model.month.id)
                    .accessibilityIdentifier("activity-ring-month-title")
                Spacer()

                Button {
                    model.nextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Next month")
            }

            HStack {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<model.leadingBlankCount, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }
                ForEach(model.month.days) { day in
                    Button {
                        model.select(day)
                    } label: {
                        ActivityRingDayCell(
                            day: day,
                            isToday: day.day == model.todayDay,
                            isSelected: day.day == model.selectedDay
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("activity-ring-day-\(day.day.value)")
                    .accessibilityLabel(accessibilityLabel(for: day))
                }
            }

            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let day = model.selectedActivity {
                Divider()
                Text("Rings for \(day.day.value)")
                    .font(.headline)
                ringRow(
                    title: "Hydration",
                    state: day.hydration == .complete ? "Target met" : "Target not met",
                    detail: "\(ringFormat(day.hydrationTotalMilliliters.value)) of \(ringFormat(day.hydrationTargetMilliliters.value)) mL",
                    complete: day.hydration == .complete
                )
                ringRow(
                    title: "Training",
                    state: day.training == .complete ? "Logged" : "Not logged",
                    detail: nil,
                    complete: day.training == .complete
                )
                let nutrition = nutritionPresentation(day.nutrition)
                ringRow(
                    title: "Nutrition",
                    state: nutrition.state,
                    detail: nutrition.detail,
                    complete: nutrition.complete
                )
                if day.nutrition == .dietProfileRequired {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Per-value status")
                            .font(.caption.weight(.semibold))
                        ForEach(["Calories", "Carbohydrates", "Protein", "Fat", "Fiber"], id: \.self) { name in
                            Label("\(name): unavailable", systemImage: "questionmark")
                                .font(.caption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ringRow(
                    title: "Digestion",
                    state: day.digestion == .disabled ? "Off" : "On; daily fill rule unavailable",
                    detail: nil,
                    complete: false
                )
                NavigationLink {
                    ActivityRingDayEditor(db: model.database, day: day.day) {
                        model.refresh()
                    }
                } label: {
                    Label("Edit selected day's logs", systemImage: "pencil")
                }
                .disabled(model.database == nil)
                if day.isGolden {
                    Label("All visible rings complete — golden day", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if model.summary.isEmpty {
                    Text("No other tracked records on \(model.summary.day).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tracked records")
                        .font(.subheadline.weight(.semibold))
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
            }

            Text("Almanac logical days start at 04:00 local time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            model.tick()
        }
    }

    private func nutritionPresentation(_ state: ActivityRingNutritionState) -> (state: String, detail: String?, complete: Bool, accessibility: String) {
        switch state {
        case .hit: return ("Targets hit", nil, true, "nutrition hit")
        case .off: return ("Off target", nil, false, "nutrition off target")
        case .mess: return ("Mess", nil, false, "nutrition mess")
        case .notLogged: return ("No nutrition logged; no ring", nil, false, "no nutrition ring")
        case .dietProfileRequired:
            return ("Diet Profile required", "Hit, off and mess remain unavailable until Diet Profile targets exist", false, "nutrition awaiting Diet Profile")
        }
    }

    private func ringRow(title: String, state: String, detail: String?, complete: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(complete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title): \(state)").font(.subheadline)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func accessibilityLabel(for day: ActivityRingDay) -> String {
        let hydration = day.hydration == .complete ? "complete" : "incomplete"
        let training = day.training == .complete ? "complete" : "incomplete"
        let nutrition = nutritionPresentation(day.nutrition).accessibility
        let digestion = day.digestion == .disabled ? "digestion off" : "digestion fill rule unavailable"
        var parts = [day.day.value, "Hydration \(hydration)", "Training \(training)", nutrition, digestion]
        if day.isGolden { parts.append("golden day, all visible rings complete") }
        if day.day == model.todayDay { parts.append("today") }
        if day.day == model.selectedDay { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

private struct ActivityRingDayCell: View {
    let day: ActivityRingDay
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            if day.isGolden {
                Circle()
                    .fill(Color.yellow.opacity(0.18))
                    .frame(width: 42, height: 42)
            }

            Circle()
                .strokeBorder(day.hydration == .complete ? Color.cyan : Color.cyan.opacity(0.3), lineWidth: 3)
                .frame(width: 32, height: 32)
            Circle()
                .trim(from: 0, to: day.hydration == .complete ? 1 : 0)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 32, height: 32)

            Circle()
                .strokeBorder(day.training == .complete ? Color.green : Color.green.opacity(0.3), lineWidth: 3)
                .frame(width: 23, height: 23)
            Circle()
                .trim(from: 0, to: day.training == .complete ? 1 : 0)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 23, height: 23)

            if day.nutrition == .dietProfileRequired {
                Circle()
                    .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .frame(width: 14, height: 14)
            }

            if isToday {
                Circle()
                    .strokeBorder(Color.teal, lineWidth: 2)
                    .frame(width: 40, height: 40)
            }

            Text(String(day.dayNumber))
                .font(.caption.weight(day.isGolden ? .bold : .regular))
        }
        .frame(width: 44, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.teal.opacity(0.14) : Color.clear)
        )
        .overlay(alignment: .topLeading) {
            if day.isGolden {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if day.digestion == .fillRuleUnavailable {
                ZStack {
                    Circle()
                        .strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                        .frame(width: 16, height: 16)
                    Text("D")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.purple)
                }
            }
        }
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
