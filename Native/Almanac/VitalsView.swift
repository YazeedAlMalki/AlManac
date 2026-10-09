import SwiftUI
import AlmanacCore

/// The two vitals a readiness score is made of, entered by hand when nothing else
/// can supply them.
///
/// BRD §6.7 promises resting HR, HRV, steps and active energy arrive "imported
/// (HealthKit-authoritative, Section 5.2) with **manual fallback**". Until now
/// the fallback did not exist: `vitals_record` had exactly one writer, the
/// HealthKit bridge, so a person without a watch — or one who declined the HRV
/// permission §5.2's own scenario names — could never produce a readiness score
/// at all. `ReadinessEngine` yields `score: nil` when duration, stages and both
/// heart-rate terms are missing, and that is what left checklist rows 7.10 and
/// 7.11 undrivable.
///
/// **Only resting HR and HRV, and only because those are the two the score
/// weighs.** `ReadinessFormula` has no term for steps or active energy; offering
/// a field for them here would be a control with nothing on the other side of
/// it. The screen says so in its own footer rather than leaving the absence to
/// be discovered.
///
/// **No model object.** `BodyCircumferenceView` and `SupplementView` both drive
/// their store straight from the view and reload afterwards, and the one thing
/// this screen needs beyond that — `readinessModel.refresh()` so today's score
/// reflects the reading just saved — is a call on an observed object it already
/// holds. A `VitalsModel` would have been a third copy of the same six lines.
@MainActor
struct VitalsView: View {
    let db: Database
    /// Recomputed after every save and deletion. Without it the readiness card
    /// keeps showing the score the engine worked out *before* the reading
    /// existed, which is the one thing a person entering a number is watching for.
    @ObservedObject var readinessModel: ReadinessModel
    /// Read for `lastSynced` only, so the day re-reads after a sync brings in a
    /// reading from Apple Health. Nothing here writes anything HealthKit owns.
    @ObservedObject var healthModel: HealthModel

    /// The newest reading of each metric inside today's logical day, whatever its
    /// source. Read through `latestValue(for:since:)` rather than by asking the
    /// store for the whole table's newest row, so a reading from yesterday is
    /// not presented as today's.
    @State private var today: [VitalsMetric: VitalsRecord] = [:]
    /// Hand-entered and synced readings from the last fortnight, newest first.
    @State private var history: [VitalsRecord] = []
    @State private var adding = false
    @State private var editing: VitalsRecord?
    @State private var error: String?
    @State private var readProblem: String?

    /// Days in the log, today included. A logbook, not an analytics screen —
    /// same bound `SupplementView` uses, and for the same reason.
    private static let historyDayCount = 14

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            Section {
                AlmanacCard(prominent: true) { todayCard }
            }

            Section {
                Button("Log a reading", systemImage: AlmanacIcon.quickAdd) { adding = true }
                    .accessibilityIdentifier("vitals-log")
            } footer: {
                Text("Resting heart rate and HRV are the two readings a readiness score is made of. Steps and active energy are not scored, so Almanac does not ask for them by hand.")
            }

            Section {
                if history.isEmpty {
                    Text("No readings recorded yet.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(history) { record in
                        historyRow(record)
                    }
                }
            } header: {
                AlmanacSectionHeader(title: String(localized: "Recent readings"))
            } footer: {
                Text(historyFooter)
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Vitals")
        .task { reload() }
        .onChange(of: healthModel.lastSynced) { _, _ in reload() }
        .sheet(isPresented: $adding) {
            VitalsEntryEditor(db: db, record: nil, onSaved: saved)
        }
        .sheet(item: $editing) { record in
            VitalsEntryEditor(db: db, record: record, onSaved: saved)
        }
        .editorError($error)
    }

    // MARK: - Today's readings

    private var todayCard: some View {
        VStack(spacing: 0) {
            ForEach(VitalsMetric.allCases, id: \.self) { metric in
                if metric != VitalsMetric.allCases.first {
                    AlmanacRule(inset: AlmanacRule.metricTextInset)
                }
                row(for: metric)
            }
        }
    }

