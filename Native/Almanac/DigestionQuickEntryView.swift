import SwiftUI
import AlmanacCore
import Foundation

/// Quick entry for the two things BRD §6.3 covers: a bowel movement and a
/// urination.
///
/// **No advisory, and that is deliberate.** BRD §6.3 asks for a three-level
/// non-diagnostic advisory and then says its wording "requires clinician review
/// before App Store release". `clinicianEscalationLevel` is therefore left NULL
/// by every write here, and this screen displays no interpretation of any
/// entry — no colour is called concerning, no grade is called dark, blood is
/// shown as the fact the user recorded it as. The escalation rule that would
/// key on "black" and "red" is the part of §6.3 that has not been written, and
/// writing the *display* half of it is how the other half would get written by
/// accident.
///
/// **Today's entries, not a history.** This is a quick-entry surface: log it,
/// see it, undo it. A multi-day view with trends is the read side and is not
/// built (see `docs/features/digestion.md`).
@MainActor
struct DigestionQuickEntryView: View {
    let db: Database?
    @ObservedObject var trackingModel: TrackingCalendarModel
    /// Called after a save. The sheet hosting this may keep itself open for a
    /// second entry, so this is a notification, not a dismissal.
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .bowel
    @State private var bristol: BristolType = .type4
    @State private var stoolColor: StoolColor = .brown
    @State private var notesStated = false
    @State private var bloodPresent = false
    @State private var bloodAmount: BloodAmount = .none
    @State private var gas: Gas = .unstated
    @State private var grade: UrinationColorGrade = .grade4
    @State private var notes = ""
    @State private var time = Date()
    @State private var entries: [(id: Int64, time: Date, text: String)] = []
    @State private var confirmation: String?
    @State private var error: String?
    @State private var readProblem: String?

    private enum Kind: String, CaseIterable, Identifiable {
        case bowel, urination
        var id: String { rawValue }
        var title: String { self == .bowel ? String(localized: "Bowel movement") : String(localized: "Urination") }
    }

