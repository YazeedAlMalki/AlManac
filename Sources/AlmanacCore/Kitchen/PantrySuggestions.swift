import Foundation

/// A food Kitchen offers to add to the pantry, because it is logged often.
public struct PantrySuggestion: Sendable, Hashable {
    public let ref: SourceIdentifier
    /// The catalog's name, else the name it was logged under.
    public let name: String?
    /// Distinct logical days in the window on which it was logged.
    public let daysLogged: Int
}

/// Offers to add often-logged foods to the declared pantry; adds nothing itself.
///
/// The owner's call (2026-10-06): the pantry is **declared, with suggestions** —
/// Kitchen may offer foods he logs often, he approves or dismisses each, and
/// nothing is added automatically. `KitchenPantry`'s "declared, not inferred"
/// rule stands; this only proposes, and `accept` is the person's tap.
///
/// ## The rule (unconfirmed — `CONTEXT.md`, Kitchen 2026-10-06)
///
/// A food is offered when it was logged on at least `minimumDays` distinct
/// logical days among the last `windowDays` (today included), is not already in
/// the pantry, has not been dismissed, and is not itself a recipe — a recipe is
/// made from a pantry, not kept in one. Days, not entries: three eggs at one
/// breakfast are one day of eggs. Logical days by §7.1's 04:00 boundary, read
/// through `NutritionSummary` so a day here is the day the log screen shows.
public struct PantrySuggestions: Sendable {
    public static let minimumDays = 3
    public static let windowDays = 14

    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    /// Suggestions as of `today`, most-logged first, then by name.
    public func suggestions(today: LogicalDay, timeModel: TimeModel) throws -> [PantrySuggestion] {
        let summary = NutritionSummary(db: db)
        var days: [SourceIdentifier: Set<String>] = [:]
        var names: [SourceIdentifier: String] = [:]
        var day = today
        for _ in 0..<Self.windowDays {
            for logged in try summary.loggedFoods(on: day, in: timeModel) ?? [] {
                let ref = logged.entry.foodRef
                days[ref, default: []].insert(day.value)
                if names[ref] == nil {
                    names[ref] = logged.food?.primaryName ?? logged.entry.foodNameText
                }
            }
            guard let previous = timeModel.day(before: day) else { break }
            day = previous
        }

        let frequent = days.filter { $0.value.count >= Self.minimumDays }.map(\.key)
        guard !frequent.isEmpty else { return [] }
        let pantry = try KitchenPantry(db: db).refs()
        let dismissed = try self.dismissed()
        let recipes = try recipesAmong(frequent)

        return frequent
            .filter { !pantry.contains($0) && !dismissed.contains($0) && !recipes.contains($0) }
            .map { PantrySuggestion(ref: $0, name: names[$0], daysLogged: days[$0]?.count ?? 0) }
            .sorted {
                if $0.daysLogged != $1.daysLogged { return $0.daysLogged > $1.daysLogged }
                let a = $0.name ?? $0.ref.description, b = $1.name ?? $1.ref.description
                switch a.compare(b, options: .caseInsensitive) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return $0.ref.description < $1.ref.description
                }
            }
    }

    /// The person approved: add it to the pantry.
    public func accept(_ suggestion: PantrySuggestion) throws {
        try KitchenPantry(db: db, clock: clock).add(suggestion.ref, nameText: suggestion.name)
    }

    /// The person declined: never offer this food again.
    public func dismiss(_ ref: SourceIdentifier) throws {
        try db.run("""
        INSERT INTO kitchen_pantry_dismissal (food_ref, dismissed_at) VALUES (?, ?)
        ON CONFLICT(food_ref) DO NOTHING;
        """, [.text(ref.description), .text(ISO8601DateFormatter().string(from: clock.now))])
    }

    public func dismissed() throws -> Set<SourceIdentifier> {
        Set(try db.query("SELECT food_ref FROM kitchen_pantry_dismissal;")
            .compactMap { $0.string("food_ref").flatMap(SourceIdentifier.init(parsing:)) })
    }

    /// Which of `refs` are recipes — dishes with at least one component.
    private func recipesAmong(_ refs: [SourceIdentifier]) throws -> Set<SourceIdentifier> {
        let json = String(decoding: try JSONEncoder().encode(refs.map(\.description).sorted()), as: UTF8.self)
        return Set(try db.query("""
            SELECT DISTINCT dish_ref FROM nutrition_dish_component
            WHERE dish_ref IN (SELECT value FROM json_each(?));
            """, [.text(json)]).compactMap { $0.string("dish_ref").flatMap(SourceIdentifier.init(parsing:)) })
    }
}
