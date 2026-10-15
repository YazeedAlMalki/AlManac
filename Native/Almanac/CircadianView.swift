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
@MainActor
struct CircadianView: View {
    let db: Database

    @State private var days: [CircadianContext] = []
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
            ShiftEditorView(db: db) { reload() }
        }
        .editorError($error)
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
        guard let start = timeModel.start(of: day) else { return day.value }
        return start.formatted(.almanacDateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Loading

    private func reload() {
        do {
            let today = timeModel.logicalDay(Date())
            let first = step(today, by: -Self.daysBefore)
            let last = step(today, by: Self.daysAfter)
            days = try CircadianTimeline(db: db, timeModel: timeModel).days(from: first, through: last)
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
