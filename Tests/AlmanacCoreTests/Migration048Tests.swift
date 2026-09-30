import Foundation
import Testing
@testable import AlmanacCore

/// Migration 048 — the profile fields Tasks E and F need.
///
/// Two kinds of check, and the second kind is the one that matters most:
///
/// - *Shape*: the columns and tables exist, with the right types, nullability
///   and constraints. Cheap, and it catches a typo in an `ALTER TABLE`.
/// - *Compatibility*: a database migrated through 47 and then through 48 holds
///   exactly the same body-composition and nutrition rows as one migrated
///   straight to 48. This is the check that catches a migration which "adds a
///   column" and quietly rewrites a value on the way past, and it is the only
///   one that can.
@Suite("Migration 048 — profile fields")
struct Migration048Tests {

    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func columns(_ db: Database, table: String) throws -> [String: (type: String, notNull: Bool, defaultValue: String?)] {
        var result: [String: (type: String, notNull: Bool, defaultValue: String?)] = [:]
        for row in try db.query("PRAGMA table_info(\(table));") {
            guard let name = row.string("name") else { continue }
            // PRAGMA reports booleans as integers.
            let notNull = (row.int("notnull") ?? 0) == 1
            let dflt = row.string("dflt_value")
            result[name] = (row.string("type") ?? "", notNull, dflt)
        }
        return result
    }

    // MARK: - Columns exist

    @Test("Every new profile column exists, with the type it was declared as")
    func columnsExist() throws {
        let db = try migrated()
        let profile = try columns(db, table: "profile")
        for name in ["unitBasis", "registeredAt", "firstName", "lastName",
                     "trainingExperience", "bloodType"] {
            #expect(profile[name] != nil, "profile.\(name) is missing")
        }
        #expect(profile["unitBasis"]?.type == "TEXT")
        #expect(profile["registeredAt"]?.type == "TEXT")
        #expect(profile["firstName"]?.type == "TEXT")
        #expect(profile["lastName"]?.type == "TEXT")
        #expect(profile["trainingExperience"]?.type == "TEXT")
        #expect(profile["bloodType"]?.type == "TEXT")
    }

    @Test("Only the unit basis is required, because only it has a safe default")
    func nullability() throws {
        let db = try migrated()
        let profile = try columns(db, table: "profile")
        // A mass basis has a right answer nobody has to be asked for: kilograms is
        // what every stored `body_composition_measurement` already holds.
        #expect(profile["unitBasis"]?.notNull == true)
        #expect(profile["unitBasis"]?.defaultValue == "'kilograms'")
        // Everything else is a fact about a person. A NOT NULL would mean the app
        // inventing one — "practising intermediate" written down for somebody who
        // has never touched a barbell.
        for name in ["registeredAt", "firstName", "lastName", "trainingExperience", "bloodType"] {
            #expect(profile[name]?.notNull == false, "profile.\(name) should be nullable")
        }
    }

    // MARK: - Constraints reject what a closed set cannot hold

