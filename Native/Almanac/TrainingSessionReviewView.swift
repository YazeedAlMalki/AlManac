import SwiftUI
import AlmanacCore
import Foundation

/// Past training sessions, and what was done in them.
///
/// Closes one of the three gaps `docs/features/training.md` §2 lists: the
/// Training screen showed *today* only, so there was nowhere to look at what
/// happened last Tuesday. Bouts are editable here, which closes the other gap —
/// until now today's screen could only delete one.
///
/// **Ruled rows, no prominent card.** A review of many days has no single object
/// to be prominent about, and a filled panel per session would make a long list
/// read as a stack of unrelated boxes. The period is the header.
///
/// **A HealthKit-derived session is read-only, and says so.** Its rows came from
/// a watch, not from the user, so editing them would write a number the source
/// will overwrite on the next sync. `WorkoutSessionEntry.isOwnLog` is the test
/// for that, and the row is labelled rather than silently inert.
@MainActor
struct TrainingSessionReviewView: View {
    let db: Database?
    @ObservedObject var model: TrainingModel

    @State private var days: [String] = []
    @State private var sessionsByDay: [String: [WorkoutSessionEntry]] = [:]
    @State private var boutsBySession: [Int64: [WorkoutBoutEntry]] = [:]
    @State private var templates: [Int64: String] = [:]
    @State private var period: Period = .thirtyDays
    @State private var editing: WorkoutBoutEntry?
    @State private var error: String?
    @State private var readProblem: String?

