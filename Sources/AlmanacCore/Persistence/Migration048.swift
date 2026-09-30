import Foundation

/// Migration 048 — the profile fields Tasks E and F need, in one migration.
///
/// **Both tasks land in the same file on purpose.** The unit basis (Task E) and
/// the training experience, blood type, allergens and registration state
/// (Task F) are all `profile` columns, and doing them separately would mean two
/// migrations, two renumberings of a table a shipped app cannot renumber, and a
/// window in which `profile` has half its shape. Numbering is free until the
/// first install and expensive forever after — `Migrations.swift` says so at the
/// top, and this is that lesson applied rather than noted.
///
/// Every column is nullable. §5.1's own precedent is a table full of things the
/// person may not have told us, and a NOT NULL on a preference would mean the
/// app invents a value for somebody who has never opened Settings — which is how
/// "practising intermediate" ends up written down for someone who has never
/// touched a barbell.
///
/// **`profile_allergen` is a table, not a JSON column**, unlike `profile.sports`.
/// That inconsistency is deliberate and worth stating, because `sports` is the
/// precedent and following it here would be the obvious move.
///
/// `sports` is free text the person typed, which the UI now offers a picker for
/// but has always accepted as a string; nothing validates it, nothing queries it,
/// and a wrong entry costs nobody anything. An allergen is none of those. It is
/// used to *withhold* a food from somebody, so the list has to be a closed set
/// (`food_allergen` is the same 14 rows for every install), an unknown value has
/// to be impossible rather than merely unlikely, and the person has to be able to
/// see, change and revoke each entry individually. A JSON blob cannot do that last
/// one without rewriting the whole document to remove one element, which is
/// precisely the operation a person performs when a reaction gets better.
///
/// `registered_at` is one column rather than a state machine, because the only
/// two states worth distinguishing are "has set the app up" and "has not", and a
/// boolean with a timestamp of when it became true says both in a value that
/// cannot drift into a third state nobody designed.
public enum Migration048_ProfileFields: Migration {
    public static let version = 48
    public static let name = "profile_fields"

