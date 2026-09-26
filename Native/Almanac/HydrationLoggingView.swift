import SwiftUI
import AlmanacCore

/// Log what was actually drunk.
///
/// This screen used to be water-only: three volume presets, a free-text
/// amount, and a note. `HydrationLoggingService`, `CatalogDrinks` and the
/// `hydration_drink` table have been built and tested in `AlmanacCore` since
/// Migration013 with calories, sodium, sugar, volume scaling, duplicate-tap
/// detection and a provenance qualifier — and none of it was reachable from
/// here. The owner asked for other drinks counted with their calories
/// (2026-09-26); this is that.
///
/// The qualifier is not optional in the UI. `CatalogDrinks` states plainly:
/// "Do not present these as measured anywhere in the UI without that qualifier
/// visible." A catalog can of cola is a typical value for a named product, not
/// a cited composition figure, and this screen says which of the two the user
/// is looking at rather than letting a number imply either.
struct HydrationLoggingView: View {
    @ObservedObject var model: HydrationModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Drink?
    @State private var amountText = ""
    @State private var note = ""
    @State private var error: String?
    @State private var warnings: [DrinkLoggingWarning] = []
    @State private var addingDrink = false
    /// Loaded once on appear. `allDrinks()` reads `hydration_drink`, so
    /// computing it from two computed properties would query the database
    /// twice per render.
    @State private var drinks: [Drink] = []
    private let onSaved: () -> Void