    private enum Period: Int, CaseIterable, Identifiable {
        case sevenDays, thirtyDays, ninetyDays
        var id: Int { rawValue }
        var dayCount: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }
        var title: String {
            switch self {
            case .sevenDays: return String(localized: "Last 7 days")
            case .thirtyDays: return String(localized: "Last 30 days")
            case .ninetyDays: return String(localized: "Last 90 days")
            }
        }
    }

    private let timeModel = TimeModel(timeZone: .current)

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            if days.isEmpty {
                Section {
                    Text("No sessions in this period.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }

            ForEach(days, id: \.self) { day in
                Section {
                    ForEach(sessionsByDay[day] ?? []) { session in
                        sessionSection(session)
                    }
                } header: {
                    AlmanacSectionHeader(title: day, detail: sessionCountLabel(for: day))
                }
            }

            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("training-review-period")
            } footer: {
                Text("Sessions auto-logged from Apple Health are shown but not editable — the watch is the source for those figures.")
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Training history")
        .task { reload() }
        .onChange(of: period) { _, _ in reload() }
        .sheet(item: $editing) { bout in
            BoutActualsEditor(db: db, bout: bout) { reload() }
        }
        .editorError($error)
    }

    // MARK: - Rows

    @ViewBuilder
    private func sessionSection(_ session: WorkoutSessionEntry) -> some View {
        let bouts = boutsBySession[session.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(sessionTitle(session))
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 10)
                if let minutes = session.durationMinutes {
                    Text("\(minutes) min")
                        .font(AlmanacTypography.font(.data).monospacedDigit())
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }

            if let template = session.prescribedWorkoutId.flatMap({ templates[$0] }) {
                Text("From template: \(template)")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            if !session.isOwnLog {
                Text("From Apple Health — read only.")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if bouts.isEmpty {
                Text("No bouts recorded.")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                ForEach(bouts) { bout in
                    boutRow(bout, editable: session.isOwnLog)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func boutRow(_ bout: WorkoutBoutEntry, editable: Bool) -> some View {
        let name = model.exerciseName(for: bout.exerciseCatalogId)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 10)
                Text(actualLabel(bout))
                    .font(AlmanacTypography.font(.data).monospacedDigit())
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            let kind = PrescriptionKind(rawValue: bout.prescriptionType)
            HStack(spacing: 6) {
                Text(kind?.displayName ?? readable(bout.prescriptionType))
                if let prescribed = prescribedLabel(bout) {
                    Text("·")
                    Text("prescribed \(prescribed)")
                }
                if let rpe = bout.rpe {
                    Text("·")
                    Text("RPE \(rpe)/10")
                }
            }
            .font(AlmanacTypography.font(.caption))
            .foregroundStyle(AlmanacPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .contentShape(Rectangle())
        .onTapGesture { if editable { editing = bout } }
        .accessibilityIdentifier("bout-row-\(bout.id)")
        .accessibilityHint(editable ? String(localized: "Opens this bout to correct what was actually done") : String(localized: "Read only"))
    }

    // MARK: - Labelling

    private func sessionTitle(_ session: WorkoutSessionEntry) -> String {
        if let type = session.sessionType { return readable(type) }
        if session.prescribedWorkoutId != nil { return String(localized: "Templated session") }
        return String(localized: "Training")
    }

    private func sessionCountLabel(for day: String) -> String? {
        guard let count = sessionsByDay[day]?.count, count > 1 else { return nil }
        return "\(count) sessions"
    }

    /// What was actually done, in the words its prescription type calls for.
    ///
    /// Only the groups the type records — a timed hold has no load in it, and
    /// printing "0 kg" beside one would be a number nobody lifted.
    private func actualLabel(_ bout: WorkoutBoutEntry) -> String {
        guard let kind = PrescriptionKind(rawValue: bout.prescriptionType) else {
            // An unrecognised type is a data problem, not an empty result. Says
            // so rather than printing nothing that reads as "did nothing".
            return String(localized: "Unrecognised type")
        }
        var parts: [String] = []
        if let sets = bout.actualSets { parts.append("\(sets)×") }
        if kind.recordsReps, let reps = bout.actualReps { parts.append("\(reps)") }
        if kind.recordsRounds, let rounds = bout.actualRounds { parts.append("\(rounds) rounds") }
        if kind.recordsLoad, let load = bout.actualLoadKg {
            parts.append("\(AlmanacNumber.compact(load)) kg")
        }
        if kind.recordsDuration, let seconds = bout.actualDurationSeconds {
            parts.append(durationLabel(seconds))
        }
        if kind.recordsDistance, let meters = bout.actualDistanceMeters {
            parts.append("\(AlmanacNumber.compact(meters)) m")
        }
        if parts.isEmpty { return String(localized: "Not recorded") }
        return parts.joined(separator: " ")
    }

    private func prescribedLabel(_ bout: WorkoutBoutEntry) -> String? {
        guard let kind = PrescriptionKind(rawValue: bout.prescriptionType) else { return nil }
        var parts: [String] = []
        if let sets = bout.prescribedSets { parts.append("\(sets)×") }
        if kind.recordsReps, let reps = bout.prescribedReps { parts.append("\(reps)") }
        if kind.recordsRounds, let rounds = bout.prescribedRounds { parts.append("\(rounds) rounds") }
        if kind.recordsLoad, let load = bout.prescribedLoadKg {
            parts.append("\(AlmanacNumber.compact(load)) kg")
        }
        if kind.recordsDuration, let seconds = bout.prescribedDurationSeconds {
            parts.append(durationLabel(seconds))
        }
        if kind.recordsDistance, let meters = bout.prescribedDistanceMeters {
            parts.append("\(AlmanacNumber.compact(meters)) m")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let rest = total % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes)m \(rest)s"
    }

    // MARK: - Load

    private func reload() {
        guard let db else { return }
        do {
            let end = timeModel.logicalDay(Date())
            let start = advance(end, by: -(period.dayCount - 1))
            let sessions = try WorkoutSessionStore(db: db).sessions(from: start.value, to: advance(end, by: 1).value)

            var byDay: [String: [WorkoutSessionEntry]] = [:]
            for session in sessions { byDay[session.date, default: []].append(session) }
            sessionsByDay = byDay
            days = byDay.keys.sorted(by: >)

            let boutStore = WorkoutBoutStore(db: db)
            var bouts: [Int64: [WorkoutBoutEntry]] = [:]
            for session in sessions {
                bouts[session.id] = try boutStore.bouts(sessionId: session.id)
            }
            boutsBySession = bouts

            // Read every template, including discontinued ones, because a past
            // session may name one — `templates()` lists only the live set.
            var names: [Int64: String] = [:]
            for session in sessions {
                guard let id = session.prescribedWorkoutId, names[id] == nil,
                      let template = try PrescribedWorkoutStore(db: db).workout(id: id) else { continue }
                names[id] = template.name
            }
            templates = names

            model.refresh()
            readProblem = nil
        } catch {
            self.error = String(describing: error)
            readProblem = String(localized: "Could not read your training history.")
            days = []
            sessionsByDay = [:]
            boutsBySession = [:]
        }
    }

    private func advance(_ day: LogicalDay, by amount: Int) -> LogicalDay {
        var cursor = day
        for _ in 0..<abs(amount) {
            let next = amount < 0 ? timeModel.day(before: cursor) : timeModel.day(after: cursor)
            guard let stepped = next else { return cursor }
            cursor = stepped
        }
        return cursor
    }
}

/// Corrects what was actually done in one bout.
///
/// The prescription fields are not on this form at all. They are what was
/// planned, and an editor that offered them would make "I had meant to do four
/// reps" indistinguishable from "I did four reps" — which is the distinction the
/// prescribed/actual split exists to keep.
@MainActor
private struct BoutActualsEditor: View {
    let db: Database?
    let bout: WorkoutBoutEntry
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sets = ""
    @State private var reps = ""
    @State private var loadKg = ""
    @State private var durationSeconds = ""
    @State private var distanceMeters = ""
    @State private var rounds = ""
    @State private var elapsedSeconds = ""
    @State private var avgHeartRate = ""
    @State private var rpe = ""
    @State private var notes = ""
    @State private var error: String?

    private var kind: PrescriptionKind? { PrescriptionKind(rawValue: bout.prescriptionType) }

    var body: some View {
        NavigationStack {
            Form {
                if kind == nil {
                    Section {
                        Text("This bout's prescription type (\(bout.prescriptionType)) is not one of the twelve this app knows, so the fields that belong to it cannot be shown. The row can still be given a note or deleted.")
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }

                if let kind {
                    Section {
                        if kind.recordsReps || bout.prescribedSets != nil {
                            numberField("Sets", text: $sets)
                        }
                        if kind.recordsReps {
                            numberField("Reps", text: $reps)
                        }
                        if kind.recordsRounds {
                            numberField("Rounds", text: $rounds)
                        }
                        if kind.recordsLoad {
                            numberField("Load (kg)", text: $loadKg)
                            numberField("Duration (seconds)", text: $durationSeconds)
                        }
                        if kind.recordsDistance {
                            numberField("Distance (m)", text: $distanceMeters)
                        }
                        if kind.recordsDuration && !kind.recordsLoad {
                            numberField("Duration (seconds)", text: $durationSeconds)
                        }
                    } header: {
                        AlmanacSectionHeader(title: String(localized: "What you did"))
                    } footer: {
                        // The nil rule stated where it is acted on, so a blank
                        // field reads as "not recorded" rather than as a bug.
                        Text("Leave a field blank to record it as not done. A blank is not a zero.")
                    }
                }

                Section("How it went") {
                    numberField("Elapsed (seconds)", text: $elapsedSeconds)
                    numberField("Average heart rate", text: $avgHeartRate)
                    numberField("RPE (1–10)", text: $rpe)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .almanacModuleSurface()
            .navigationTitle("Bout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(db == nil)
                }
            }
            .editorError($error)
            .onAppear(perform: load)
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
    }

    private func load() {
        sets = bout.actualSets.map(String.init) ?? ""
        reps = bout.actualReps.map(String.init) ?? ""
        loadKg = bout.actualLoadKg.map { AlmanacNumber.compact($0) } ?? ""
        durationSeconds = bout.actualDurationSeconds.map { AlmanacNumber.compact($0) } ?? ""
        distanceMeters = bout.actualDistanceMeters.map { AlmanacNumber.compact($0) } ?? ""
        rounds = bout.actualRounds.map(String.init) ?? ""
        elapsedSeconds = bout.elapsedSeconds.map { AlmanacNumber.compact($0) } ?? ""
        avgHeartRate = bout.avgHeartRate.map(String.init) ?? ""
        rpe = bout.rpe.map(String.init) ?? ""
        notes = bout.notes ?? ""
    }

    private func save() {
        guard let db else { return }
        // Validated up front, before anything is written. A field that fails to
        // parse must not become a silent nil: blanking a load by mistyping it
        // would erase a number that was there, and the only trace would be a
        // figure that quietly became "not recorded".
        let numbers: [(String, String, Bool)] = [
            (String(localized: "Sets"), sets, false), (String(localized: "Reps"), reps, false),
            (String(localized: "Rounds"), rounds, false), (String(localized: "Load"), loadKg, true),
            (String(localized: "Duration"), durationSeconds, true),
            (String(localized: "Distance"), distanceMeters, true), (String(localized: "Elapsed"), elapsedSeconds, true),
            (String(localized: "Average heart rate"), avgHeartRate, false), (String(localized: "RPE"), rpe, false)
        ]
        for (name, text, isDecimal) in numbers where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parses = isDecimal ? Double(userInput: trimmed) != nil : Int(userInput: trimmed) != nil
            guard parses else {
                error = isDecimal ? String(localized: "\(name) must be a number.")
                    : String(localized: "\(name) must be a whole number.")
                return
            }
        }
        if let rpeValue = int(rpe), !(1...10).contains(rpeValue) {
            error = String(localized: "RPE runs from 1 to 10.")
            return
        }
        // A draft carrying only the actuals, with the prescribed group left nil —
        // `updateActuals` writes only the actual columns, so the prescription is
        // untouched whatever this draft holds.
        let draft = WorkoutBoutDraft(
            sessionId: bout.sessionId,
            exerciseCatalogId: bout.exerciseCatalogId,
            sequenceIndex: bout.sequenceIndex,
            prescriptionType: bout.prescriptionType,
            containerType: bout.containerType,
            actualSets: int(sets),
            actualReps: int(reps),
            actualLoadKg: double(loadKg),
            actualDurationSeconds: double(durationSeconds),
            actualDistanceMeters: double(distanceMeters),
            actualRounds: int(rounds),
            elapsedSeconds: double(elapsedSeconds),
            avgHeartRate: int(avgHeartRate),
            rpe: int(rpe),
            techniqueRating: bout.techniqueRating,
            notes: optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        do {
            let changed = try WorkoutBoutStore(db: db).updateActuals(draft, id: bout.id)
            guard changed else {
                error = String(localized: "That bout no longer exists — it may have been deleted on another screen.")
                return
            }
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Blank means not recorded. Anything non-blank was already validated in
    /// `save()`, so a nil here can only be a genuinely empty field.
    private func int(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(userInput: trimmed)
    }

    private func double(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Double(userInput: trimmed)
    }
}