    private func row(for metric: VitalsMetric) -> some View {
        AlmanacMetricRow(
            icon: AlmanacIcon.vitals,
            title: metric.displayName,
            // An em dash, not a zero. Doctrine rule 10, and the whole reason this
            // screen exists: a person who has not measured anything and a person
            // who measured zero are different facts, and only one of them is a
            // reading.
            value: today[metric].map { String(localized: "\(AlmanacNumber.compact($0.value)) \(UnitDisplay.localized(metric.unit))") } ?? "—",
            detail: detail(for: metric),
            tone: today[metric] == nil ? .neutral : nil
        )
        // One row, one element. Without this the identifier lands on each of the
        // three texts separately, so a query for today's resting rate matches
        // three elements and raises instead of answering — and VoiceOver reads
        // the title, the value and the provenance as three stops on one row.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(todayIdentifier(metric))
    }

    private func detail(for metric: VitalsMetric) -> String {
        guard let record = today[metric] else { return String(localized: "Not entered") }
        let time = record.timestamp.formatted(date: .omitted, time: .shortened)
        return record.source == VitalsRecordStore.manualSource
            ? String(localized: "Entered at \(time)")
            : String(localized: "From Apple Health at \(time)")
    }

    /// Stable per metric so a UI test can read today's resting rate without
    /// depending on the wording of the detail line beside it — the same reason
    /// `UIScrollSupport.staticText(beginningWith:)` matches on a prefix.
    private func todayIdentifier(_ metric: VitalsMetric) -> String {
        metric == .restingHeartRate ? "vitals-today-rhr" : "vitals-today-hrv"
    }

    // MARK: - Recent readings