    init(model: HydrationModel, onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                drinkSection
                if selected != nil { amountSection }
                nutritionSection
                warningSection
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log a drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", action: save).disabled(selected == nil)
                }
            }
            .sheet(isPresented: $addingDrink) {
                CustomDrinkView(model: model) { drink in
                    drinks = model.allDrinks()
                    selected = drink
                    amountText = String(Int(drink.volumeMilliliters.rounded()))
                    addingDrink = false
                }
            }
            .editorError($error)
            .task { drinks = model.allDrinks() }
        }
    }

    // MARK: - Sections

    /// The service's own warnings, shown rather than swallowed. A possible
    /// double tap in particular should not pass unseen, and re-deriving these
    /// in the UI would let the two drift from the service's thresholds.
    @ViewBuilder
    private var warningSection: some View {
        if !warnings.isEmpty {
            Section {
                ForEach(warnings, id: \.type) { warning in
                    AlmanacStatusMark(text: warning.message, tone: .warning)
                }
                Button("Log it anyway") { finish() }
            } header: {
                Text("Logged, with notes")
            } footer: {
                Text("The drink is saved. These are things worth knowing, not reasons it was rejected.")
            }
        }
    }

    private var drinkSection: some View {
        Section {
            ForEach(catalogDrinks) { drink in
                drinkRow(drink)
            }
            if !customDrinks.isEmpty {
                ForEach(customDrinks) { drink in
                    drinkRow(drink)
                }
            }
            Button {
                addingDrink = true
            } label: {
                Label("Add your own drink", systemImage: "plus.circle")
            }
        } header: {
            Text("What did you drink?")
        } footer: {
            Text("Catalog figures are typical values for the named product, not measured from a published composition table. Your own drinks are your figures and are labelled as such.")
        }
    }

    private func drinkRow(_ drink: Drink) -> some View {
        Button {
            selected = drink
            // Pre-fill the drink's own serving size, so the common case is one
            // tap to pick and one to log.
            amountText = String(Int(drink.volumeMilliliters.rounded()))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(drink.name)
                    Text(qualifierLabel(drink))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if drink.caloriesKcal > 0 {
                    Text("\(AlmanacNumber.compact(drink.caloriesKcal)) kcal")
                        .font(AlmanacTypography.font(.data).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("drink-row-\(drink.id)")
    }

    private var amountSection: some View {
        Section("How much") {
            HStack(spacing: 10) {
                ForEach([250.0, 500.0, 750.0], id: \.self) { preset in
                    Button("\(Int(preset)) mL") { amountText = String(Int(preset)) }
                        .buttonStyle(.bordered)
                }
            }
            TextField("Custom amount, in mL", text: $amountText)
                .keyboardType(.numberPad)
        }
    }

    /// The figures for the amount actually selected, not the drink's catalog
    /// serving — logging half a can must not credit a full can. Nil per field
    /// rather than zero, so an absent figure never reads as "none".
    @ViewBuilder
    private var nutritionSection: some View {
        if let drink = selected, let amount = Double(amountText), amount > 0 {
            let scale = drink.volumeMilliliters > 0 ? amount / drink.volumeMilliliters : 1
            Section {
                if drink.caloriesKcal > 0 {
                    figure("Calories", "\(AlmanacNumber.compact(drink.caloriesKcal * scale)) kcal")
                }
                if drink.sodiumMilligrams > 0 {
                    figure("Sodium", "\(AlmanacNumber.compact(drink.sodiumMilligrams * scale)) mg")
                }
                if let sugar = drink.sugarGrams, sugar > 0 {
                    figure("Sugar", "\(AlmanacNumber.compact(sugar * scale)) g")
                }
            } header: {
                Text("This amount")
            } footer: {
                Text(scalingFootnote(drink, scale: scale))
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(AlmanacTypography.font(.body))
            Spacer(minLength: 12)
            Text(value).font(AlmanacTypography.font(.data).monospacedDigit())
        }
    }

    // MARK: - Data

    private var catalogDrinks: [Drink] { drinks.filter { !$0.isCustom } }
    private var customDrinks: [Drink] { drinks.filter(\.isCustom) }

    private func qualifierLabel(_ drink: Drink) -> String {
        drink.isCustom ? "Your figures" : "Typical value, not measured"
    }

    private func scalingFootnote(_ drink: Drink, scale: Double) -> String {
        let base = Int(drink.volumeMilliliters.rounded())
        if abs(scale - 1) < 0.001 {
            return drink.isCustom
                ? "Your own figures for \(base) mL."
                : "Typical values for a \(base) mL serving, not measured from a composition table."
        }
        return "Scaled from a \(base) mL serving to the amount logged. \(drink.isCustom ? "Your own figures." : "Typical values, not measured.")"
    }

    // MARK: - Save

    private func save() {
        guard let drink = selected else { return }
        let amount = Double(amountText).map { Milliliters($0) }
        do {
            warnings = try model.logDrink(drink, volume: amount, note: optionalText(note))
            if warnings.isEmpty {
                finish()
            }
            // Warnings are the service's call (duplicate tap, high sugar, high
            // sodium). They are shown rather than swallowed; a possible double
            // tap in particular should not pass without being seen.
        } catch {
            self.error = String(describing: error)
        }
    }

    private func finish() {
        onSaved()
        dismiss()
    }
}

/// Add a drink of the user's own, with their own figures. The service tags it
/// `.userEntered` itself, so nothing entered here can be mistaken for a
/// catalog estimate.
struct CustomDrinkView: View {
    @ObservedObject var model: HydrationModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: LiquidType = .other
    @State private var volumeText = ""
    @State private var caloriesText = ""
    @State private var sodiumText = ""
    @State private var sugarText = ""
    @State private var error: String?
    var onSave: (Drink) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $type) {
                        ForEach(LiquidType.allCases, id: \.self) {
                            Text(readable($0.rawValue)).tag($0)
                        }
                    }
                    TextField("Serving size (mL)", text: $volumeText).keyboardType(.numberPad)
                }
                Section {
                    TextField("Calories (kcal)", text: $caloriesText).keyboardType(.numberPad)
                    TextField("Sodium (mg)", text: $sodiumText).keyboardType(.numberPad)
                    TextField("Sugar (g, optional)", text: $sugarText).keyboardType(.decimalPad)
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("These are your figures, taken on your word, and stay labelled as yours. Almanac does not verify them against a composition table.")
                }
            }
            .navigationTitle("New drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .editorError($error)
        }
    }

    private func save() {
        guard let volume = Double(volumeText), volume > 0 else {
            error = "Enter a serving size greater than zero."
            return
        }
        do {
            // Persisted through the service, not just constructed here: a drink
            // that is not in `hydration_drink` would vanish on next launch, and
            // the service is what stamps it `.userEntered`.
            let drink = try model.saveCustomDrink(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Custom drink" : name,
                liquidType: type, volumeMilliliters: volume,
                caloriesKcal: Double(caloriesText) ?? 0,
                sodiumMilligrams: Double(sodiumText) ?? 0,
                sugarGrams: Double(sugarText))
            onSave(drink)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
