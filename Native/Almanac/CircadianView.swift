import SwiftUI
import AlmanacCore
import Foundation

/// The shifts a person has entered, and the rhythm they add up to (BRD §6.11,
/// §13): the last six days, today, and the week ahead.
///
/// **The forward days are the useful half.** A move from days to nights is a
/// process, and the screen that says "day 2 of moving to later hours" is the
/// one a person opens the week before it happens. Both halves come from the
/// same place — `CircadianTimeline`, which runs the §13 engine over the entered
/// shifts — so a planned week reads the way a lived one will.
///
/// **A person with no shifts is told what the screen needs, not shown a blank
/// week.** §6.11 makes that the ordinary case and requires it to stay fully
/// supported: there is no claim to make about a rhythm nobody entered, so none
/// is made.
///
/// **Saved patterns are listed here, and picked here.** Nothing changes at a
/// period end until the person picks; with the period-end reminder off, the
/// pattern set as next starts by itself (`SavedShiftPatternStore.refresh`).
@MainActor
struct CircadianView: View {
    let db: Database
    var notificationModel: NotificationModel?

    @State private var days: [CircadianContext] = []
    /// The saved pattern's shift on a day a one-day entry replaced, by date.
    @State private var patternNotes: [String: ShiftType] = [:]
    @State private var patterns: [SavedShiftPattern] = []
    @State private var selection = SavedShiftPatternSelection.none
    @State private var nextPeriodStart: LogicalDay?
    @State private var reminderOn = true
    /// Nights in the window, by date, with their place in their run.
    @State private var runNights: [String: NightRunNight] = [:]
    @State private var capPercent = NightRunStore.defaultCapPercent
    @State private var choosing: SavedShiftPattern?
    @State private var editingRunLength: SavedShiftPattern?
    @State private var runLengthText = ""
    @State private var addingShifts = false
    @State private var error: String?

    private let timeModel = TimeModel(timeZone: .current)
    /// Days before today the window starts, which is also the index of today.
    private static let daysBefore = 6
    private static let daysAfter = 7

    private var hasShifts: Bool { days.contains { $0.shiftType != nil } }

