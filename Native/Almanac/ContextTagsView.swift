import SwiftUI
import AlmanacCore
import Foundation

/// Context tags: the things that explain a reading.
///
/// Nothing here measures anything, so the screen has **no prominent card**.
/// Doctrine rule 2 allows exactly one per screen and reserves it for the object
/// the screen is about; a filled panel wrapping a list of tags would be spending
/// the emphasis on decoration, and the accent is not available either — Almanac
/// recorded no measurement on this screen. So it is ruled sections and text.
///
/// The editing rule worth stating: **a day is edited, not appended to.**
/// `context_event.date` has no unique index, so `log` can put a second row on
/// the same day, and `event(for:)` returns only the first — a screen that
/// inserted unconditionally would silently hide half of what the user just
/// told it. So saving updates the day's existing row when there is one and
/// inserts only when there is not. The store's tolerance of two rows for one day is still a real
/// ambiguity, recorded in `docs/features/body-composition.md`; the UI resolves it
/// rather than inheriting it.
@MainActor
struct ContextTagsView: View {
    let db: Database
    @ObservedObject var trackingModel: TrackingCalendarModel

    @State private var day = ""
    @State private var events: [ContextEvent] = []
    @State private var selected: Set<ContextTag> = []
    @State private var notes = ""
    @State private var loadedForDay = ""
    @State private var error: String?
    @State private var readProblem: String?

    private let timeModel = TimeModel(timeZone: .current)
    private static let historyDayCount = 30

