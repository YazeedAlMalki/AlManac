import SwiftUI
import AlmanacCore
import Foundation

/// Enter a shift: one day, a rotation that repeats, or a saved pattern.
///
/// This view decides nothing about shifts. It builds a draft and hands it to
/// `ShiftScheduleStore`, whose behaviour — a day the person changed by hand
/// keeping their change, a rotation that cannot be read leaving nothing behind —
/// is pinned by tests that do not need a screen.
///
/// **A one-day entry is a manual override; a rotation is not.** The first is
/// the person saying "this day, specifically" (BRD §6.11's "record unplanned
/// change"), so no rotation entered later may overwrite it. A rotation is a
/// rule, and a rule gives way to a specific day.
///
/// **A saved pattern sits beside the rotation.** It has a name and blocks of
/// days on one shift, and repeats every week or every month from its start
/// date until the person picks another (`SavedShiftPatternStore`).
@MainActor
struct ShiftEditorView: View {
    let db: Database
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case oneDay, rotation, pattern
        var id: String { rawValue }
        var title: String {
            switch self {
            case .oneDay: return String(localized: "One day")
            case .rotation: return String(localized: "Rotation")
            case .pattern: return String(localized: "Saved pattern")
            }
        }
    }

    @State private var mode = Mode.oneDay
    @State private var date = ShiftEditorView.openingDate()
    @State private var shift = ShiftType.day
    /// One entry per day, repeating. Starts as a single day shift so that
    /// "Rotation, Save" already means something: day shifts, every day.
    @State private var sequence: [ShiftType] = [.day]
    @State private var until = Calendar.current.date(byAdding: .day, value: 27, to: ShiftEditorView.openingDate()) ?? Date()
    @State private var patternName = ""
    /// A working week to start from, so the form opens on something real.
    @State private var blocks = [ShiftBlock(.day, days: 5), ShiftBlock(.rest, days: 2)]
    @State private var cadence = ShiftCadence.weekly
    /// On when no saved pattern is running: a first pattern is saved to be
    /// used. Off otherwise, because saving is not picking.
    @State private var startUsing = true
    @State private var error: String?

    /// The date the pickers open on: the calendar date of the person's *current
    /// logical day*, which is what the row labelled Today on the Shifts screen
    /// shows. Between midnight and 04:00 that is yesterday's date, and opening
    /// on `Date()` would file a shift entered "for today" under tomorrow.
    private static func openingDate() -> Date {
        let model = TimeModel(timeZone: .current)
        return model.start(of: model.logicalDay(Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("shift-editor-mode")
                }

                switch mode {
                case .oneDay: oneDaySection
                case .rotation: rotationSections
                case .pattern: patternSections
                }
            }
            .navigationTitle("Add shifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("shift-editor-save")
                }
            }
            .editorError($error)
            .task { startUsing = (try? SavedShiftPatternStore(db: db, timeModel: TimeModel(timeZone: .current))
                                    .selection().currentId) == nil }
        }
    }

    // MARK: - Sections

    private var oneDaySection: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            shiftPicker("Shift", selection: $shift)
                .accessibilityIdentifier("shift-editor-shift")
        }
    }

    @ViewBuilder
    private var rotationSections: some View {
        Section {
            ForEach(sequence.indices, id: \.self) { index in
                shiftPicker("Day \(index + 1)", selection: $sequence[index])
            }
            Button("Add a day") { sequence.append(.rest) }
            if sequence.count > 1 {
                Button("Remove last day", role: .destructive) { sequence.removeLast() }
            }
        } header: {
            AlmanacSectionHeader(title: String(localized: "Rotation"))
        }

        Section {
            DatePicker("Starts", selection: $date, displayedComponents: .date)
            DatePicker("Repeat until", selection: $until, displayedComponents: .date)
        } footer: {
            Text("The rotation repeats from the start date until the end date. A day you changed yourself keeps your change.")
        }
    }

    @ViewBuilder
    private var patternSections: some View {
        Section {
            TextField("Name", text: $patternName)
                .accessibilityIdentifier("shift-pattern-name")
        }

        Section {
            ForEach(blocks.indices, id: \.self) { index in
                shiftPicker("Block \(index + 1)", selection: $blocks[index].shift)
                Stepper(value: $blocks[index].days, in: 1...31) {
                    Text(blocks[index].days == 1 ? String(localized: "1 day") : String(localized: "\(blocks[index].days) days"))
                }
            }
            Button("Add a block") { blocks.append(ShiftBlock(.rest, days: 1)) }
            if blocks.count > 1 {
                Button("Remove last block", role: .destructive) { blocks.removeLast() }
            }
        } header: {
            AlmanacSectionHeader(title: String(localized: "Blocks"))
        }

        Section {
            Picker("Repeats", selection: $cadence) {
                Text("Every week").tag(ShiftCadence.weekly)
                Text("Every month").tag(ShiftCadence.monthly)
            }
            .pickerStyle(.segmented)
            DatePicker("Starts", selection: $date, displayedComponents: .date)
            Toggle("Start using it", isOn: $startUsing)
        } footer: {
            Text("The blocks repeat inside each week or month and start again from the first block when a new one begins. A day you change yourself keeps your change, and the pattern's shift is kept as a note.")
        }
    }

    private func shiftPicker(_ title: LocalizedStringKey, selection: Binding<ShiftType>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ShiftPresentation.options, id: \.self) { option in
                Text(ShiftPresentation.title(for: option)).tag(option)
            }
        }
    }

    // MARK: - Saving

    private func save() {
        let timeZone = TimeZone.current
        let store = ShiftScheduleStore(db: db)
        do {
            let scheduleId = try store.defaultScheduleId()
            let start = LogicalDay(calendarDayOf: date, in: timeZone)

            switch mode {
            case .oneDay:
                try store.logOneDay(scheduleId: scheduleId, date: start.value, shift: shift)
            case .rotation:
                let end = LogicalDay(calendarDayOf: until, in: timeZone)
                guard end >= start else {
                    error = String(localized: "The end date is before the start date.")
                    return
                }
                try store.applyPattern(
                    ShiftRecurrencePatternDraft(scheduleId: scheduleId, shifts: sequence, startDate: start.value),
                    through: end, timeModel: TimeModel(timeZone: timeZone))
            case .pattern:
                let timeModel = TimeModel(timeZone: timeZone)
                let patterns = SavedShiftPatternStore(db: db, timeModel: timeModel)
                let id = try patterns.save(SavedShiftPatternDraft(
                    name: patternName, blocks: blocks, startDate: start, cadence: cadence))
                if startUsing { try patterns.use(id, today: timeModel.logicalDay(Date())) }
            }
            onSaved()
            dismiss()
        } catch let failure as SavedShiftPatternError {
            self.error = Self.message(for: failure)
        } catch {
            self.error = String(describing: error)
        }
    }

    private static func message(for failure: SavedShiftPatternError) -> String {
        switch failure {
        case .missingName: return String(localized: "Give the pattern a name.")
        case .noBlocks, .blockWithNoDays: return String(localized: "Every block needs at least one day.")
        case .runLengthNotPositive: return String(localized: "The run length must be at least one night.")
        case .unknownPattern: return String(localized: "That pattern is no longer saved.")
        }
    }
}
