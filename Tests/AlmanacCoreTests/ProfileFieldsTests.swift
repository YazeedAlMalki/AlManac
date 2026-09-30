import Foundation
import Testing
@testable import AlmanacCore

/// The Task F profile fields, and the Task E unit basis they travel with.
///
/// Two things are being pinned here. First, that each field round-trips — a
/// profile field that silently fails to save is the classic version of this
/// feature, because the picker shows the value and the next launch does not have
/// it. Second, that the absences are absences: an install that has never opened
/// Settings reads as every optional field unset, not as a profile with guesses in
/// it.
@Suite("Profile fields")
struct ProfileFieldsTests {

    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func store(_ db: Database, at now: Date = Date(timeIntervalSince1970: 1_800_000_000))
    -> ProfileStore {
        ProfileStore(db: db, clock: FixedClock(now))
    }

    // MARK: - Absences

    @Test("A profile nobody has filled in is all unset, not all guessed")
    func freshProfileIsEmpty() throws {
        let db = try migrated()
        let profile = try store(db).profile()
        #expect(profile.unitBasis == .kilograms)
        #expect(profile.trainingExperience == .notSet)
        #expect(profile.bloodType == nil)
        #expect(profile.allergens.isEmpty)
        #expect(profile.registeredAt == nil)
        #expect(profile.isRegistered == false)
        #expect(profile.firstName == nil)
        // And "not asked" is not "asked, and told us they don't know".
        #expect(profile.bloodType != .unknown)
        // Nothing has been assumed about their body, so no target can be derived.
        #expect(profile.canGenerateCalorieTarget == false)
    }

    // MARK: - Unit basis

    @Test("The unit basis round-trips, and defaults to kilograms")
    func unitBasisRoundTrips() throws {
        let db = try migrated()
        let profileStore = store(db)
        #expect(try profileStore.profile().unitBasis == .kilograms)
        try profileStore.updateUnitBasis(.pounds)
        #expect(try profileStore.profile().unitBasis == .pounds)
        try profileStore.updateUnitBasis(.kilograms)
        #expect(try profileStore.profile().unitBasis == .kilograms)
    }