    public static func up(_ db: Database) throws {
        // --- Task E: the unit basis masses are displayed in. ----------------
        // A CHECK rather than a plain TEXT so a bad value cannot be stored at all.
        // Kilograms as the default, because every `body_composition_measurement`
        // row already holds kilograms — a database that has never been told
        // otherwise must not start displaying pounds.
        try db.execute("""
        ALTER TABLE profile ADD COLUMN unitBasis TEXT NOT NULL DEFAULT 'kilograms'
            CHECK (unitBasis IN ('kilograms', 'pounds'));
        """)

        // --- Task F: the registration gate. ---------------------------------
        try db.execute("""
        ALTER TABLE profile ADD COLUMN registeredAt TEXT;
        """)

        // --- Task F: the name split. ----------------------------------------
        // `displayName` is **kept, not replaced**. It is the greeting on every
        // screen, it is what every existing install holds, and "which name do you
        // show" is a product decision — overwriting it with a derived value would
        // answer that question by rewriting somebody's existing row. So the new
        // columns start empty and the derived `UserProfile.preferredName` answers
        // the question from them when one is present.
        //
        // Not NOT NULL and not defaulted: "Yazeed" is §5.1's default for a table
        // nobody has written to, and inheriting it as a *first name* would put a
        // name in every profile that nobody gave.
        try db.execute("""
        ALTER TABLE profile ADD COLUMN firstName TEXT;
        ALTER TABLE profile ADD COLUMN lastName TEXT;
        """)

        // --- Task F: how long this person has been training. ----------------
        // The set the handoff names — novice / beginner / moderate / expert —
        // plus `not_set`, for the same reason `biologicalSex` has `not_set`:
        // "I have not said" and "I have said something the app cannot store" lead
        // to the same place, and neither should present itself as an error the
        // other is not.
        try db.execute("""
        ALTER TABLE profile ADD COLUMN trainingExperience TEXT
            CHECK (trainingExperience IN ('not_set', 'novice', 'beginner', 'intermediate', 'advanced'));
        """)

        // --- Task F: blood type. --------------------------------------------
        // `unknown` is a first-class member and not the null: it is a thing people
        // are, and "I don't know" is a different statement from "not asked yet".
        // The Rh factor is a suffix on the type, so `A+` is one value rather than
        // two fields that could disagree.
        try db.execute("""
        ALTER TABLE profile ADD COLUMN bloodType TEXT
            CHECK (bloodType IS NULL OR bloodType IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown'));
        """)

        // --- Task F: the closed set of allergens, and which of them apply. ----
        // Seeded by the migration rather than looked up in code, so a row can
        // carry a label and so the set is data — which is what lets it be
        // extended by a later migration without rewriting a Swift enum's
        // meaning. `id` is the stable key; `label` is prose that will be
        // reworded; `sort_order` is so a picker does not order itself by
        // whichever way SQLite happens to return the rows.
        try db.execute("""
        CREATE TABLE food_allergen (
            id          TEXT    PRIMARY KEY,
            label       TEXT    NOT NULL,
            sort_order  INTEGER NOT NULL
        );
        """)
        try db.execute("""
        INSERT INTO food_allergen (id, label, sort_order) VALUES
            ('gluten',  'Gluten / cereals',     1),
            ('crustaceans', 'Crustaceans',     2),
            ('eggs',    'Eggs',                  3),
            ('fish',    'Fish',                  4),
            ('peanuts', 'Peanuts',               5),
            ('soy',     'Soy',                   6),
            ('milk',    'Milk',                  7),
            ('nuts',    'Tree nuts',             8),
            ('celery',  'Celery',                9),
            ('mustard', 'Mustard',              10),
            ('sesame',  'Sesame',               11),
            ('sulphites', 'Sulphites',          12),
            ('lupin',   'Lupin',                13),
            ('molluscs', 'Molluscs',            14);
        """)

        // Which of them apply to this person. `profile_id` rather than assuming
        // id = 1 at the schema level, because the singleton is a decision
        // `ProfileStore` makes and a table that encodes it stops the day that is
        // revisited. `(profile_id, allergen_id)` is the primary key, so the same
        // allergen cannot be added twice — a duplicate allergy row is a row
        // somebody has to notice and remove, and on a safety list that is a
        // defect, not a cosmetic one.
        try db.execute("""
        CREATE TABLE profile_allergen (
            profile_id   INTEGER NOT NULL,
            allergen_id  TEXT    NOT NULL REFERENCES food_allergen(id),
            createdAt    TEXT    NOT NULL,
            PRIMARY KEY (profile_id, allergen_id)
        );
        """)

        // **No index on `allergen_id`, and that is a measured decision rather than
        // an omission.** There was one here, added for the food gate's join, and
        // `EXPLAIN QUERY PLAN` on the one query the gate runs
        // (`Migration048Tests.allergenLookupIsIndexed`) reported that SQLite never
        // touches it:
        //
        //     SEARCH pa USING COVERING INDEX sqlite_autoindex_profile_allergen_1 (profile_id=?)
        //     SEARCH a  USING INDEX sqlite_autoindex_food_allergen_1 (id=?)
        //     USE TEMP B-TREE FOR ORDER BY
        //
        // The `(profile_id, allergen_id)` primary key already covers the lookup,
        // because the only question anyone asks is "this person's allergens". An
        // index on `allergen_id` serves the reverse question — who has this
        // allergy — which is a multi-tenant query this app has no concept of, since
        // `ProfileStore` treats the profile as a singleton. It was an index for a
        // query that does not exist, paying for itself in write cost on every
        // allergy added.
        //
        // The `ORDER BY a.sort_order` temp b-tree is left alone for the same
        // reason: it sorts the result of a join whose input is at most 14 rows.
        // Making that a real index would mean storing `sort_order` twice and
        // keeping the two in step.
    }
}
