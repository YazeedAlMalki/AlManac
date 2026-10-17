import SwiftUI
import AlmanacCore
import Foundation

/// Enter a shift: one day, or a rotation that repeats.
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
@MainActor
struct ShiftEditorView: View {
    let db: Database
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case oneDay, rotation
        var id: String { rawValue }
        var title: String {
            switch self {
            case .oneDay: return String(localized: "One day")
            case .rotation: return String(localized: "Rotation")
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
                try store.logOccurrence(ShiftOccurrenceDraft(
                    scheduleId: scheduleId, date: start.value, shiftType: shift, isManualOverride: true))
            case .rotation:
                let end = LogicalDay(calendarDayOf: until, in: timeZone)
                guard end >= start else {
                    error = String(localized: "The end date is before the start date.")
                    return
                }
                try store.applyPattern(
                    ShiftRecurrencePatternDraft(scheduleId: scheduleId, shifts: sequence, startDate: start.value),
                    through: end, timeModel: TimeModel(timeZone: timeZone))
            }
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