    private func historyRow(_ record: VitalsRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(AlmanacNumber.compact(record.value)) \(UnitDisplay.localized(unit(for: record.metric)))")
                .font(AlmanacTypography.font(.body).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text(verbatim: "\(name(for: record.metric)) · \(LogicalDay(record.logicalDay).displayText) · \(timeLabel(record))")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        // On the combined element, so a test can count and swipe readings
        // without matching the two lines of copy a row is made of. Prefixed with
        // the row's id rather than a constant so "the next reading" is a query
        // rather than an index into a list that shrinks under the test.
        .accessibilityIdentifier("vitals-reading-\(record.id)")
        .swipeActions {
            // Only what was typed here. A synced reading is retracted by
            // correcting it in Apple Health, and the store refuses anyway — the
            // buttons are simply not offered, so the screen does not advertise an
            // action it would reject.
            if record.source == VitalsRecordStore.manualSource {
                Button("Delete", role: .destructive) { delete(record) }
                    .accessibilityIdentifier("vitals-delete")
                Button("Edit") { editing = record }
                    .accessibilityIdentifier("vitals-edit")
            }
        }
        .contextMenu {
            if record.source == VitalsRecordStore.manualSource {
                Button("Edit") { editing = record }
                Button("Delete", role: .destructive) { delete(record) }
            }
        }
    }

    private var historyFooter: String {
        history.contains { $0.source == VitalsRecordStore.manualSource }
            ? String(localized: "Readings you type in can be corrected or removed here. Readings from Apple Health are corrected in Apple Health.")
            : String(localized: "Readings from Apple Health are corrected in Apple Health.")
    }

    private func name(for metric: String) -> String {
        VitalsMetric(rawValue: metric)?.displayName ?? metric
    }

    private func unit(for metric: String) -> String {
        VitalsMetric(rawValue: metric)?.unit ?? ""
    }

    private func timeLabel(_ record: VitalsRecord) -> String {
        record.source == VitalsRecordStore.manualSource ? String(localized: "entered by hand") : "Apple Health"
    }

    // MARK: - Data

    private func reload() {
        let store = VitalsRecordStore(db: db)
        let model = TimeModel(timeZone: .current)
        let today = model.logicalDay(Date())
        let todayStart = model.start(of: today)
        do {
            var readings: [VitalsMetric: VitalsRecord] = [:]
            for metric in VitalsMetric.allCases {
                // Bounded to today for the same reason the dashboard bounds it to
                // the scored cycle: "the newest row in the table" is not the same
                // question as "what did I measure today", and the first entry in
                // this screen is often back-dated.
                if let start = todayStart {
                    readings[metric] = try store.latestValue(for: metric, since: start)
                }
            }
            // Today included: the log is where a hand-entered reading is
            // corrected or deleted, and today's card offers neither. See
            // `VitalsRecordStore.log` for the half-open bound this replaced.
            self.history = try store.log(metrics: VitalsMetric.allCases, dayCount: Self.historyDayCount,
                                         endingOn: today, timeModel: model, limit: 40)
            self.today = readings
            readProblem = nil
        } catch {
            // Distinct from an empty list, and left beside it rather than
            // replacing it: "nothing recorded" and "could not read" are different
            // claims (see `AlmanacProblemNote`).
            self.readProblem = String(localized: "Could not read your vitals log. Figures below may be out of date.")
        }
    }

    private func saved() {
        reload()
        readinessModel.refresh()
    }

    private func delete(_ record: VitalsRecord) {
        do {
            try VitalsRecordStore(db: db).delete(id: record.id)
            saved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One reading, entered or corrected.
///
/// The metric picker is absent when correcting: `VitalsRecordStore.update` moves
/// the value and nothing else, so offering the control would suggest a change
/// that silently does not happen. The "Measured at" picker is absent for the same
/// reason — the instant is part of the reading, not part of its value.
@MainActor
private struct VitalsEntryEditor: View {
    let db: Database
    let record: VitalsRecord?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metric = VitalsMetric.restingHeartRate
    @State private var value = ""
    @State private var measuredAt = Date()
    @State private var error: String?
    @State private var confirmUnusual = false
    @State private var loaded = false

    private var isCorrection: Bool { record != nil }

    /// The metric being corrected, which the picker would otherwise be needed to
    /// recover from the row's `metric` string.
    private var metricBeingEdited: VitalsMetric {
        guard let record else { return metric }
        return VitalsMetric(rawValue: record.metric) ?? metric
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCorrection {
                    Text(metricBeingEdited.displayName)
                        .font(AlmanacTypography.font(.bodyMedium))
                    // The correction is a new number for the same instant and the
                    // same metric. Saying so is what stops "correct" from being
                    // read as "replace this reading with another one".
                    Text("A correction changes the number only. The reading stays on \(LogicalDay(record!.logicalDay).displayText) at \(record!.timestamp.formatted(date: .omitted, time: .shortened)).")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    Picker("Measurement", selection: $metric) {
                        ForEach(VitalsMetric.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .accessibilityIdentifier("vitals-metric")
                    DatePicker("Measured at", selection: $measuredAt)
                        .accessibilityIdentifier("vitals-measured-at")
                }
                TextField("\(metricBeingEdited.displayName) (\(metricBeingEdited.unit))", text: $value)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("vitals-value")
            }
            .navigationTitle(isCorrection ? String(localized: "Correct reading") : String(localized: "Log a reading"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!loaded)
                }
            }
            .task {
                guard !loaded else { return }
                if let record {
                    value = record.value.formatted(.number.grouping(.never))
                }
                loaded = true
            }
            .alert("That looks unusually low or high", isPresented: $confirmUnusual) {
                // The bound is a typo guard, not a clinical range — so the alert
                // quotes no range, and the escape hatch is a real one rather than
                // a formality. A deliberate reading is never blocked by a number
                // this repository invented.
                Button("Save anyway") { save(allowUnusual: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Check the number and that it is in \(metricBeingEdited.unit).")
            }
            .editorError($error)
        }
    }

    private func save(allowUnusual: Bool = false) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(userInput: trimmed)
                ?? (try? Double(trimmed, format: .number, lenient: false)) else {
            error = VitalsEntryError.invalidValue(metricBeingEdited).localizedDescription
            return
        }
        do {
            let store = VitalsRecordStore(db: db)
            if let record {
                try store.update(id: record.id, value: number, allowUnusualValue: allowUnusual)
            } else {
                try store.recordManual(metric: metric, value: number, measuredAt: measuredAt,
                                      allowUnusualValue: allowUnusual)
            }
            onSaved()
            dismiss()
        } catch VitalsEntryError.unusuallySized {
            confirmUnusual = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
