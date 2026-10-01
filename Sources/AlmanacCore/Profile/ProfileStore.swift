import Foundation

/// User profile data.
///
/// ## Why this struct keeps growing
///
/// Every field here is something the person told the app about themselves, and
/// `profile` is the table for that because §5.1 says so. The additions since the
/// table was created are the handoff's Task F — the name split, training
/// experience, blood type, allergens — plus the unit basis Task E needs.
///
/// Two of the new fields are deliberately *absent* as stored columns and this
/// struct says so in its own comment: see `sports` and `allergens`.
public struct UserProfile: Sendable, Hashable {
    /// The one-line name the app greets people with.
    ///
    /// Kept as it was, not derived from `firstName`. It has been the greeting on
    /// every screen since before the name split existed, it is what existing
    /// installs hold, and "which name do you show" is a product decision rather
    /// than something to answer by overwriting a person's existing row with a
    /// derived value. See `preferredName` for the derived answer.
    public let displayName: String
    /// Split out of `displayName` at Task F's request. Nullable, because no
    /// install has these yet and a migration cannot invent them.
    public let firstName: String?
    public let lastName: String?

    public let dateOfBirth: String?
    public let biologicalSex: String?  // e.g., "male", "female", "other"
    public let heightCm: Double?
    /// JSON array stored as TEXT.
    ///
    /// **Not validated, and that is the reason this one is text while
    /// `allergens` is a table.** These are the sports somebody plays; a wrong
    /// entry costs nothing, nothing queries it, and a picker over a free list has
    /// to tolerate values it has not heard of. An allergen is used to withhold
    /// food, which is the opposite trade — see `allergens`.
    public let sports: [String]

    /// The unit masses are shown in. Kilograms on every install that predates
    /// Migration048, because that is what `body_composition_measurement.unit`
    /// has always held.
    public let unitBasis: UnitBasis

    /// When this person finished first-run setup, or `nil` if they have not.
    ///
    /// **A date rather than a `hasRegistered` boolean**, so one value answers
    /// both questions the gate asks — "has setup finished?" and "when?" — and
    /// there is no way for the two to disagree. Two columns for one fact is how a
    /// flag gets set without the timestamp, or the timestamp without the flag.
    public let registeredAt: Date?
    public let trainingExperience: TrainingExperience
    /// `nil` is "not asked". `.unknown` is "asked, and told us they don't know",
    /// which is a different fact — see `BloodType`.
    public let bloodType: BloodType?

    /// The allergens this person has said they have.
    ///
    /// Rows of `profile_allergen`, joined to `food_allergen` for the labels. Read
    /// from a second query rather than kept in the JSON column `sports` uses,
    /// because on this list a partial rewrite is the operation a person performs
    /// most often: a reaction that gets better is a row deleted, and deleting a
    /// row from a JSON array means rewriting the whole document to drop one
    /// element. A closed set, no duplicates (the primary key enforces it), and a
    /// row that can be individually revoked.
    public let allergens: [FoodAllergen]

    public let bodyMeasurementTrackSides: Bool
    public let createdAt: String
    public let updatedAt: String

    /// Whether first-run setup has been completed.
    ///
    /// A derived property rather than a stored flag, so there is exactly one place
    /// the answer can come from.
    public var isRegistered: Bool { registeredAt != nil }

    /// The name to address somebody by.
    ///
    /// First name if they gave one, else the display name they already had. The
    /// "which do you show" question the handoff flagged — see the doc comment on
    /// `displayName`: this is the derived answer and it is not applied to the
    /// greeting yet, because that is a product decision and not a refactor.
    public var preferredName: String {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? displayName : first
    }

    /// Whether the calorie-target inputs are complete enough to derive one.
    ///
    /// Asked here rather than by the goals code reaching into three fields, so
    /// "can this person have a generated target" has one answer and the builder
    /// cannot disagree with it about which pieces are missing.
    public var canGenerateCalorieTarget: Bool {
        BiologicalSex.parse(biologicalSex) != .notSet
            && (dateOfBirth?.isEmpty == false)
            && (heightCm ?? 0) > 0
    }