    private var canSave: Bool {
        !selected.isEmpty || !(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            Section {
                dayPicker
            }

            Section {
                if selected.isEmpty && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing recorded for this day.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
                tagGrid
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                Button(hasUnsavedChanges ? String(localized: "Save for \(displayDay)") : String(localized: "Saved"), action: save)
                    .disabled(!hasUnsavedChanges)
                    .accessibilityIdentifier("context-tags-save")
            } header: {
                AlmanacSectionHeader(title: String(localized: "What happened"))
            } footer: {
                Text("Tags are the confounders a readiness or correlation reading cannot explain on its own.")
            }

            if !events.isEmpty {
                Section {
                    ForEach(events) { event in
                        historyRow(event)
                    }
                } header: {
                    AlmanacSectionHeader(title: String(localized: "Earlier"), detail: "last \(Self.historyDayCount) days")
                }
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Context")
        .task { load(day: timeModel.logicalDay(Date()).value) }
        .onChange(of: day) { _, newValue in load(day: newValue) }
        .editorError($error)
    }

    private var dayPicker: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: AlmanacIcon.previous)
                    .frame(minHeight: AlmanacMetrics.minimumControl)
            }
            .accessibilityIdentifier("context-day-previous")
            Spacer()
            VStack(spacing: 2) {
                Text(displayDay)
                    .font(AlmanacTypography.font(.bodyMedium))
                    .monospacedDigit()
                Text(relativeLabel)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Spacer()
            Button { step(1) } label: {
                Image(systemName: AlmanacIcon.next)
                    .frame(minHeight: AlmanacMetrics.minimumControl)
            }
            .accessibilityIdentifier("context-day-next")
            .disabled(isToday)
        }
        .buttonStyle(.plain)
    }

    /// A wrapping grid of the ten known tags.
    ///
    /// Two columns rather than a `List` section per tag, because ten stacked
    /// rows would bury the notes field and the save button — and the whole point
    /// of tagging is to do several at once. A short final row is left half
    /// width rather than stretched, so a lone tag does not read as a section of
    /// its own.
    private var tagGrid: some View {
        let pairs = ContextTag.allCases.chunked(into: 2)
        return VStack(spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(pair) { tag in tagButton(tag) }
                    if pair.count == 1 { Spacer(minLength: 0) }
                }
            }
        }
    }

    private func tagButton(_ tag: ContextTag) -> some View {
        let isOn = selected.contains(tag)
        return Button {
            if isOn { selected.remove(tag) } else { selected.insert(tag) }
        } label: {
            Text(tag.title)
                .font(AlmanacTypography.font(.label))
                .foregroundStyle(isOn ? AlmanacPalette.onAccent : AlmanacPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumControl)
                .padding(.horizontal, 10)
                .background(isOn ? AlmanacPalette.accent : AlmanacPalette.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("context-tag-\(tag.rawValue)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func historyRow(_ event: ContextEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.date)
                    .font(AlmanacTypography.font(.body))
                    .monospacedDigit()
                Spacer(minLength: 12)
                if !event.tags.isEmpty {
                    Text("\(event.tags.count) tags")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            if !event.tags.isEmpty {
                Text(event.tags.map { ContextTag(rawValue: $0)?.title ?? readable($0) }
                    .joined(separator: " · "))
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = event.notes, !note.isEmpty {
                Text(note)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: AlmanacMetrics.minimumControl, alignment: .leading)
    }

    // MARK: - Day handling

    /// Whether the day's stored state differs from what is on screen.
    ///
    /// The button is keyed to this rather than to "is there anything to write",
    /// because those are not the same condition and conflating them costs the
    /// user the ability to *clear* a day: a day that had `illness` on it has
    /// something to write when the tag is cleared, and an `isEmpty`-style guard
    /// would disable the one control that could record that.
    private var hasUnsavedChanges: Bool {
        let existing = events.first { $0.date == day }
        let existingTags = Set(existing?.tags.compactMap(ContextTag.init(rawValue:)) ?? [])
        let existingNotes = existing?.notes ?? ""
        return existingTags != selected || existingNotes != notes
    }

    private func save() {
        let cleanNotes = optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let store = ContextEventStore(db: db)
            if let existing = events.first(where: { $0.date == day }) {
                try store.updateTags(id: existing.id, to: selected.map(\.rawValue).sorted())
                try store.updateNotes(id: existing.id, to: cleanNotes)
            } else {
                // Nothing stored for this day, so this is a create. It needs
                // something to record — an empty row is not a fact about the day.
                guard canSave else {
                    error = String(localized: "Add a tag or a note before saving.")
                    return
                }
                _ = try store.log(ContextEventDraft(date: day, tags: selected.map(\.rawValue).sorted(),
                                                    notes: cleanNotes))
            }
            load(day: day)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func step(_ delta: Int) {
        let current = LogicalDay(day)
        let next = delta < 0 ? timeModel.day(before: current) : timeModel.day(after: current)
        guard let next else { return }
        day = next.value
    }

    private var isToday: Bool { day == timeModel.logicalDay(Date()).value }

    /// The day's label, formatted for reading, with the stored string as the
    /// fallback so an unreadable day is shown as itself rather than as nothing.
    private var displayDay: String {
        guard let date = LogicalDay(day).dayStart else { return day }
        return date.almanacFormatted(date: .abbreviated, time: .omitted)
    }

    private var relativeLabel: String {
        if isToday { return String(localized: "Today") }
        if let yesterday = timeModel.day(before: timeModel.logicalDay(Date()))?.value, day == yesterday {
            return String(localized: "Yesterday")
        }
        return String(localized: "Logical day")
    }

    private func load(day newDay: String) {
        day = newDay
        do {
            let store = ContextEventStore(db: db)
            let today = timeModel.logicalDay(Date())
            let start = (0..<(Self.historyDayCount - 1)).reduce(today) { acc, _ in
                timeModel.day(before: acc) ?? acc
            }
            let end = timeModel.day(after: today)?.value ?? today.value
            events = try store.events(from: start.value, to: end)

            let existing = events.first { $0.date == newDay }
            selected = Set(existing?.tags.compactMap(ContextTag.init(rawValue:)) ?? [])
            notes = existing?.notes ?? ""
            loadedForDay = newDay
            readProblem = nil
        } catch {
            self.error = String(describing: error)
            readProblem = String(localized: "Could not read your context tags.")
        }
    }
}

private extension LogicalDay {
    /// The day's 04:00 instant in the current zone, for display only. The stored
    /// value stays the label — nothing here is written back, the same rule
    /// `PartialDateTime.span` follows.
    var dayStart: Date? {
        TimeModel(timeZone: .current).bounds(of: self)?.start
    }
}

private extension Array {
    /// Rows of `size`, the last one short if the count does not divide.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