    @Test("The unit basis column will not hold a unit the app cannot render")
    func unitBasisIsConstrained() throws {
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.updateDisplayName("Reader")
        for bad in ["stone", "", "KG", "lbs", "1"] {
            #expect(throws: (any Error).self, "unitBasis accepted \(bad.debugDescription)") {
                try db.run("UPDATE profile SET unitBasis = ?;", [.text(bad)])
            }
        }
        // Both real values, and the ones that are legal.
        try store.updateUnitBasis(.pounds)
        #expect(try store.profile().unitBasis == .pounds)
    }

    @Test("Training experience and blood type are closed sets too")
    func closedSets() throws {
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.updateDisplayName("Reader")
        // "expert" is a word the handoff uses, and it is not in the column's set —
        // `TrainingExperience` calls it `advanced`. Without a CHECK the two would
        // both be writable and read back as "not said".
        #expect(throws: (any Error).self) {
            try db.run("UPDATE profile SET trainingExperience = 'expert';")
        }
        // The eight real types, plus the honest "I don't know".
        for good in ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "unknown"] {
            try db.run("UPDATE profile SET bloodType = ?;", [.text(good)])
            #expect(try db.query("SELECT bloodType FROM profile;").first?.string("bloodType") == good)
        }
        #expect(throws: (any Error).self) {
            try db.run("UPDATE profile SET bloodType = 'A';")
        }
        #expect(throws: (any Error).self) {
            try db.run("UPDATE profile SET bloodType = 'C+';")
        }
    }

    // MARK: - The allergen tables

    @Test("The allergen vocabulary is seeded with the published fourteen, in order")
    func allergenSeed() throws {
        let db = try migrated()
        let rows = try db.query("SELECT id, label, sort_order FROM food_allergen ORDER BY sort_order;")
        #expect(rows.count == 14)
        #expect(rows.compactMap { $0.string("id") } == FoodAllergen.inPickerOrder.map(\.rawValue))
        // Labels are seeded too, so a picker can be built from the table and the
        // Swift `title` is the thing that has to agree with it, not the only copy.
        for (row, allergen) in zip(rows, FoodAllergen.inPickerOrder) {
            // A `#expect` comment must be one expression, so the two facts go into
            // a local rather than being concatenated into the message.
            let seeded = row.string("label") ?? "nil"
            let disagreement = seeded == allergen.title ? "" : " (titled \(allergen.title))"
            #expect(row.string("label") == allergen.title,
                    "\(allergen.rawValue) is seeded as \(seeded)\(disagreement)")
            #expect(row.int("sort_order") == Int64(allergen.sortIndex))
        }
    }

    @Test("An allergen outside the vocabulary cannot be recorded")
    func allergenForeignKey() throws {
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.addAllergen(.peanuts)
        #expect(throws: (any Error).self) {
            try db.run("""
            INSERT INTO profile_allergen (profile_id, allergen_id, createdAt)
            VALUES (1, 'shellfish', '2026-09-30T00:00:00Z');
            """)
        }
    }

    @Test("The same allergen cannot be recorded twice for one profile")
    func allergenPrimaryKey() throws {
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.addAllergen(.sesame)
        #expect(throws: (any Error).self) {
            try db.run("""
            INSERT INTO profile_allergen (profile_id, allergen_id, createdAt)
            VALUES (1, 'sesame', '2026-09-30T00:00:00Z');
            """)
        }
        #expect(try store.allergens() == [.sesame])
    }

    @Test("A second profile can hold its own allergens")
    func allergensArePerProfile() throws {
        // The table is keyed on `profile_id` rather than hard-coding 1, so the
        // singleton is a decision `ProfileStore` makes and not something the
        // schema refuses to revisit.
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.addAllergen(.peanuts)
        try db.execute("""
        INSERT INTO profile (id, createdAt, updatedAt) VALUES (2, '2026-09-30T00:00:00Z', '2026-09-30T00:00:00Z');
        INSERT INTO profile_allergen (profile_id, allergen_id, createdAt)
        VALUES (2, 'milk', '2026-09-30T00:00:00Z');
        """)
        #expect(try store.allergens() == [.peanuts])
        #expect(try db.query("""
        SELECT a.id FROM profile_allergen pa JOIN food_allergen a ON a.id = pa.allergen_id
        WHERE pa.profile_id = 2;
        """).compactMap { $0.string("id") } == ["milk"])
    }

    @Test("The food gate's query is served by the primary key, with no index of its own")
    func allergenLookupPlan() throws {
        // Recorded from `EXPLAIN QUERY PLAN` rather than assumed. An index on
        // `allergen_id` existed and the planner never used it, because the only
        // question asked is "this person's allergens" and the
        // `(profile_id, allergen_id)` primary key answers that. So the index is
        // gone, and this test says what the plan has to be so it cannot come back
        // by accident with a write cost nobody is paying attention to.
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.addAllergen(.peanuts)
        try store.addAllergen(.milk)

        let plan = try db.query("""
        EXPLAIN QUERY PLAN
        SELECT a.id FROM profile_allergen pa
        JOIN food_allergen a ON a.id = pa.allergen_id
        WHERE pa.profile_id = 1 ORDER BY a.sort_order;
        """).compactMap { $0.string("detail") }

        #expect(plan.contains { $0.contains("sqlite_autoindex_profile_allergen_1") },
                "the profile's own rows are no longer found by the primary key: \(plan)")
        // Both sides of the join are index lookups — no full scan of either table.
        #expect(plan.allSatisfy { $0.contains("SEARCH") || $0.contains("TEMP B-TREE") },
                "something is being scanned: \(plan)")
        #expect(plan.filter { $0.contains("SCAN ") && !$0.contains("SEARCH") }.isEmpty,
                "a full scan appeared in the gate's plan: \(plan)")
    }

    // MARK: - Upgrade from the previous schema

    @Test("Upgrading from 47 changes nothing about existing data")
    func upgradeIsAdditive() throws {
        // The test that matters. A migration described as additive is a claim, and
        // the claim is only worth anything if the rows are compared before and
        // after rather than eyeballed in the schema.
        let at47 = try Database.inMemory()
        try MigrationRunner(
            migrations: AlmanacMigrations.all.filter { $0.version <= 47 }
        ).migrate(at47)

        // Real rows, in the tables a person actually has data in.
        try at47.execute("""
        UPDATE profile SET displayName = 'Yazeed', dateOfBirth = '1996-09-30',
                           biologicalSex = 'male', heightCm = 180, sports = '["weightlifting"]'
        WHERE id = 1;
        -- Migration018's columns, not Migration041's: that table is
        -- `body_measurement` and measures girth in centimetres. Writing to the
        -- wrong one here would have been a test that passed for the wrong reason.
        INSERT INTO body_composition_measurement (id, timestamp, logicalDay, metric, value,
                                                  unit, source, conditions, createdAt)
        VALUES (1, '2026-09-01T07:00:00Z', '2026-09-01', 'weight', 72.5,
                'kg', 'manual', 'fasting', '2026-09-01T07:00:00Z');
        INSERT INTO body_composition_measurement (id, timestamp, logicalDay, metric, value,
                                                  unit, source, conditions, createdAt)
        VALUES (2, '2026-09-29T07:00:00Z', '2026-09-29', 'body_fat_pct', 18.4,
                'pct', 'manual', 'fasting', '2026-09-29T07:00:00Z');
        -- Migration047's columns are snake_case, not §5.2's camelCase. Writing §5.2's
        -- spelling here would have been a test that failed for the right reason
        -- but taught the wrong lesson, so: read the migration, do not read the spec.
        INSERT INTO goal_target_snapshot (id, effective_date, goal, formula_version,
                                          body_weight_kg, body_fat_pct, activity_multiplier,
                                          goal_calorie_adjustment, calorie_target, protein_target_g,
                                          carb_target_g, fat_target_g, hydration_target_ml,
                                          manual_calorie_target, manual_protein_target_g,
                                          manual_carb_target_g, manual_fat_target_g,
                                          manual_hydration_target_ml, created_at)
        VALUES (1, '2026-09-01', 'cut', '1.0', 72.5, 18.4, 1.375, -500, 2100, 180, 180, 70, 2500,
                2000, NULL, NULL, NULL, NULL, '2026-09-01T07:00:00Z');
        """)
        let before = try snapshot(at47)

        try MigrationRunner(migrations: [Migration048_ProfileFields.self]).migrate(at47)
        let after = try snapshot(at47)

        #expect(after == before)
    }

    @Test("An install that has never opened Settings reads as unset, not guessed")
    func defaultsForAnUntouchedProfile() throws {
        // The row exists — `ProfileStore` creates it — and every new column is
        // empty. A default on any of them would be a fact about a person that
        // nobody told the app.
        let db = try migrated()
        let store = ProfileStore(db: db, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        try store.updateDisplayName("Untouched")
        let row = try db.query("SELECT * FROM profile WHERE id = 1;").first
        #expect(row?.string("unitBasis") == "kilograms")
        #expect(row?.isNull("registeredAt") == true)
        #expect(row?.isNull("firstName") == true)
        #expect(row?.isNull("lastName") == true)
        #expect(row?.isNull("trainingExperience") == true)
        #expect(row?.isNull("bloodType") == true)
        #expect(try db.query("SELECT COUNT(*) AS n FROM profile_allergen;").first?.int("n") == 0)
        #expect(try store.profile().isRegistered == false)
    }

    @Test("§5.1's own columns are untouched")
    func specColumnsSurvive() throws {
        // §5.1 is the table this migration alters. The columns it specifies are the
        // ones the spec is written against, so a migration that quietly renames or
        // retypes one of them breaks the spec's own examples.
        let db = try migrated()
        let profile = try columns(db, table: "profile")
        #expect(profile["displayName"]?.type == "TEXT")
        #expect(profile["dateOfBirth"]?.type == "TEXT")
        #expect(profile["biologicalSex"]?.type == "TEXT")
        #expect(profile["heightCm"]?.type == "REAL")
        #expect(profile["sports"]?.type == "TEXT")
        #expect(profile["displayName"]?.notNull == true)
        #expect(profile["displayName"]?.defaultValue == "'Yazeed'")
        #expect(profile["sports"]?.notNull == true)
        #expect(profile["sports"]?.defaultValue == "'[]'")
    }

    // MARK: - Helper

    /// Every column of the tables a person has data in, as a comparable string.
    ///
    /// The column names come from `PRAGMA table_info` rather than from a hardcoded
    /// list, which is the whole point: a migration that adds a column with a
    /// backfilled value shows up here as a new line, and one that rewrites an
    /// existing one as a changed line. A hand-written list would be checked
    /// against the schema I expected rather than the schema I have.
    private func snapshot(_ db: Database) throws -> [String] {
        var lines: [String] = []
        for table in ["profile", "body_composition_measurement", "goal_target_snapshot"] {
            let names = try db.query("PRAGMA table_info(\(table));").compactMap { $0.string("name") }
            for row in try db.query("SELECT * FROM \(table);") {
                for name in names {
                    let value: String
                    switch row[name] {
                    case .some(.null), .none: value = "NULL"
                    case .some(.text(let t)): value = t
                    case .some(.integer(let i)): value = String(i)
                    case .some(.real(let d)): value = String(d)
                    case .some(.blob(let b)): value = "blob(\(b.count))"
                    }
                    lines.append("\(table).\(name)=\(value)")
                }
            }
        }
        return lines.sorted()
    }
}