    /// How much blood, where the user has observed some.
    ///
    /// The BRD's escalation rule names "amount/type of blood" as a trigger, so
    /// the value has to be a value rather than a yes/no — but the vocabulary is
    /// this one's, since the BRD does not list amounts. `none` is distinct from
    /// "unstated" for the same reason `gas` is: a user who saw no blood and a
    /// user who did not look are different observations, and only the first is
    /// a finding.
    private enum BloodAmount: String, CaseIterable, Identifiable {
        case none, streak, small, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return String(localized: "None seen")
            case .streak: return String(localized: "Streak")
            case .small: return String(localized: "Small amount")
            case .large: return String(localized: "Large amount")
            }
        }
    }

    /// Gas, with "unstated" as a real third state.
    private enum Gas: String, CaseIterable, Identifiable {
        case unstated, yes, no
        var id: String { rawValue }
        var title: String {
            switch self {
            case .unstated: return String(localized: "Not stated")
            case .yes: return String(localized: "Yes")
            case .no: return String(localized: "No")
            }
        }
    }

    private let timeModel = TimeModel(timeZone: .current)

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(Kind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("digestion-kind")

                Section {
                    DatePicker("Time", selection: $time)
                } footer: {
                    Text("Logical day \(timeModel.logicalDay(time).value) — days begin at 04:00.")
                }

                if kind == .bowel {
                    bristolSection
                    colorSection
                    symptomSection
                } else {
                    gradeSection
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let readProblem {
                    Section { AlmanacProblemNote(text: readProblem) }
                }

                todaysEntries
            }
            .almanacModuleSurface()
            .navigationTitle("Log digestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(db == nil)
                        .accessibilityIdentifier("digestion-save")
                }
            }
            .editorError($error)
            .task { reload() }
        }
    }

    // MARK: - Bristol

    /// A link to the scale, not the scale.
    ///
    /// Seven described rows inlined would push the colour field, the symptoms
    /// and the notes field most of a screen away — and this form is a *log*
    /// form, so everything below the fold is something the user came here to
    /// do. The link shows the current choice, which is the part that has to stay
    /// on screen. `BristolScaleView` is where the comparing happens.
    private var bristolSection: some View {
        Section {
            NavigationLink {
                BristolScaleView(selection: $bristol)
            } label: {
                HStack {
                    Text("Bristol type")
                    Spacer()
                    Text("\(bristol.rawValue) — \(bristol.displayName)")
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityIdentifier("bristol-link")
            .accessibilityLabel(bristol.accessibilityLabel)
        } footer: {
            Text("Seven types, from separate hard lumps to entirely liquid.")
        }
    }

    // MARK: - Colour

    /// Text, never a swatch. The BRD's rule is not to rely on colour alone, and
    /// a colour chip *is* relying on colour alone — it also cannot be rendered
    /// at all to a VoiceOver user, and a swatch of "brown" and a swatch of
    /// "pale yellow" are near-identical on screen at small sizes.
    private var colorSection: some View {
        Section {
            Picker("Colour", selection: $stoolColor) {
                ForEach(StoolColor.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .accessibilityIdentifier("stool-color")
        } header: {
            AlmanacSectionHeader(title: String(localized: "Colour"))
        } footer: {
            Text("Almanac records what you saw and does not interpret it.")
        }
    }

    private var symptomSection: some View {
        Section {
            Toggle("Blood seen", isOn: $bloodPresent)
                .accessibilityIdentifier("digestion-blood")
            if bloodPresent {
                Picker("How much", selection: $bloodAmount) {
                    ForEach(BloodAmount.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("digestion-blood-amount")
            }
            Picker("Gas", selection: $gas) {
                ForEach(Gas.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier("digestion-gas")
        } header: {
            AlmanacSectionHeader(title: String(localized: "Symptoms"))
        } footer: {
            // Says what a nil means, because "Gas: not stated" is otherwise a
            // value the user cannot produce and so cannot interpret.
            Text("“Not stated” is a different entry from “no” — it records that you were not asked, not that you noticed nothing.")
        }
    }

    // MARK: - Urination grade

    /// A link to the chart, for the same reason as the Bristol scale above.
    private var gradeSection: some View {
        Section {
            NavigationLink {
                UrinationGradeView(selection: $grade)
            } label: {
                HStack {
                    Text("Colour grade")
                    Spacer()
                    Text(grade.displayName)
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityIdentifier("grade-link")
            .accessibilityLabel(grade.accessibilityLabel)
        } footer: {
            Text("Eight grades, 1 pale through 8 dark brown. The intermediate grades have no published description here, so only the two ends are named.")
        }
    }

    // MARK: - Today's entries

    private var todaysEntries: some View {
        Section {
            if entries.isEmpty {
                Text("Nothing logged today.")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                ForEach(entries, id: \.id) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text)
                                .font(AlmanacTypography.font(.body))
                                .foregroundStyle(AlmanacPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.time.formatted(date: .omitted, time: .shortened))
                                .font(AlmanacTypography.font(.caption))
                                .monospacedDigit()
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                        Spacer(minLength: 10)
                    }
                    .frame(minHeight: AlmanacMetrics.minimumControl)
                    .swipeActions {
                        Button("Delete", role: .destructive) { delete(entry.id) }
                    }
                }
            }
            if let confirmation {
                AlmanacStatusMark(text: confirmation, tone: .good)
            }
        } header: {
            AlmanacSectionHeader(title: String(localized: "Today"))
        }
    }

    // MARK: - Actions

    private func save() {
        guard let db else { return }
        let day = timeModel.logicalDay(time).value
        let cleanNotes = optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            switch kind {
            case .bowel:
                _ = try DigestionStore(db: db).log(
                    BowelMovementDraft(timestamp: time,
                                       bristolType: bristol,
                                       color: stoolColor.rawValue,
                                       bloodPresent: bloodPresent,
                                       bloodAmount: bloodPresent && bloodAmount != .none ? bloodAmount.rawValue : nil,
                                       gas: gas == .unstated ? nil : (gas == .yes),
                                       // Urgency is left nil: the column is an
                                       // unvalidated Int and neither the BRD nor
                                       // the spec gives it a scale, so a picker
                                       // here would be inventing one. Recorded
                                       // in docs/features/digestion.md.
                                       notes: cleanNotes),
                    logicalDay: day)
                confirmation = "Bowel movement logged"
            case .urination:
                _ = try UrinationStore(db: db).log(
                    UrinationDraft(timestamp: time, colorGrade: grade, notes: cleanNotes),
                    logicalDay: day)
                confirmation = "Urination logged"
            }
            notes = ""
            reload()
            trackingModel.refresh()
            onSaved()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func delete(_ id: Int64) {
        guard let db else { return }
        do {
            switch kind {
            case .bowel: try DigestionStore(db: db).delete(id: id)
            case .urination: try UrinationStore(db: db).delete(id: id)
            }
            confirmation = nil
            reload()
            trackingModel.refresh()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func reload() {
        guard let db else { return }
        let day = timeModel.logicalDay(Date()).value
        do {
            let bowel = try DigestionStore(db: db).logs(for: day).map { entry in
                (entry.id, entry.timestamp, describe(entry))
            }
            let urine = try UrinationStore(db: db).logs(for: day).map { entry in
                (entry.id, entry.timestamp, describe(entry))
            }
            // Both tables, newest first — a single list of "what I recorded
            // today", not two lists the user has to read as separate things.
            entries = (bowel + urine).sorted { $0.1 > $1.1 }
            readProblem = nil
        } catch {
            self.error = String(describing: error)
            readProblem = "Could not read today's entries."
            entries = []
        }
    }

    private func describe(_ entry: BowelMovementEntry) -> String {
        var parts = ["Type \(entry.bristolType.rawValue) — \(entry.bristolType.displayName)"]
        if let color = entry.color { parts.append(StoolColor(rawValue: color)?.displayName ?? readable(color)) }
        if entry.bloodPresent {
            let amount = entry.bloodAmount.map { readable($0) }
            parts.append(amount.map { "Blood seen, \($0)" } ?? String(localized: "Blood seen"))
        }
        if let gas = entry.gas { parts.append(gas ? String(localized: "Gas") : String(localized: "No gas")) }
        if let note = entry.notes, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private func describe(_ entry: UrinationEntry) -> String {
        var parts = [entry.colorGrade.displayName]
        if let note = entry.notes, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// The Bristol scale on its own screen, all seven types at once.
///
/// A wheel would hide six of seven behind a spin, and the point of a reference
/// scale is comparing what you saw against all of them together. Every row
/// carries the number *and* the description, per BRD §6.3's "never rely on
/// colour alone; numeric grades + text + VoiceOver" — the two halves of that
/// rule have to travel together, or a number travels without its meaning.
struct BristolScaleView: View {
    @Binding var selection: BristolType

    var body: some View {
        List {
            ForEach(BristolType.allCases, id: \.rawValue) { type in
                Button {
                    selection = type
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(type.rawValue)")
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                            .foregroundStyle(AlmanacPalette.textSecondary)
                            .frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(AlmanacTypography.font(.body))
                                .foregroundStyle(AlmanacPalette.textPrimary)
                            Text(type.summary)
                                .font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 10)
                        if selection == type {
                            Image(systemName: AlmanacIcon.check)
                                .foregroundStyle(AlmanacPalette.accent)
                        }
                    }
                    .frame(minHeight: AlmanacMetrics.minimumControl)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bristol-type-\(type.rawValue)")
                .accessibilityLabel(type.accessibilityLabel)
                .accessibilityAddTraits(selection == type ? [.isSelected] : [])
            }
        }
        .almanacModuleSurface()
        .navigationTitle("Bristol type")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The eight-level urination colour chart on its own screen.
///
/// Text, never a swatch — see `DigestionQuickEntryView`'s colour section for why
/// the same rule applies twice.
struct UrinationGradeView: View {
    @Binding var selection: UrinationColorGrade

    var body: some View {
        List {
            ForEach(UrinationColorGrade.allCases, id: \.rawValue) { grade in
                Button {
                    selection = grade
                } label: {
                    HStack(spacing: 12) {
                        Text("\(grade.rawValue)")
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                            .foregroundStyle(AlmanacPalette.textSecondary)
                            .frame(width: 22, alignment: .leading)
                        Text(grade.displayName)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Spacer(minLength: 10)
                        if selection == grade {
                            Image(systemName: AlmanacIcon.check)
                                .foregroundStyle(AlmanacPalette.accent)
                        }
                    }
                    .frame(minHeight: AlmanacMetrics.minimumControl)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("urine-grade-\(grade.rawValue)")
                .accessibilityLabel(grade.accessibilityLabel)
                .accessibilityAddTraits(selection == grade ? [.isSelected] : [])
            }
        }
        .almanacModuleSurface()
        .navigationTitle("Colour grade")
        .navigationBarTitleDisplayMode(.inline)
    }
}
