import SwiftUI
import AlmanacCore

/// The person's own details, and the choices that change what the app advises.
///
/// ## Why most of this is a picker and not a text field
///
/// `biologicalSex` was a free-text `TextField` until this was rewritten, and the
/// damage was real and silent: `BiologicalSex.parse` was case-sensitive, so the
/// `"Female"` a person typed became *not set*, which disabled calorie-target
/// generation with no error anywhere. A picker cannot be typed wrong, and a
/// parser that folds case is now a second line of defence rather than the only
/// one. The same applies to training experience, blood type and the unit basis —
/// each is a closed set that the column already enforces, and a text field is a
/// way to write a value the column does not accept.
///
/// `displayName`, date of birth, height and sports stay free text: they are
/// genuinely open, and a picker over "sports" would be a taxonomy nobody has
/// specified yet.
///
/// ## What is not here
///
/// No calorie target, no macro split, no generated anything. The goal screen owns
/// targets and this screen owns facts about the person; a target derived from a
/// fact is derived in one place.
struct ProfileView: View {
    let db: Database?
    @ObservedObject var readinessModel: ReadinessModel

    @State private var displayName = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = ""
    /// The parsed value, not the raw string. A typed value that does not parse
    /// becomes `.notSet` here rather than being saved and re-parsed somewhere
    /// else — the parse happens once, on the way in.
    @State private var biologicalSex: BiologicalSex = .notSet
    @State private var height = ""
    @State private var sports = ""
    @State private var unitBasis: UnitBasis = .kilograms
    @State private var trainingExperience: TrainingExperience = .notSet
    /// `nil` means "not recorded", which is different from `.unknown` — "I don't
    /// know" is an answer the person gave, and conflating it with silence loses
    /// the fact that they thought about it.
    @State private var bloodType: BloodType?
    @State private var allergens: Set<FoodAllergen> = []
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                TextField("Date of birth (YYYY-MM-DD)", text: $dateOfBirth)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Height (cm)", text: $height)
                    .keyboardType(.decimalPad)
                TextField("Sports (comma-separated)", text: $sports)
            }

            // Split from "Profile" because these three change *what the app
            // advises*, and a person looking for them should not have to read
            // past their own name to find out the app does not know their sex.
            Section {
                Picker("Biological sex", selection: $biologicalSex) {
                    ForEach(BiologicalSex.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Training experience", selection: $trainingExperience) {
                    ForEach(TrainingExperience.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Blood type", selection: $bloodType) {
                    // The "not recorded" row is explicit. A `Picker` bound to an
                    // optional needs a tag matching `nil`, and without it the
                    // control opens on the first real option with nothing
                    // selected — which reads as "you are A+" to somebody who
                    // never touched it.
                    Text("Not recorded").tag(BloodType?.none)
                    ForEach(BloodType.allCases) { option in
                        Text(option.title).tag(BloodType?.some(option))
                    }
                }
            } header: {
                Text("Used to tailor advice")
            } footer: {
                Text(trainingExperience.explanation)
            }

            // A `Picker` rather than a toggle: two states would have been simpler
            // and would have lost the thing people actually need to know, which is
            // that the numbers are stored in kilograms and pounds are a display
            // choice. Storing one and displaying two is why the same reading can
            // be formatted two ways, and why `BodyCompositionProgress` carries
            // its basis instead of reading a store.
            Section {
                Picker("Units", selection: $unitBasis) {
                    ForEach(UnitBasis.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Weights are stored once. Switching this changes how they are shown, not what was recorded.")
            }

            Section {
                ForEach(FoodAllergen.allCases) { allergen in
                    // A toggle per allergen rather than a multi-select list: this is
                    // the operation a person performs most often, which is *removing*
                    // one, and "remove" wants a control you can hit without a
                    // confirmation step.
                    Toggle(isOn: binding(for: allergen)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(allergen.title)
                            Text(allergen.guidance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // The identifier, because the label is the title *and* the
                    // guidance sentence joined: `Toggle` combines its label's
                    // children, so a query by title matches nothing and a query by
                    // index breaks the day someone reorders the list. This is the
                    // same reasoning as `tab-<rawValue>` on the bottom bar.
                    .accessibilityIdentifier("allergen-\(allergen.rawValue)")
                }
            } header: {
                Text("Food allergies")
            } footer: {
                Text("Almanac hides foods whose name mentions one of these. It has no ingredient lists, so it cannot tell you a food is safe — read the label.")
            }

            if saved {
                Section {
                    Label("Profile saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AlmanacPalette.good)
                }
            }
        }
        .navigationTitle("Profile")
        .almanacModuleSurface()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(db == nil)
            }
        }
        .task { load() }
        .editorError($error)
    }

    /// A toggle that adds and removes, rather than binding to a mutable set.
    ///
    /// `Binding(get:set:)` because `Set` has no `subscript` setter that means
    /// "add or remove this one member" — the alternative is a `ForEach` over the
    /// set with an index, which breaks the moment two members sort together.
    private func binding(for allergen: FoodAllergen) -> Binding<Bool> {
        Binding(
            get: { allergens.contains(allergen) },
            set: { isOn in
                if isOn { allergens.insert(allergen) } else { allergens.remove(allergen) }
                // A change here invalidates the food search's results, and the
                // search screen reads the set per search rather than caching it —
                // so the next search is correct and nothing else needs to be told.
                saved = false
            })
    }

    private func load() {
        guard let db else { return }
        do {
            let store = ProfileStore(db: db)
            let profile = try store.profile()
            displayName = profile.displayName
            firstName = profile.firstName ?? ""
            lastName = profile.lastName ?? ""
            dateOfBirth = profile.dateOfBirth ?? ""
            biologicalSex = BiologicalSex.parse(profile.biologicalSex)
            height = profile.heightCm.map { String(describing: $0) } ?? ""
            sports = profile.sports.joined(separator: ", ")
            unitBasis = profile.unitBasis
            trainingExperience = profile.trainingExperience
            bloodType = profile.bloodType
            allergens = try store.allergenSet()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func save() {
        guard let db else { return }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw EditorFailure(message: String(localized: "Enter a display name."))
            }

            let heightValue: Double?
            let trimmedHeight = height.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedHeight.isEmpty {
                heightValue = nil
            } else if let value = Double(trimmedHeight), value > 0, value < 300 {
                heightValue = value
            } else {
                throw EditorFailure(message: String(localized: "Height must be a number between 0 and 300 cm."))
            }

            let store = ProfileStore(db: db)
            try store.updateDisplayName(name)
            try store.updateDateOfBirth(optionalText(dateOfBirth.trimmingCharacters(in: .whitespacesAndNewlines)))
            // Written through `parse`, never the raw text. `.notSet` round-trips
            // to `nil` — the column stores an absence as NULL, and writing the
            // literal string "not_set" would be a value the parser and the column
            // both have to special-case.
            try store.updateBiologicalSex(biologicalSex.isSet ? biologicalSex.rawValue : nil)
            try store.updateHeight(heightValue)
            try store.updateSports(
                sports.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            try store.updateFirstName(optionalText(firstName.trimmingCharacters(in: .whitespacesAndNewlines)))
            try store.updateLastName(optionalText(lastName.trimmingCharacters(in: .whitespacesAndNewlines)))
            try store.updateUnitBasis(unitBasis)
            try store.updateTrainingExperience(trainingExperience)
            try store.updateBloodType(bloodType)
            try store.setAllergens(allergens)
            readinessModel.refresh()
            saved = true
        } catch {
            self.error = String(describing: error)
        }
    }
}