    @Test("A unit basis the column does not list cannot be written")
    func unitBasisIsConstrained() throws {
        // "Stone" is a real unit somebody will eventually ask for, and it is not in
        // the set. The CHECK is what makes that a rejected write rather than a
        // value that reads back as something else — a column that accepted it and
        // then parsed it as kilograms would show every mass in the app half the
        // size of what the person typed.
        let db = try migrated()
        let profileStore = store(db)
        // A CHECK is evaluated per row, so an UPDATE over an empty table
        // constraints nothing — the row has to exist for this to be a test.
        try profileStore.updateDisplayName("Reader")
        #expect(throws: (any Error).self) {
            try db.run("UPDATE profile SET unitBasis = 'stone';")
        }
        #expect(try profileStore.profile().unitBasis == .kilograms)
        // And the parse fallback, for a value that is there anyway.
        #expect(UnitBasis.parse(nil) == .kilograms)
        #expect(UnitBasis.parse("") == .kilograms)
        #expect(UnitBasis.parse("stone") == .kilograms)
        #expect(UnitBasis.parse("pounds") == .pounds)
    }

    @Test("Masses convert in a pounds basis and nothing else does")
    func onlyMassesConvert() throws {
        let pounds = UnitBasis.pounds
        #expect(abs(pounds.value(72.5, metric: .weight) - 159.834) < 0.01)
        #expect(abs(pounds.value(72.5, metric: .leanMassKg) - 159.834) < 0.01)
        // A percentage and a rating are the same number in every basis. Converting
        // them would be a bug with a clean-looking answer.
        #expect(pounds.value(18.4, metric: .bodyFatPercent) == 18.4)
        #expect(pounds.value(8, metric: .visceralRating) == 8)
        // `format` is the bare number and `formatWithUnit` appends the unit —
        // the same split `BodyMetric` has, asserted on both so they cannot drift.
        #expect(UnitBasis.pounds.format(72.5, metric: .weight) == "159.8")
        #expect(UnitBasis.pounds.formatWithUnit(72.5, metric: .weight) == "159.8 lb")
        #expect(UnitBasis.pounds.format(18.4, metric: .bodyFatPercent) == "18.4")
        #expect(UnitBasis.pounds.formatWithUnit(18.4, metric: .bodyFatPercent) == "18.4%")
        #expect(UnitBasis.pounds.formatWithUnit(8, metric: .visceralRating) == "8")
        // And the round trip a typed-in-pounds target depends on.
        #expect(abs(UnitBasis.pounds.kilograms(fromMass: pounds.value(72.5, metric: .weight)) - 72.5) < 0.0001)
    }

    @Test("A card in pounds says pounds, everywhere")
    func cardTextFollowsTheBasis() throws {
        // The unit basis is carried on the value, not read from a store at format
        // time — so the same progress rendered twice cannot give two answers.
        let progress = BodyCompositionProgress(metric: .weight, current: 72.5, previous: 73.0,
                                              start: 75, target: 70, readingCount: 3,
                                              unitBasis: .pounds)
        #expect(progress.currentText == "159.8")
        #expect(progress.currentWithUnit == "159.8 lb")
        #expect(progress.targetWithUnit == "154.3 lb")
        #expect(progress.remainingText == "5.5 lb")
        #expect(progress.statusText == "5.5 lb to go")
        #expect(progress.accessibilityDescription
                == "Weight: 159.8 lb. Your target of 154.3 lb, 5.5 lb to go.")
        // And the arithmetic is untouched, because a conversion scales a ratio.
        #expect(abs((progress.fraction ?? 0) - 0.5) < 0.0001)
        // `change` is in the stored unit, not the display basis: a signed difference
        // is a difference, and converting it would make the number on the card
        // disagree with the number the direction was judged from.
        #expect(progress.change == -0.5)
        #expect(progress.directionOfTravel == .improving)
    }

    // MARK: - Registration

    @Test("Registration is a moment, and only the first one counts")
    func registrationIsIdempotent() throws {
        let db = try migrated()
        let profileStore = store(db, at: Date(timeIntervalSince1970: 1_800_000_000))
        try profileStore.markRegistered()
        let first = try profileStore.profile().registeredAt
        #expect(first == Date(timeIntervalSince1970: 1_800_000_000))

        // Somebody who comes back to finish setup must not have their registration
        // date moved to whenever that was — "when did they register" would then
        // answer "when they last changed a preference".
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        try store(db, at: later).markRegistered()
        #expect(try profileStore.profile().registeredAt == first)
        #expect(try profileStore.profile().isRegistered)
    }

    @Test("Registration can be undone, and the date goes with it")
    func registrationCanBeCleared() throws {
        // For somebody who wants the setup flow back. A flag that cannot be turned
        // off is not a flag, it is a decision.
        let db = try migrated()
        let profileStore = store(db)
        try profileStore.markRegistered()
        try profileStore.clearRegistration()
        let profile = try profileStore.profile()
        #expect(profile.registeredAt == nil)
        #expect(profile.isRegistered == false)
    }

    // MARK: - Training experience and blood type

    @Test("Training experience round-trips, including declining to say")
    func trainingExperienceRoundTrips() throws {
        let db = try migrated()
        let profileStore = store(db)
        for level in TrainingExperience.allCases {
            try profileStore.updateTrainingExperience(level)
            #expect(try profileStore.profile().trainingExperience == level)
        }
        // Declining is not the same as being intermediate, and neither is an error.
        #expect(TrainingExperience.notSet.allowsProgressiveAdvice == false)
        #expect(TrainingExperience.intermediate.allowsProgressiveAdvice)
        #expect(TrainingExperience.parse(nil) == .notSet)
        #expect(TrainingExperience.parse("wizard") == .notSet)
    }

    @Test("Blood type distinguishes not-asked from asked-and-unknown")
    func bloodTypeRoundTrips() throws {
        let db = try migrated()
        let profileStore = store(db)
        // "Not asked" is nil and stays nil.
        try profileStore.updateBloodType(nil)
        #expect(try profileStore.profile().bloodType == nil)

        // Every type, plus the honest "I don't know".
        for type in BloodType.allCases {
            try profileStore.updateBloodType(type)
            #expect(try profileStore.profile().bloodType == type)
        }
        #expect(BloodType.unknown.isKnown == false)
        #expect(BloodType.aPositive.isKnown)
        #expect(BloodType.allCases.count == 9)
        // Eight real types, and the Rh factor is part of the value rather than a
        // second field that could disagree with the first.
        #expect(BloodType.allCases.filter(\.isKnown).map(\.rawValue).sorted()
                == ["A+", "A-", "AB+", "AB-", "B+", "B-", "O+", "O-"])
    }

    // MARK: - Names

    @Test("The name split does not disturb what the app already shows")
    func namesAreAdditive() throws {
        let db = try migrated()
        let profileStore = store(db)
        try profileStore.updateDisplayName("Yazeed")
        // First and last name are new columns and new facts; `displayName` is left
        // exactly as it was, because it is the greeting on every screen and the
        // row every existing install already holds.
        try profileStore.updateFirstName("Yazeed")
        try profileStore.updateLastName("Abdulrahman")
        let profile = try profileStore.profile()
        #expect(profile.displayName == "Yazeed")
        #expect(profile.lastName == "Abdulrahman")
        #expect(profile.preferredName == "Yazeed")
        // And with no first name given, the derived name falls back rather than
        // rendering as an empty greeting.
        try profileStore.updateFirstName(nil)
        #expect(try profileStore.profile().preferredName == "Yazeed")
        #expect(try profileStore.profile().displayName == "Yazeed")
    }

    // MARK: - Allergens

    @Test("Allergens are added, listed, and removed individually")
    func allergenLifecycle() throws {
        let db = try migrated()
        let profileStore = store(db)
        #expect(try profileStore.allergens().isEmpty)

        try profileStore.addAllergen(.peanuts)
        try profileStore.addAllergen(.milk)
        // In picker order, not insertion order, so the profile screen and the
        // setup flow show the same list in the same arrangement.
        #expect(try profileStore.allergens() == [.peanuts, .milk])

        // Revoking one leaves the other alone. This is the operation a person
        // performs when a reaction gets better, and it is why this is a table.
        try profileStore.removeAllergen(.peanuts)
        #expect(try profileStore.allergens() == [.milk])
        // Removing one that was not there is a no-op, not an error — a UI that
        // tapped twice should not fault.
        try profileStore.removeAllergen(.peanuts)
        #expect(try profileStore.allergens() == [.milk])
    }

    @Test("The same allergy cannot be recorded twice")
    func noDuplicateAllergens() throws {
        let db = try migrated()
        let profileStore = store(db)
        try profileStore.addAllergen(.sesame)
        try profileStore.addAllergen(.sesame)
        try profileStore.addAllergen(.sesame)
        // A duplicate row on this list is a thing somebody has to notice and
        // remove, and it reads as alarming.
        #expect(try profileStore.allergens() == [.sesame])
        let rows = try db.query("SELECT COUNT(*) AS n FROM profile_allergen;")
        #expect(rows.first?.int("n") == 1)
    }

    @Test("Setting the whole set keeps the ones that did not change")
    func setAllergensDiffers() throws {
        let db = try migrated()
        let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let profileStore = store(db, at: clock.now)
        try profileStore.addAllergen(.peanuts)
        let recordedAt = try db.query("SELECT createdAt FROM profile_allergen;").first?.string("createdAt")
        #expect(recordedAt == "2027-01-15T08:00:00Z")

        // A later save, from a different "now": the untouched allergy keeps the
        // time it was actually declared, because that is the only record of when
        // somebody said they had it.
        let later = store(db, at: Date(timeIntervalSince1970: 1_900_000_000))
        try later.setAllergens([.peanuts, .gluten])
        #expect(try later.allergens() == [.gluten, .peanuts])
        let stamps = try db.query("SELECT allergen_id, createdAt FROM profile_allergen ORDER BY allergen_id;")
            .map { ($0.string("allergen_id") ?? "", $0.string("createdAt") ?? "") }
        // Ordered by id: gluten is the newly added row and carries the later
        // stamp; peanuts is untouched and keeps the time it was declared.
        #expect(stamps.first?.0 == "gluten")
        #expect(stamps.first?.1 == "2030-03-17T17:46:40Z")
        #expect(stamps.last?.0 == "peanuts")
        #expect(stamps.last?.1 == recordedAt)

        // And clearing the lot works, which is the reason the diff is not simply
        // "delete everything then insert".
        try later.setAllergens([])
        #expect(try later.allergens().isEmpty)
    }

    @Test("The profile carries its allergens")
    func profileCarriesAllergens() throws {
        let db = try migrated()
        let profileStore = store(db)
        try profileStore.addAllergen(.crustaceans)
        try profileStore.addAllergen(.fish)
        let profile = try profileStore.profile()
        #expect(profile.allergens == [.crustaceans, .fish])
        #expect(try profileStore.allergenSet() == [.crustaceans, .fish])
    }

    @Test("An allergen outside the closed set cannot be recorded")
    func unknownAllergenCannotBeStored() throws {
        // The foreign key is what makes this an enum rather than a convention.
        let db = try migrated()
        try store(db).addAllergen(.nuts)
        #expect(throws: (any Error).self) {
            try db.run("""
            INSERT INTO profile_allergen (profile_id, allergen_id, createdAt)
            VALUES (1, 'unobtainium', '2026-09-30T00:00:00Z');
            """)
        }
    }

    // MARK: - The target inputs

    @Test("A complete profile can generate a calorie target")
    func calorieTargetInputs() throws {
        let db = try migrated()
        let profileStore = store(db)
        #expect(try profileStore.profile().canGenerateCalorieTarget == false)

        // One piece at a time, so it is visible which one is load-bearing. Sex is
        // last and it is a real piece: with no sex stated there is no resting burn
        // to multiply by an activity level, and inventing one would be a number
        // about somebody's body that nobody chose.
        try profileStore.updateDateOfBirth("1996-09-30")
        #expect(try profileStore.profile().canGenerateCalorieTarget == false)
        try profileStore.updateHeight(180)
        #expect(try profileStore.profile().canGenerateCalorieTarget == false)
        try profileStore.updateBiologicalSex("not_set")
        #expect(try profileStore.profile().canGenerateCalorieTarget == false)
        try profileStore.updateBiologicalSex("male")
        #expect(try profileStore.profile().canGenerateCalorieTarget)

        // A free-text value typed the way a person types it. `ProfileView` has
        // always written whatever was in the field, so "Female" is a value real
        // installs hold, and a case-sensitive parse would read it as *not said* —
        // silently switching off target generation for somebody who has said.
        try profileStore.updateBiologicalSex("Female")
        #expect(BiologicalSex.parse("Female") == .female)
        #expect(try profileStore.profile().canGenerateCalorieTarget)
        try profileStore.updateBiologicalSex("  male  ")
        #expect(try profileStore.profile().canGenerateCalorieTarget)

        // And a height of zero is not a height.
        try profileStore.updateHeight(0)
        #expect(try profileStore.profile().canGenerateCalorieTarget == false)
    }
}
