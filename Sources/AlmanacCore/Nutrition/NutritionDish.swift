import Foundation

// MARK: - Values

/// One ingredient of a dish, by weight.
public struct DishComponent: Sendable, Hashable {
    public let ref: SourceIdentifier
    public let grams: Double
    public let noteText: String?

    public init(_ ref: SourceIdentifier, grams: Double, noteText: String? = nil) {
        self.ref = ref
        self.grams = grams
        self.noteText = noteText
    }
}

/// A dish's own facts — the ones migration 008's bundle-mirrored `nutrition_food`
/// has no room for. Present only for `almanac:` foods.
public struct NativeDish: Sendable, Hashable {
    public let ref: SourceIdentifier
    public let nameText: String
    /// The finished weight, when cooking makes it differ from the sum of the
    /// components. Nil means the sum.
    public let yieldGrams: Double?
    /// CoFID `1.2 Factors`: the fraction of an as-purchased weight that is
    /// edible. Nil where nobody stated one — not 1.0.
    public let edibleProportion: Double?
}

/// What a recipe reduced to, and everything about it that is not known.
///
/// The three "not known" lists are separate because they have different fixes:
/// a missing component needs the reference row, an unmeasured nutrient cannot
/// be fixed at all, and a unit conflict is a canonicalisation bug upstream.
public struct RecipeReduction: Sendable, Hashable {
    /// Per 100 g of the finished dish, qualifier `.calculatedRecipe`, basis
    /// `.per100g` — a dish is always solid.
    public let values: [NutrientValue]
    /// The finished weight the values are per-100-g of: the stated yield, or
    /// the sum of the components when no yield was given.
    public let totalGrams: Double
    /// The raw sum of component weights, before any cooking loss.
    public let componentGrams: Double
    /// Ingredients with no row in the catalog. Their contribution is not
    /// guessed, so every nutrient is affected and none of this is reliable.
    public let missingComponents: [SourceIdentifier]
    /// Nutrients at least one ingredient did not report, or reported as not
    /// analysed. A sum containing an unknown is unknown, so these are omitted
    /// from `values` rather than totalled as though the gap were zero.
    public let unmeasuredNutrients: [String]
    /// Nutrients whose ingredients disagree on the unit. Omitted rather than
    /// added together — the codebase converts no units anywhere else either.
    public let conflictingUnits: [String]

    public var isComplete: Bool {
        missingComponents.isEmpty && unmeasuredNutrients.isEmpty && conflictingUnits.isEmpty
    }
}

/// A correction to a dish's own fields. Component lists are replaced wholesale
/// by `setRecipe`, which is how a person edits a recipe anyway.
public struct DishEdit: Sendable, Hashable {
    public var nameText: FieldEdit<String> = .leaveUnchanged
    public var yieldGrams: FieldEdit<Double> = .leaveUnchanged
    public var edibleProportion: FieldEdit<Double> = .leaveUnchanged

    public init() {}

    public var touchesAnything: Bool {
        nameText.isChange || yieldGrams.isChange || edibleProportion.isChange
    }
}

// MARK: - Editor