    var body: some View {
        List {
            if hasShifts {
                Section {
                    ForEach(Array(days.enumerated()), id: \.element.date) { index, context in
                        dayRow(context, offset: index - Self.daysBefore)
                    }
                } header: {
                    AlmanacSectionHeader(title: String(localized: "Your days"))
                } footer: {
                    Text("A day with no shift entered says nothing about your rhythm.")
                }
            } else {
                emptyState
            }
            if !patterns.isEmpty {
                patternsSection
            }
            if hasShifts || !patterns.isEmpty {
                nightReadinessSection
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Shifts & rhythm")
        .toolbar {
            if hasShifts {
                ToolbarItem(placement: .primaryAction) {
                    Button { addingShifts = true } label: {
                        Label("Add shifts", systemImage: "plus")
                    }
                    .accessibilityIdentifier("circadian-add-shifts")
                }
            }
        }
        .task { reload() }
        .sheet(isPresented: $addingShifts) {
            ShiftEditorView(db: db) {
                reload()
                Task { await notificationModel?.reconcileNotifications() }
            }
        }
        .confirmationDialog(choosing?.name ?? "", isPresented: Binding(
            get: { choosing != nil }, set: { if !$0 { choosing = nil } }
        ), titleVisibility: .visible, presenting: choosing) { pattern in
            if selection.currentId != pattern.id {
                Button("Use now") { act { try $0.use(pattern.id, today: today) } }
                if selection.nextId == pattern.id {
                    Button("Don't run next") { act { try $0.setNext(nil, today: today) } }
                } else {
                    Button("Run next") { act { try $0.setNext(pattern.id, today: today) } }
                }
            }
            Button("Set run length") {
                runLengthText = pattern.runLengthNights.map(String.init) ?? ""
                editingRunLength = pattern
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Run length", isPresented: Binding(
            get: { editingRunLength != nil }, set: { if !$0 { editingRunLength = nil } }
        ), presenting: editingRunLength) { pattern in
            TextField("Nights", text: $runLengthText)
                .keyboardType(.numberPad)
            Button("Save") {
                act { try $0.setRunLength(Int(NumberInput.ascii(runLengthText)), for: pattern.id) }
            }
            Button("Use the default") { act { try $0.setRunLength(nil, for: pattern.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("A run of night shifts longer than this is warned about. With none set, it is 3 nights.")
        }
        .editorError($error)
    }

    // MARK: - Saved patterns

    private var patternsSection: some View {
        Section {
            ForEach(patterns) { pattern in
                Button { choosing = pattern } label: { patternRow(pattern) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("saved-pattern-\(pattern.name)")
            }
            if selection.currentId != nil {
                Toggle(isOn: Binding(get: { reminderOn }, set: setReminder)) {
                    Text("Remind me before it starts again")
                        .font(AlmanacTypography.font(.body))
                }
                .accessibilityIdentifier("saved-pattern-reminder")
            }
        } header: {
            AlmanacSectionHeader(title: String(localized: "Saved patterns"))
        } footer: {
            Text(reminderOn
                 ? "The evening before a week or month ends, Almanac asks you to pick what runs next. Until you pick, the running pattern keeps going."
                 : "With the reminder off, the pattern you set as next starts when the week or month ends. With none set, the running pattern keeps going.")
        }
    }

    /// The cap applies to manually entered shifts and rotations too.
    private var nightReadinessSection: some View {
        Section {
            Stepper(value: Binding(get: { capPercent }, set: setCap), in: 1...50, step: 1) {
                Text("Most a run of nights takes off readiness: \(Int(capPercent))%")
                    .font(AlmanacTypography.font(.body))
            }
            .accessibilityIdentifier("saved-pattern-cap")
        }
    }

    private func patternRow(_ pattern: SavedShiftPattern) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pattern.name)
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text(summary(pattern))
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pattern.runLengthNights.map { String(localized: "Warns after \($0) nights") }
                     ?? String(localized: "Warns after 3 nights (the default)"))
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                if selection.currentId == pattern.id, let next = nextPeriodStart {
                    Text("Starts again \(dateText(next))")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else if selection.nextId == pattern.id, let starts = selection.nextStartsOn {
                    Text("Starts \(dateText(starts))")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            Spacer()
            if let status = status(of: pattern) {
                Text(status)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .accessibilityIdentifier("saved-pattern-status-\(pattern.name)")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func status(of pattern: SavedShiftPattern) -> String? {
        if selection.currentId == pattern.id { return String(localized: "Running") }
        if selection.nextId == pattern.id { return String(localized: "Next") }
        return nil
    }

    /// "5 × Day shift, 2 × Rest day · every week from Wed 21 Oct".
    private func summary(_ pattern: SavedShiftPattern) -> String {
        let blocks = pattern.blocks
            .map { String(localized: "\($0.days) × \(ShiftPresentation.title(for: $0.shift))") }
            .joined(separator: String(localized: ", "))
        let from = dateText(pattern.startDate)
        switch pattern.cadence {
        case .weekly: return String(localized: "\(blocks) · every week from \(from)")
        case .monthly: return String(localized: "\(blocks) · every month from \(from)")
        }
    }

    private var today: LogicalDay { timeModel.logicalDay(Date()) }

    private func act(_ change: (SavedShiftPatternStore) throws -> Void) {
        do {
            try change(SavedShiftPatternStore(db: db, timeModel: timeModel))
            reload()
            Task { await notificationModel?.reconcileNotifications() }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func setCap(_ percent: Double) {
        do {
            try NightRunStore(db: db, timeModel: timeModel).setCapPercent(percent)
            capPercent = percent
        } catch {
            self.error = String(describing: error)
        }
    }

    private func setReminder(_ on: Bool) {
        do {
            try SavedShiftPatternStore(db: db, timeModel: timeModel).setReminder(on, today: today)
            reload()
            Task { await notificationModel?.reconcileNotifications() }
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("No shifts entered yet")
                    .font(AlmanacTypography.font(.sectionTitle))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text("Almanac describes your rhythm only from the shifts you enter. If you do not work shifts, there is nothing to do here.")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { addingShifts = true } label: {
                    Label("Add shifts", systemImage: "plus")
                }
                .accessibilityIdentifier("circadian-add-shifts")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Rows

    private func dayRow(_ context: CircadianContext, offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateText(context.date, offset: offset))
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer()
                Text(context.shiftType.map(ShiftPresentation.title(for:)) ?? String(localized: "No shift"))
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(context.shiftType == nil
                                     ? AlmanacPalette.textSecondary : AlmanacPalette.textPrimary)
                    .accessibilityIdentifier("circadian-shift-\(offset)")
            }
            if let run = runNights[context.date.value], run.isPastRunLength {
                Text("Night \(run.night) in a row: past your run length of \(run.runLengthNights).")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("circadian-run-warning-\(offset)")
            }
            if let planned = patternNotes[context.date.value] {
                Text("Pattern: \(ShiftPresentation.title(for: planned))")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .accessibilityIdentifier("circadian-pattern-note-\(offset)")
            }
            if let line = CircadianPresentation.line(for: context.contextType,
                                                     transitionDayN: context.transitionDayN) {
                Text(line)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("circadian-line-\(offset)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// "Today", or the weekday and date. The date is the day's start instant in
    /// the app's Gregorian display calendar, so an Arabic phone on Umm al-Qura
    /// still names the month the data is filed under (docs/features/arabic.md).
    private func dateText(_ day: LogicalDay, offset: Int) -> String {
        if offset == 0 { return String(localized: "Today") }
        return dateText(day)
    }

    private func dateText(_ day: LogicalDay) -> String {
        guard let start = timeModel.start(of: day) else { return day.value }
        return start.formatted(.almanacDateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Loading

    private func reload() {
        do {
            let today = timeModel.logicalDay(Date())
            let saved = SavedShiftPatternStore(db: db, timeModel: timeModel)
            try saved.refresh(today: today)
            let first = step(today, by: -Self.daysBefore)
            let last = step(today, by: Self.daysAfter)
            days = try CircadianTimeline(db: db, timeModel: timeModel).days(from: first, through: last)
            let shifts = ShiftScheduleStore(db: db)
            patternNotes = try days.reduce(into: [:]) { notes, context in
                if let planned = SavedShiftPatternNote.shift(in: try shifts.occurrence(for: context.date.value)?.notes) {
                    notes[context.date.value] = planned
                }
            }
            patterns = try saved.patterns()
            selection = try saved.selection()
            nextPeriodStart = try saved.nextPeriodStart(after: today)
            reminderOn = try NotificationRuleStore(db: db).isEnabled(.shiftPattern)
            let runs = NightRunStore(db: db, timeModel: timeModel)
            runNights = Dictionary(uniqueKeysWithValues: try runs.nights(from: first, through: last)
                .map { ($0.day.value, $0) })
            capPercent = try runs.capPercent()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func step(_ day: LogicalDay, by count: Int) -> LogicalDay {
        var result = day
        for _ in 0..<abs(count) {
            result = (count < 0 ? timeModel.day(before: result) : timeModel.day(after: result)) ?? result
        }
        return result
    }
}