    public init(displayName: String,
                firstName: String? = nil,
                lastName: String? = nil,
                dateOfBirth: String? = nil,
                biologicalSex: String? = nil,
                heightCm: Double? = nil,
                sports: [String] = [],
                unitBasis: UnitBasis = .kilograms,
                registeredAt: Date? = nil,
                trainingExperience: TrainingExperience = .notSet,
                bloodType: BloodType? = nil,
                allergens: [FoodAllergen] = [],
                createdAt: String = "",
                updatedAt: String = "",
                bodyMeasurementTrackSides: Bool = false) {
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
        self.heightCm = heightCm
        self.sports = sports
        self.unitBasis = unitBasis
        self.registeredAt = registeredAt
        self.trainingExperience = trainingExperience
        self.bloodType = bloodType
        self.allergens = allergens
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bodyMeasurementTrackSides = bodyMeasurementTrackSides
    }
}

/// Profile storage over `profile` table. Single-user profile — profile.id is always 1.
public struct ProfileStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Read

    /// The person's profile. **Two queries, and the second one is the allergens.**
    ///
    /// Stated rather than left to be discovered: it is one row plus one indexed
    /// join over `profile_allergen`, it runs at launch, and anything that made it
    /// a third query would belong in its own type. The allergens cannot come back
    /// in the same row because they are a one-to-many, and a second query is
    /// cheaper than a `GROUP_CONCAT` the caller then has to parse.
    public func profile() throws -> UserProfile {
        // Fetch the singleton profile row (id=1)
        if let row = try db.query("""
        SELECT displayName, firstName, lastName, dateOfBirth, biologicalSex, heightCm,
               sports, unitBasis, registeredAt, trainingExperience, bloodType,
               createdAt, updatedAt, bodyMeasurementTrackSides
        FROM profile WHERE id = 1;
        """).first {
            return rowToProfile(row)
        }
        // If no profile exists, return a default one (should not happen in normal operation)
        return UserProfile(displayName: "User", createdAt: nowText, updatedAt: nowText)
    }

    /// Just the allergens, for the food gate — without materialising the profile.
    ///
    /// The gate runs per search result row, and `profile()` builds a struct with
    /// nine unrelated fields to hand back a set of four values. Separate so the
    /// one caller that runs in a loop does not drag the rest of the row with it.
    public func allergens() throws -> [FoodAllergen] {
        try db.query("""
        SELECT a.id FROM profile_allergen pa
        JOIN food_allergen a ON a.id = pa.allergen_id
        WHERE pa.profile_id = 1
        ORDER BY a.sort_order;
        """).compactMap { row in
            row.string("id").flatMap(FoodAllergen.init(rawValue:))
        }
    }

    /// The allergens as a `Set`, which is the shape the gate takes.
    public func allergenSet() throws -> Set<FoodAllergen> {
        Set(try allergens())
    }

    /// Just the unit basis, in one query.
    ///
    /// A body-composition screen needs this on every reload to format its cards,
    /// and `profile()` would fetch the whole row *and* join `food_allergen` to
    /// hand back nine unrelated fields. Reading one column is the difference
    /// between one query and two for the common case of somebody with no
    /// allergies, where the second query returns nothing at all.
    public func unitBasis() throws -> UnitBasis {
        guard let row = try db.query("SELECT unitBasis FROM profile WHERE id = 1;").first else {
            return .kilograms
        }
        return UnitBasis.parse(row.string("unitBasis"))
    }

    // MARK: - Write

    /// The profile table is a singleton (id always 1), but nothing seeds
    /// that row at migration time. Every write goes through this first so
    /// "no profile yet" self-heals instead of the UPDATE silently affecting
    /// zero rows (found 2026-09-16: every updateX call was a no-op against
    /// a fresh database).
    private func ensureRowExists() throws {
        try db.run("""
        INSERT OR IGNORE INTO profile (id, createdAt, updatedAt) VALUES (1, ?, ?);
        """, [.text(nowText), .text(nowText)])
    }

    /// Update the user's display name.
    public func updateDisplayName(_ name: String) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE profile SET displayName = ?, updatedAt = ? WHERE id = 1;
        """, [.text(name), .text(nowText)])
    }

    /// Update the user's date of birth (YYYY-MM-DD format).
    public func updateDateOfBirth(_ dob: String?) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE profile SET dateOfBirth = ?, updatedAt = ? WHERE id = 1;
        """, [dob.map { SQLValue.text($0) } ?? .null, .text(nowText)])
    }

    /// Update the user's biological sex.
    public func updateBiologicalSex(_ sex: String?) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE profile SET biologicalSex = ?, updatedAt = ? WHERE id = 1;
        """, [sex.map { SQLValue.text($0) } ?? .null, .text(nowText)])
    }

    /// Update the user's height in centimeters.
    public func updateHeight(_ cm: Double?) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE profile SET heightCm = ?, updatedAt = ? WHERE id = 1;
        """, [cm.map { SQLValue.real($0) } ?? .null, .text(nowText)])
    }

    /// Update the list of sports the user participates in (stored as JSON array).
    public func updateSports(_ sports: [String]) throws {
        try ensureRowExists()
        let jsonData = try JSONEncoder().encode(sports)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        try db.run("""
        UPDATE profile SET sports = ?, updatedAt = ? WHERE id = 1;
        """, [.text(jsonString), .text(nowText)])
    }

    // MARK: - Private

    public func updateBodyMeasurementTrackSides(_ enabled: Bool) throws {
        try ensureRowExists()
        // ponytail: OI-1 stub; preserve historical sides until the owner decides their treatment.
        try db.run("UPDATE profile SET bodyMeasurementTrackSides = ?, updatedAt = ? WHERE id = 1;",
                   [.integer(enabled ? 1 : 0), .text(nowText)])
    }

    // MARK: - Registration

    /// Marks first-run setup as finished.
    ///
    /// Idempotent by design: a second call leaves the first timestamp alone.
    /// Setup can be re-entered — somebody editing their profile mid-flow should
    /// not un-register themselves — and "when did they register" must not be the
    /// time they added a blood type.
    public func markRegistered(_ when: Date? = nil) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE profile SET registeredAt = COALESCE(registeredAt, ?), updatedAt = ? WHERE id = 1;
        """, [.text(Self.iso(when ?? clock.now)), .text(nowText)])
    }

    /// Clears the registration marker. For a person who wants the setup flow back.
    public func clearRegistration() throws {
        try ensureRowExists()
        try db.run("UPDATE profile SET registeredAt = NULL, updatedAt = ? WHERE id = 1;",
                   [.text(nowText)])
    }

    // MARK: - New fields

    public func updateFirstName(_ name: String?) throws {
        try ensureRowExists()
        try db.run("UPDATE profile SET firstName = ?, updatedAt = ? WHERE id = 1;",
                   [name.map { SQLValue.text($0) } ?? .null, .text(nowText)])
    }

    public func updateLastName(_ name: String?) throws {
        try ensureRowExists()
        try db.run("UPDATE profile SET lastName = ?, updatedAt = ? WHERE id = 1;",
                   [name.map { SQLValue.text($0) } ?? .null, .text(nowText)])
    }

    /// Changes the unit masses are shown in.
    public func updateUnitBasis(_ basis: UnitBasis) throws {
        try ensureRowExists()
        try db.run("UPDATE profile SET unitBasis = ?, updatedAt = ? WHERE id = 1;",
                   [.text(basis.rawValue), .text(nowText)])
    }

    public func updateTrainingExperience(_ experience: TrainingExperience) throws {
        try ensureRowExists()
        try db.run("UPDATE profile SET trainingExperience = ?, updatedAt = ? WHERE id = 1;",
                   [.text(experience.rawValue), .text(nowText)])
    }

    public func updateBloodType(_ type: BloodType?) throws {
        try ensureRowExists()
        try db.run("UPDATE profile SET bloodType = ?, updatedAt = ? WHERE id = 1;",
                   [type.map { SQLValue.text($0.rawValue) } ?? .null, .text(nowText)])
    }

    // MARK: - Allergens

    /// Adds one, if not already recorded.
    ///
    /// `INSERT OR IGNORE` against the `(profile_id, allergen_id)` primary key
    /// rather than a read-then-write. The read-then-write has a race that matters
    /// here in a way it does not elsewhere: two taps on the same row should
    /// produce one allergy, and a person with a duplicate peanut row has a
    /// duplicate to notice and remove on a list where duplicates are alarming.
    public func addAllergen(_ allergen: FoodAllergen) throws {
        try ensureRowExists()
        try db.run("""
        INSERT OR IGNORE INTO profile_allergen (profile_id, allergen_id, createdAt)
        VALUES (1, ?, ?);
        """, [.text(allergen.rawValue), .text(nowText)])
    }

    /// Removes one, if recorded. A no-op when it was not there.
    public func removeAllergen(_ allergen: FoodAllergen) throws {
        try db.run("DELETE FROM profile_allergen WHERE profile_id = 1 AND allergen_id = ?;",
                   [.text(allergen.rawValue)])
    }

    /// Replaces the whole set.
    ///
    /// Diffed rather than delete-all-then-insert, so `createdAt` survives on the
    /// allergens a person did not change. It is the only record of when somebody
    /// said they had an allergy, and blowing it away every time they add a second
    /// one destroys it for no gain — the rows are tiny and the diff is one SELECT.
    public func setAllergens(_ allergens: Set<FoodAllergen>) throws {
        try ensureRowExists()
        let wanted = Set(allergens.map(\.rawValue))
        let existing = try db.query("SELECT allergen_id FROM profile_allergen WHERE profile_id = 1;")
            .compactMap { $0.string("allergen_id") }

        for stale in existing where !wanted.contains(stale) {
            try db.run("DELETE FROM profile_allergen WHERE profile_id = 1 AND allergen_id = ?;",
                       [.text(stale)])
        }
        for fresh in wanted.subtracting(existing) {
            try db.run("""
            INSERT OR IGNORE INTO profile_allergen (profile_id, allergen_id, createdAt)
            VALUES (1, ?, ?);
            """, [.text(fresh), .text(nowText)])
        }
    }

    // MARK: - Private

    private func rowToProfile(_ row: Row) -> UserProfile {
        let sports: [String] = (row.string("sports") ?? "[]").decodeJSON() ?? []
        return UserProfile(
            displayName: row.string("displayName") ?? "User",
            firstName: row.string("firstName"),
            lastName: row.string("lastName"),
            dateOfBirth: row.string("dateOfBirth"),
            biologicalSex: row.string("biologicalSex"),
            heightCm: row.double("heightCm"),
            sports: sports,
            unitBasis: UnitBasis.parse(row.string("unitBasis")),
            registeredAt: row.string("registeredAt").flatMap(Self.isoFormatter.date(from:)),
            trainingExperience: TrainingExperience.parse(row.string("trainingExperience")),
            // `rawValue` is failable, so this is a `flatMap` and not a `map` — the
            // column has a CHECK constraint behind it, and a value that somehow
            // failed it should read as "not recorded" rather than crash the
            // profile read at launch.
            bloodType: row.string("bloodType").flatMap(BloodType.init(rawValue:)),
            // Absent on the returned default path, and an empty list on a real row
            // is the correct answer for somebody with none. One extra query, only
            // on the row that exists.
            allergens: (try? allergens()) ?? [],
            createdAt: row.string("createdAt") ?? "",
            updatedAt: row.string("updatedAt") ?? "",
            bodyMeasurementTrackSides: row.int("bodyMeasurementTrackSides") == 1
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
}

// MARK: - JSON Helper Extension

private extension String {
    func decodeJSON<T: Decodable>() -> T? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
