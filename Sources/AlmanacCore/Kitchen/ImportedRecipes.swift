import Foundation

/// Where an imported recipe came from — what CC BY-SA 4.0 asks to be shown
/// with it: the work's title, a link, and the licence.
public struct ImportedRecipeSource: Sendable, Hashable {
    public let source: String
    public let title: String
    public let url: String
    public let revision: Int
    public let licence: String
    /// The serving count the page itself states, when it states one.
    public let statedServings: Int?

    /// One line, shown with the recipe wherever it appears.
    public var credit: String {
        localized("From the Wikibooks Cookbook, CC BY-SA 4.0. Amounts converted to grams.")
    }

    /// The page, as a link.
    public var pageURL: URL? { URL(string: url) }
}

/// Kitchen's recipes from the Wikibooks Cookbook (owner, T04, 2026-10-16).
///
/// The recipes are built by `tools/recipes` from the Cookbook's pages: each
/// ingredient line resolved to a catalog food and a weight in grams, or set
/// aside as a seasoning ("salt, to taste"); a recipe with any other line was
/// left out whole. The bundle is `Kitchen/Resources/wikibooks-recipes.json`.
///
/// ## An imported recipe is an `almanac:` dish
///
/// So everything Kitchen already does applies to it unchanged — the ingredient
/// table, the allergen check, one-serving pre-fill, logging. What marks it as
/// imported is its `kitchen_recipe_source` row (Migration 062), which carries
/// the credit. `nutrition_food.licence_group` stays `N`: it describes the
/// nutrition values, which are reduced on this device from the components'
/// own (USDA, CoFID, CIQUAL, AFCD) values, and the column admits only A, B and
/// N. The recipe's own licence is in `kitchen_recipe_source.licence`
/// (`CONTEXT.md`, Kitchen recipes).
///
/// ## Serving counts
///
/// A page that states its servings sets the count on first install. One that
/// does not is left without, and Kitchen asks the first time it is chosen
/// (`CONTEXT.md`, Kitchen 2026-10-06). A count the person set is never
/// overwritten by a later install.
public enum WikibooksRecipeBundle {
    public static let source = "wikibooks"
    /// The bundled file, as `tools/recipes` writes it.
    public static var resourceURL: URL {
        Bundle.module.bundleURL.appendingPathComponent("wikibooks-recipes.json")
    }

    /// The dish ref an imported page becomes.
    public static func ref(forPageID id: String) -> SourceIdentifier {
        SourceIdentifier(namespace: .almanac, localID: "wikibooks-" + id)
    }

    /// Installs the bundled recipes when they are missing or the bundle
    /// changed. Returns the number installed, or nil when the installed bundle
    /// already has the same SHA-256. Run after the nutrition reference, whose
    /// foods the recipes are made of.
    @discardableResult
    public static func installIfNeeded(into db: Database,
                                       clock: any Clock = SystemClock()) throws -> Int? {
        let data = try Data(contentsOf: resourceURL)
        let sha256 = SHA256File.hex(of: Array(data))
        let installed = try db.query("""
            SELECT bundle_sha256 FROM kitchen_recipe_import WHERE source = ?;
            """, [.text(source)]).first?.string("bundle_sha256")
        guard installed != sha256 else { return nil }
        return try install(data, sha256: sha256, into: db, clock: clock)
    }

    /// Installs `data` as the Wikibooks bundle, in one transaction: every
    /// recipe in it written or updated, every imported recipe no longer in it
    /// removed.
    @discardableResult
    public static func install(_ data: Data, sha256: String, into db: Database,
                               clock: any Clock = SystemClock()) throws -> Int {
        let bundle = try JSONDecoder().decode(Bundle_.self, from: data)
        let editor = NutritionDishEditor(db: db, clock: clock)
        return try db.transaction { () throws -> Int in
            let existing = Set(try db.query("""
                SELECT source_id FROM kitchen_recipe_source WHERE source = ?;
                """, [.text(source)]).compactMap { $0.string("source_id") })
            var seen: Set<String> = []
            for recipe in bundle.recipes {
                guard seen.insert(recipe.id).inserted else { continue }
                let ref = ref(forPageID: recipe.id)
                let isNew = !existing.contains(recipe.id)
                if isNew {
                    try editor.create(localID: ref.localID, nameText: recipe.name)
                } else {
                    var edit = DishEdit()
                    edit.nameText = .set(recipe.name)
                    try editor.update(ref, edit)
                }
                try editor.setRecipe(recipe.components.compactMap { component in
                    SourceIdentifier(parsing: component.ref).map {
                        DishComponent($0, grams: component.grams, noteText: component.line)
                    }
                }, for: ref)
                try db.run("""
                INSERT INTO kitchen_recipe_source
                    (food_ref, source, source_id, title, url, revision, licence, stated_servings)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(food_ref) DO UPDATE SET
                    title = excluded.title, url = excluded.url, revision = excluded.revision,
                    licence = excluded.licence, stated_servings = excluded.stated_servings;
                """, [.text(ref.description), .text(source), .text(recipe.id), .text(recipe.title),
                      .text(recipe.url), .integer(Int64(recipe.revision)), .text(bundle.licence),
                      recipe.servings.map { SQLValue.integer(Int64($0)) } ?? .null])
                if isNew, let servings = recipe.servings {
                    try editor.update(ref, .servings(servings))
                }
            }
            for gone in existing.subtracting(seen) {
                try editor.delete(ref(forPageID: gone))
            }
            try db.run("""
            INSERT INTO kitchen_recipe_import (source, bundle_sha256, recipe_count, imported_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(source) DO UPDATE SET
                bundle_sha256 = excluded.bundle_sha256, recipe_count = excluded.recipe_count,
                imported_at = excluded.imported_at;
            """, [.text(source), .text(sha256), .integer(Int64(seen.count)),
                  .text(ISO8601DateFormatter().string(from: clock.now))])
            return seen.count
        }
    }

    /// Every imported recipe's source, by dish.
    public static func sources(in db: Database) throws -> [SourceIdentifier: ImportedRecipeSource] {
        var result: [SourceIdentifier: ImportedRecipeSource] = [:]
        for row in try db.query("""
            SELECT food_ref, source, title, url, revision, licence, stated_servings
            FROM kitchen_recipe_source;
            """) {
            guard let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let held = source(from: row) else { continue }
            result[ref] = held
        }
        return result
    }

    static func source(from row: Row) -> ImportedRecipeSource? {
        guard let source = row.string("source"), let title = row.string("title"),
              let url = row.string("url"), let revision = row.int("revision"),
              let licence = row.string("licence") else { return nil }
        return ImportedRecipeSource(source: source, title: title, url: url, revision: Int(revision),
                                    licence: licence,
                                    statedServings: row.int("stated_servings").map { Int($0) })
    }

    // MARK: The bundle's shape (tools/recipes/almanac_recipes/build.py)

    struct Bundle_: Decodable {
        let licence: String
        let recipes: [Recipe]
    }

    struct Recipe: Decodable {
        let id: String
        let name: String
        let title: String
        let revision: Int
        let url: String
        let servings: Int?
        let components: [Component]
    }

    struct Component: Decodable {
        let ref: String
        let grams: Double
        let line: String
    }
}
