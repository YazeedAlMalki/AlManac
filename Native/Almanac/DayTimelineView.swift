import SwiftUI
import AlmanacCore
import Foundation

/// Everything recorded, in the order it happened.
///
/// This is the reading surface the timeline type was built for and never had.
/// `TrackingTimeline` was reachable only from the Activity Rings day editor,
/// which is a *correction* surface — a place to fix a value, not a place to
/// read a day back. `Timeline` itself, the generic merge type, had no consumer at
/// all: every screen assembled its own list by hand, which is why Today's record
/// names four domains and knows nothing about the other eight.
///
/// **Ruled rows, not cards.** There is no single object here to be prominent
/// about — the day is the object, and it is the heading. One prominent card
/// would be spent on decoration (doctrine rule 2).
///
/// **Nothing here is grouped by domain.** The merge type's whole argument is one
/// total order over occurrence time, and grouping by module would throw that
/// away in favour of a list that reads like the hand-rolled ones it replaces.
/// A day reads as a day, not as twelve sections.
@MainActor
struct DayTimelineView: View {
    let db: Database?
    /// Days back from today to show. One is Today; a week is the reading
    /// surface's reason for existing over a single day.
    ///
    /// A `State` rather than a `let` because the screen offers the choice itself
    /// — a period picker whose selection could not change would be a control
    /// that lies.
    @State private var dayCount: Int

    @State private var items: [TrackingTimelineItem] = []
    @State private var anchor: LogicalDay = LogicalDay("")
    @State private var error: String?
    @State private var readProblem: String?

    private let timeModel = TimeModel(timeZone: .current)

    init(db: Database?, dayCount: Int = 1) {
        self.db = db
        _dayCount = State(initialValue: max(1, dayCount))
    }

    /// The exclusive end of the range: `dayCount` logical days after the anchor,
    /// walked through `TimeModel` so the 04:00 boundary is applied between them.
    private var rangeEnd: String {
        var cursor = anchor
        for _ in 0..<dayCount {
            guard let next = timeModel.day(after: cursor) else { return cursor.value }
            cursor = next
        }
        return cursor.value
    }

    private var title: String {
        dayCount == 1 ? String(localized: "Recorded") : String(localized: "Last \(dayCount) days")
    }

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            Section {
                if items.isEmpty {
                    Text("Nothing recorded in this period.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            } header: {
                AlmanacSectionHeader(
                    title: title,
                    detail: dayCount == 1 ? anchor.value : "\(anchor.value) → \(rangeEnd)"
                )
            } footer: {
                Text("In the order it happened, by time of day. Days begin at 04:00, so a 03:00 entry belongs to the night before.")
            }

            Section {
                Picker("Period", selection: $dayCount) {
                    Text("Today").tag(1)
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                }
                .accessibilityIdentifier("timeline-period")
            } footer: {
                Text("The day range is exclusive of its end, so an entry at the boundary is never counted twice.")
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Timeline")
        .task {
            if anchor.value.isEmpty { anchor = timeModel.logicalDay(Date()) }
            reload()
        }
        .onChange(of: dayCount) { _, _ in reload() }
        .editorError($error)
    }

    /// One entry. Time on the left in a fixed column so the readings line up and
    /// the eye can scan down the times rather than hunting for them.
    private func row(_ item: TrackingTimelineItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(time(for: item))
                .font(AlmanacTypography.font(.data).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textSecondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            if let value = item.value {
                Text(value)
                    .font(AlmanacTypography.font(.data).monospacedDigit())
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .accessibilityElement(children: .combine)
    }

    /// The entry's time of day, or a dash.
    ///
    /// A dash means the placement is not an instant — the timeline's `.recorded`
    /// basis, or a day-precision fallback. That is a real placement and not a
    /// missing one, so it is marked rather than filled in.
    private func time(for item: TrackingTimelineItem) -> String {
        guard let at = item.occurredAt else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: at)
    }

    private func reload() {
        guard let db else { return }
        do {
            items = try TrackingTimeline(db: db).items(
                fromDay: anchor.value, toDay: rangeEnd, timeModel: timeModel)
            readProblem = nil
        } catch {
            self.error = String(describing: error)
            readProblem = "Could not read the timeline."
            items = []
        }
    }
}