/// Authoring for Almanac's own foods — the `almanac:` namespace, and only it.
///
/// A dish is reference data, not a record of the user's body, so it carries no
/// revision history: Laboratory's own catalog rows are upserted the same way
/// for the same reason, while `nutrition_log` — which *is* a record about a
/// person — is revision-tracked. Adding dish revisions later is an additive
/// migration, not a redesign.
///
/// A publisher's row is never editable here. Correcting `usda:1105904` is
/// something USDA does; pretending otherwise would put an Almanac edit behind
/// a publisher's identifier and make the next bundle import silently overwrite
/// it. `NutritionReferenceImporter` never touches `almanac:` rows either way
/// (Migration 010's note), which is what makes that safe.
public struct NutritionDishEditor: Sendable {
    private let db: Database
    private let clock: any Clock
    private let catalog: NutritionCatalog

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
        self.catalog = NutritionCatalog(db: db)
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }

    private static func requireNative(_ ref: SourceIdentifier) throws {
        guard ref.namespace == .almanac else { throw NutritionError.notANativeFood(ref) }
    }

    // MARK: Creating and editing the dish itself

    @discardableResult
    public func create(localID: String, nameText: String,
                       yieldGrams: Double? = nil,
                       edibleProportion: Double? = nil) throws -> SourceIdentifier {
        let ref = SourceIdentifier(namespace: .almanac, localID: localID)
        try db.transaction {
            try db.run("""
            INSERT INTO nutrition_food
                (food_ref, namespace, local_id, licence_group, food_group_code,
                 food_group_name, source_record)
            VALUES (?, ?, ?, ?, 'dish', 'Almanac dish', '')
            ON CONFLICT(food_ref) DO NOTHING;
            """, [.text(ref.description), .text(ref.namespace.rawValue), .text(localID),
                  .text(LicenceGroup.native.rawValue)])
            try writeName(nameText, for: ref)
            try writeDishRow(ref, yieldGrams: yieldGrams, edibleProportion: edibleProportion)
        }
        return ref
    }

    private func writeName(_ nameText: String, for ref: SourceIdentifier) throws {
        try db.run("""
        INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
        VALUES (?, 'en', ?, 1, ?)
        ON CONFLICT(food_ref, language) DO UPDATE SET
            name = excluded.name, is_primary = 1, name_fold = excluded.name_fold;
        """, [.text(ref.description), .text(nameText), .text(TextFold.fold(nameText))])
    }

    private func writeDishRow(_ ref: SourceIdentifier, yieldGrams: Double?,
                              edibleProportion: Double?) throws {
        try db.run("""
        INSERT INTO nutrition_dish (food_ref, yield_grams, edible_proportion, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(food_ref) DO UPDATE SET
            yield_grams = excluded.yield_grams, edible_proportion = excluded.edible_proportion,
            updated_at = excluded.updated_at;
        """, [.text(ref.description), yieldGrams.map { SQLValue.real($0) } ?? .null,
              edibleProportion.map { SQLValue.real($0) } ?? .null, .text(nowText), .text(nowText)])
    }

    public func dish(_ ref: SourceIdentifier) throws -> NativeDish? {
        try NutritionDishEditor.requireNative(ref)
        guard let food = try catalog.food(ref) else { return nil }
        let row = try db.query("""
            SELECT yield_grams, edible_proportion FROM nutrition_dish WHERE food_ref = ?;
            """, [.text(ref.description)]).first
        return NativeDish(ref: ref, nameText: food.primaryName,
                          yieldGrams: row?.double("yield_grams"),
                          edibleProportion: row?.double("edible_proportion"))
    }

    /// Per-100 g values typed in directly — a package label, or a figure the
    /// person knows. The alternative route is `setRecipe`. Always basis
    /// `.per100g`: a dish is solid, and this module has no per-100-mL dishes.
    public func setValues(_ values: [NutrientValue], for ref: SourceIdentifier) throws {
        try NutritionDishEditor.requireNative(ref)
        guard try catalog.food(ref) != nil else { throw NutritionError.foodNotFound(ref) }
        let rows: [(identifier: String, group: LicenceGroup)] = values.map {
            (identifier: "\($0.foodRef):\($0.nutrientID):\($0.basis.rawValue)", group: $0.licenceGroup)
        }
        try BundleGuard.assertShippable(rows)
        try db.transaction {
            try db.run("DELETE FROM nutrition_value WHERE food_ref = ?;", [.text(ref.description)])
            for value in values {
                try db.run("""
                INSERT INTO nutrition_value
                    (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                     source_value, source_nutrient_id, source_unit, licence_group)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [
                    .text(ref.description), .text(value.nutrientID), .text(value.basis.rawValue),
                    value.amount.map { SQLValue.real($0) } ?? .null,
                    .text(value.qualifier.rawValue),
                    value.confidence.map { SQLValue.text($0) } ?? .null,
                    .text(value.sourceValue), .text(value.sourceNutrientID),
                    .text(value.sourceUnit), .text(value.licenceGroup.rawValue)
                ])
            }
        }
    }

    /// Applies a correction. Returns false when the edit changed nothing.
    ///
    /// A changed yield re-reduces the recipe, because the stored per-100 g
    /// values are per 100 g *of the finished dish* — leaving them alone would
    /// keep numbers that no longer describe anything.
    @discardableResult
    public func update(_ ref: SourceIdentifier, _ edit: DishEdit) throws -> Bool {
        try NutritionDishEditor.requireNative(ref)
        guard let held = try dish(ref) else { throw NutritionError.foodNotFound(ref) }
        guard edit.touchesAnything else { return false }

        // A dish must be called something, so `.clear` on the name is a no-op
        // rather than an error case nobody would ever hit deliberately.
        let name = edit.nameText.resolve(held.nameText, cleared: held.nameText)
        let yield = edit.yieldGrams.resolve(held.yieldGrams)
        let edible = edit.edibleProportion.resolve(held.edibleProportion)
        guard name != held.nameText || yield != held.yieldGrams
                || edible != held.edibleProportion else { return false }

        try db.transaction {
            if name != held.nameText { try writeName(name, for: ref) }
            try writeDishRow(ref, yieldGrams: yield, edibleProportion: edible)
        }
        if yield != held.yieldGrams, try !components(of: ref).isEmpty {
            _ = try reduceAndStore(ref, yieldGrams: yield)
        }
        return true
    }

    /// Removes the dish, its values, its recipe and its portions. A food log
    /// entry that pointed at it keeps its own row and its logged name — the
    /// log holds no foreign key here, exactly so that this delete cannot reach
    /// it. `nutrition_dish`, `nutrition_portion` and `nutrition_dish_component`
    /// cascade off `nutrition_food.food_ref`; `nutrition_value` and
    /// `nutrition_food_name` do not (migration 008 predates dishes) and are
    /// deleted explicitly, in FK order.
    @discardableResult
    public func delete(_ ref: SourceIdentifier) throws -> Bool {
        try NutritionDishEditor.requireNative(ref)
        return try db.transaction {
            try db.run("DELETE FROM nutrition_value WHERE food_ref = ?;", [.text(ref.description)])
            try db.run("DELETE FROM nutrition_food_name WHERE food_ref = ?;", [.text(ref.description)])
            return try db.run("DELETE FROM nutrition_food WHERE food_ref = ?;",
                              [.text(ref.description)]) == 1
        }
    }

    public func dishes() throws -> [NativeDish] {
        var result: [NativeDish] = []
        for row in try db.query("""
            SELECT food_ref FROM nutrition_food WHERE namespace = 'almanac' ORDER BY food_ref;
            """) {
            guard let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let held = try dish(ref) else { continue }
            result.append(held)
        }
        return result
    }

    // MARK: The recipe

    public func components(of ref: SourceIdentifier) throws -> [DishComponent] {
        try db.query("""
            SELECT component_ref, grams, note_text FROM nutrition_dish_component
            WHERE dish_ref = ? ORDER BY sequence;
            """, [.text(ref.description)]).compactMap { row in
            guard let componentRef = row.string("component_ref")
                    .flatMap(SourceIdentifier.init(parsing:)),
                  let grams = row.double("grams") else { return nil }
            return DishComponent(componentRef, grams: grams, noteText: row.string("note_text"))
        }
    }

    /// Replaces the recipe and recomputes the dish's per-100 g values from it.
    @discardableResult
    public func setRecipe(_ components: [DishComponent], for ref: SourceIdentifier,
                          yieldGrams: Double? = nil) throws -> RecipeReduction {
        try NutritionDishEditor.requireNative(ref)
        guard let held = try dish(ref) else { throw NutritionError.foodNotFound(ref) }
        for component in components {
            guard component.grams.isFinite, component.grams > 0 else {
                throw NutritionError.invalidGramWeight(component.grams)
            }
            guard try !recipeReaches(ref, from: component.ref) else {
                throw NutritionError.recipeCycle(ref)
            }
        }

        // One transaction over all three writes. A recipe stored with the
        // values of the recipe before it is a dish whose numbers describe
        // nothing, and that is exactly what a failure between these steps used
        // to leave behind.
        return try db.transaction { () throws -> RecipeReduction in
            try db.run("DELETE FROM nutrition_dish_component WHERE dish_ref = ?;",
                       [.text(ref.description)])
            for (index, component) in components.enumerated() {
                try db.run("""
                INSERT INTO nutrition_dish_component
                    (id, dish_ref, component_ref, grams, sequence, note_text)
                VALUES (?, ?, ?, ?, ?, ?);
                """, [
                    .text(UUID().uuidString), .text(ref.description),
                    .text(component.ref.description), .real(component.grams),
                    .integer(Int64(index)),
                    component.noteText.map { SQLValue.text($0) } ?? .null
                ])
            }
            let effectiveYield = yieldGrams ?? held.yieldGrams
            if effectiveYield != held.yieldGrams {
                // Written directly rather than through `update`, whose own
                // recompute would then run against the recipe twice.
                try writeDishRow(ref, yieldGrams: effectiveYield, edibleProportion: held.edibleProportion)
            }
            // Not `recompute`: emptying a recipe deliberately is allowed to
            // empty the values with it, which `recompute` refuses to do.
            return try reduceAndStore(ref, yieldGrams: effectiveYield)
        }
    }

    /// Whether `dish` already appears anywhere under `start`'s recipe.
    ///
    /// A dish may be an ingredient of another dish — that is the point of
    /// reducing to per-100 g values — but a loop is not stale data, it is two
    /// dishes each computed from the other's previous answer, and the
    /// reduction terminates on stored values so it would produce that number
    /// in silence. Walks the graph with a visited set rather than a depth
    /// limit, so a cycle already in the data cannot hang this.
    private func recipeReaches(_ dish: SourceIdentifier,
                               from start: SourceIdentifier) throws -> Bool {
        var queue = [start]
        var seen: Set<SourceIdentifier> = []
        while let next = queue.popLast() {
            guard seen.insert(next).inserted else { continue }
            if next == dish { return true }
            // Only Almanac's own foods have recipes; a publisher's row is a leaf.
            guard next.namespace == .almanac else { continue }
            queue.append(contentsOf: try components(of: next).map(\.ref))
        }
        return false
    }

    /// Re-reduces the stored recipe and writes the result.
    ///
    /// Explicit rather than automatic on read: a dish's values are stored so a
    /// day's total is one query, and recomputing them on every read would make
    /// a correction to an ingredient silently rewrite history instead of being
    /// an action someone took.
    @discardableResult
    public func recompute(_ ref: SourceIdentifier) throws -> RecipeReduction {
        try NutritionDishEditor.requireNative(ref)
        // A dish whose per-100 g values were typed in has nothing to reduce
        // from, and reducing an empty ingredient list yields an empty result —
        // so this would have quietly replaced what the person entered with
        // nothing. Refusing is the only answer that does not lose data.
        guard try !components(of: ref).isEmpty else {
            throw NutritionError.dishHasNoRecipe(ref)
        }
        return try reduceAndStore(ref, yieldGrams: try dish(ref)?.yieldGrams)
    }

    /// The reduction and the write, with no guard. `recompute` is the public
    /// door and carries the guard; `setRecipe` comes in here because emptying a
    /// recipe on purpose is allowed to empty the values with it.
    @discardableResult
    private func reduceAndStore(_ ref: SourceIdentifier, yieldGrams: Double?) throws -> RecipeReduction {
        let reduction = try reduce(try components(of: ref), yieldGrams: yieldGrams, as: ref)
        try setValues(reduction.values, for: ref)
        return reduction
    }

    /// The reduction itself, with no writing. Exposed so a person can see what
    /// a recipe comes to before committing it.
    public func reduce(_ components: [DishComponent], yieldGrams: Double? = nil,
                       as ref: SourceIdentifier = SourceIdentifier(namespace: .almanac,
                                                                   localID: "unsaved-recipe")
    ) throws -> RecipeReduction {
        let componentGrams = components.reduce(0) { $0 + $1.grams }
        let totalGrams = yieldGrams ?? componentGrams

        var missing: [SourceIdentifier] = []
        var loaded: [(component: DishComponent, values: [NutrientValue])] = []
        for component in components {
            guard try catalog.food(component.ref) != nil else {
                missing.append(component.ref)
                continue
            }
            loaded.append((component, try catalog.values(for: component.ref, basis: .per100g)))
        }

        func empty(_ missing: [SourceIdentifier]) -> RecipeReduction {
            RecipeReduction(values: [], totalGrams: totalGrams, componentGrams: componentGrams,
                            missingComponents: missing, unmeasuredNutrients: [],
                            conflictingUnits: [])
        }
        // An ingredient with no reference row contributes an unknown mass of
        // every nutrient. Totalling the rest would understate the dish across
        // the board, so nothing is computed and the gap is named instead.
        guard missing.isEmpty else { return empty(missing) }
        guard totalGrams > 0 else { return empty([]) }

        // Every nutrient any ingredient mentions. One that only some mention is
        // still unmeasured below — an ingredient that does not list iron has
        // not thereby reported zero iron.
        var nutrientIDs: [String] = []
        var seen: Set<String> = []
        for entry in loaded {
            for value in entry.values where !seen.contains(value.nutrientID) {
                seen.insert(value.nutrientID)
                nutrientIDs.append(value.nutrientID)
            }
        }

        var values: [NutrientValue] = []
        var unmeasured: [String] = []
        var conflicting: [String] = []

        for nutrientID in nutrientIDs.sorted() {
            var total = 0.0
            var unit: String?
            var unitConflict = false
            var complete = true

            for entry in loaded {
                guard let value = entry.values.first(where: { $0.nutrientID == nutrientID }),
                      let scaled = value.scaled(toGrams: entry.component.grams) else {
                    complete = false
                    break
                }
                // No unit is converted here, for the same reason `UnitRegistry`
                // converts none in Laboratory: a factor applied silently is a
                // wrong number nobody can see.
                if let unit, UnitRegistry.key(unit) != UnitRegistry.key(value.sourceUnit) {
                    unitConflict = true
                    break
                }
                unit = value.sourceUnit
                total += scaled
            }

            if unitConflict { conflicting.append(nutrientID); continue }
            guard complete else { unmeasured.append(nutrientID); continue }

            values.append(NutrientValue(
                foodRef: ref, nutrientID: nutrientID,
                amount: total / totalGrams * 100,
                qualifier: .calculatedRecipe,
                sourceValue: "sum of \(loaded.count) components over \(totalGrams) g",
                sourceNutrientID: nutrientID, sourceUnit: unit ?? "",
                licenceGroup: ref.namespace.licenceGroup, basis: .per100g))
        }

        return RecipeReduction(values: values, totalGrams: totalGrams,
                               componentGrams: componentGrams, missingComponents: [],
                               unmeasuredNutrients: unmeasured, conflictingUnits: conflicting)
    }
}
