import SwiftUI
import AlmanacCore
import Foundation

/// Create or edit a supplement plan.
///
/// One form for both rather than two, because the fields are identical and a
/// separate "edit" form is a second place for the vocabularies to drift. The
/// reminder time and the active flag are deliberately absent: `SupplementPlanStore`
/// gives them their own single-purpose methods so that saving this form can
/// never clear a reminder by omitting it.
@MainActor
struct SupplementPlanEditor: View {
    let db: Database
    /// Nil creates a plan; non-nil edits that one.
    let plan: SupplementPlan?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var doseAmount = ""
    @State private var doseUnit = SupplementDoseUnit.milligram.rawValue
    @State private var frequency = SupplementFrequency.daily.rawValue
    @State private var timingNotes = ""
    @State private var error: String?

    private var isEditing: Bool { plan != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplement") {
                    TextField("Name", text: $name)
                    HStack {
                        TextField("Dose", text: $doseAmount)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $doseUnit) {
                            ForEach(SupplementDoseUnit.allCases) { unit in
                                Text(unit.title).tag(unit.rawValue)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("supplement-dose-unit")
                    }
                    Picker("Frequency", selection: $frequency) {
                        ForEach(SupplementFrequency.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .accessibilityIdentifier("supplement-frequency")
                }

                Section {
                    TextField("When you take it", text: $timingNotes, axis: .vertical)
                } footer: {
                    Text(frequency == SupplementFrequency.custom.rawValue
                         ? "Custom frequency — say here when this is due, since the count cannot be derived."
                         : "Optional. Shown under the name on the adherence list.")
                }

                if isEditing {
                    Section {
                        Label("Discontinuing a plan keeps it and its history. Use the swipe action on the plan row.",
                              systemImage: "info.circle")
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
            }
            .navigationTitle(isEditing ? String(localized: "Edit plan") : String(localized: "New plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .editorError($error)
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let plan else { return }
        name = plan.name
        doseAmount = AlmanacNumber.compact(plan.doseAmount)
        doseUnit = plan.doseUnit
        frequency = plan.frequency
        timingNotes = plan.timingNotes ?? ""
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = optionalText(timingNotes.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleanName.isEmpty else {
            error = String(localized: "Give the supplement a name.")
            return
        }
        guard let amount = Double(userInput: doseAmount),
              amount.isFinite, amount > 0 else {
            error = String(localized: "Enter a dose greater than zero.")
            return
        }
        let draft = SupplementPlanDraft(name: cleanName, doseAmount: amount, doseUnit: doseUnit,
                                        frequency: frequency, timingNotes: cleanNotes)
        do {
            let store = SupplementPlanStore(db: db)
            if let plan {
                try store.update(draft, id: plan.id)
            } else {
                _ = try store.create(draft)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
