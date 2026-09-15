import Foundation

/// Distinguishes a figure Almanac can stand behind from one it cannot.
///
/// Every nutrient value elsewhere in Almanac — USDA, CIQUAL, CoFID, AFCD —
/// carries a licence group and a `source_value` that traces back to a
/// published food-composition table. The built-in drink catalog below has
/// none of that: its calorie/sodium/sugar figures are typical values for a
/// named product, not independently verified against any cited source. This
/// qualifier travels with every logged entry so that distinction is never
/// silently lost (see `Migration013`).
public enum DrinkValueQualifier: String, Sendable, Hashable, Codable {
    /// A built-in catalog entry. Typical, uncited, never `measured`.
    case catalogUnsourcedEstimate = "catalog_unsourced_estimate"
    /// The user typed these figures in for a custom drink. Also not a cited
    /// source, but the user's own claim about their own drink rather than an
    /// Almanac-shipped assertion.
    case userEntered = "user_entered"
}

/// A beverage with nutrition figures — either a built-in catalog entry
/// (`isCustom == false`, lives only in this file) or a user-authored one
/// persisted in `hydration_drink`.
public struct Drink: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let liquidType: LiquidType
    public let volumeMilliliters: Double
    public let caloriesKcal: Double
    public let sodiumMilligrams: Double
    public let sugarGrams: Double?
    public let isCustom: Bool
    public let valueQualifier: DrinkValueQualifier
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        liquidType: LiquidType,
        volumeMilliliters: Double,
        caloriesKcal: Double,
        sodiumMilligrams: Double,
        sugarGrams: Double? = nil,
        isCustom: Bool = false,
        valueQualifier: DrinkValueQualifier = .catalogUnsourcedEstimate,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.liquidType = liquidType
        self.volumeMilliliters = volumeMilliliters
        self.caloriesKcal = caloriesKcal
        self.sodiumMilligrams = sodiumMilligrams
        self.sugarGrams = sugarGrams
        self.isCustom = isCustom
        self.valueQualifier = valueQualifier
        self.createdAt = createdAt
    }
}

/// Standard catalog of common beverages. Ships with the app — no per-install
/// state, no database row. Every figure here is `catalogUnsourcedEstimate`:
/// typical values for the named product, not read from a cited
/// food-composition table. Do not present these as measured anywhere in the
/// UI without that qualifier visible.
public enum CatalogDrinks {
    public static let all: [Drink] = [
        Drink(id: "catalog_water", name: "Water", liquidType: .water,
              volumeMilliliters: 250, caloriesKcal: 0, sodiumMilligrams: 0),

        Drink(id: "catalog_pepsi", name: "Pepsi", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 150, sodiumMilligrams: 30, sugarGrams: 41),
        Drink(id: "catalog_coke", name: "Coca-Cola", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 140, sodiumMilligrams: 34, sugarGrams: 39),
        Drink(id: "catalog_sprite", name: "Sprite", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 140, sodiumMilligrams: 65, sugarGrams: 38),
        Drink(id: "catalog_fanta", name: "Fanta", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 160, sodiumMilligrams: 45, sugarGrams: 42),

        Drink(id: "catalog_pepsi_diet", name: "Diet Pepsi", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 0, sodiumMilligrams: 35, sugarGrams: 0),
        Drink(id: "catalog_coke_diet", name: "Diet Coke", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 0, sodiumMilligrams: 46, sugarGrams: 0),
        Drink(id: "catalog_coke_zero", name: "Coke Zero", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 0, sodiumMilligrams: 50, sugarGrams: 0),

        Drink(id: "catalog_gatorade", name: "Gatorade (Orange)", liquidType: .sportsDrink,
              volumeMilliliters: 591, caloriesKcal: 140, sodiumMilligrams: 290, sugarGrams: 37),
        Drink(id: "catalog_powerade", name: "Powerade (Fruit Punch)", liquidType: .sportsDrink,
              volumeMilliliters: 591, caloriesKcal: 150, sodiumMilligrams: 200, sugarGrams: 39),
        Drink(id: "catalog_gatorade_zero", name: "Gatorade Zero", liquidType: .sportsDrink,
              volumeMilliliters: 591, caloriesKcal: 0, sodiumMilligrams: 310, sugarGrams: 0),

        Drink(id: "catalog_pedialyte", name: "Pedialyte", liquidType: .electrolyteSolution,
              volumeMilliliters: 1000, caloriesKcal: 0, sodiumMilligrams: 750, sugarGrams: 25),
        Drink(id: "catalog_coconut_water", name: "Coconut Water", liquidType: .coconutWater,
              volumeMilliliters: 240, caloriesKcal: 45, sodiumMilligrams: 250, sugarGrams: 9),

        Drink(id: "catalog_coffee_black", name: "Black Coffee", liquidType: .coffee,
              volumeMilliliters: 240, caloriesKcal: 2, sodiumMilligrams: 5, sugarGrams: 0),
        Drink(id: "catalog_coffee_latte", name: "Latte (2% Milk)", liquidType: .coffee,
              volumeMilliliters: 240, caloriesKcal: 150, sodiumMilligrams: 150, sugarGrams: 12),
        Drink(id: "catalog_coffee_cappuccino", name: "Cappuccino", liquidType: .coffee,
              volumeMilliliters: 240, caloriesKcal: 120, sodiumMilligrams: 120, sugarGrams: 8),

        Drink(id: "catalog_tea_black", name: "Black Tea", liquidType: .tea,
              volumeMilliliters: 240, caloriesKcal: 2, sodiumMilligrams: 0, sugarGrams: 0),
        Drink(id: "catalog_tea_green", name: "Green Tea", liquidType: .tea,
              volumeMilliliters: 240, caloriesKcal: 2, sodiumMilligrams: 0, sugarGrams: 0),
        Drink(id: "catalog_iced_tea", name: "Iced Tea (Sweetened)", liquidType: .tea,
              volumeMilliliters: 240, caloriesKcal: 90, sodiumMilligrams: 10, sugarGrams: 22),

        Drink(id: "catalog_milk_whole", name: "Whole Milk", liquidType: .milk,
              volumeMilliliters: 240, caloriesKcal: 150, sodiumMilligrams: 120, sugarGrams: 12),
        Drink(id: "catalog_milk_skim", name: "Skim Milk", liquidType: .milk,
              volumeMilliliters: 240, caloriesKcal: 80, sodiumMilligrams: 125, sugarGrams: 12),
        Drink(id: "catalog_chocolate_milk", name: "Chocolate Milk", liquidType: .milk,
              volumeMilliliters: 240, caloriesKcal: 190, sodiumMilligrams: 150, sugarGrams: 24),

        Drink(id: "catalog_orange_juice", name: "Orange Juice", liquidType: .juice,
              volumeMilliliters: 240, caloriesKcal: 110, sodiumMilligrams: 0, sugarGrams: 26),
        Drink(id: "catalog_apple_juice", name: "Apple Juice", liquidType: .juice,
              volumeMilliliters: 240, caloriesKcal: 114, sodiumMilligrams: 10, sugarGrams: 29),
        Drink(id: "catalog_cranberry_juice", name: "Cranberry Juice", liquidType: .juice,
              volumeMilliliters: 240, caloriesKcal: 137, sodiumMilligrams: 60, sugarGrams: 33),

        Drink(id: "catalog_redbull", name: "Red Bull", liquidType: .other,
              volumeMilliliters: 250, caloriesKcal: 110, sodiumMilligrams: 200, sugarGrams: 27),
        Drink(id: "catalog_monster", name: "Monster Energy", liquidType: .other,
              volumeMilliliters: 355, caloriesKcal: 160, sodiumMilligrams: 370, sugarGrams: 54),
        Drink(id: "catalog_kombucha", name: "Kombucha", liquidType: .other,
              volumeMilliliters: 240, caloriesKcal: 30, sodiumMilligrams: 15, sugarGrams: 4),
    ]

    /// Search catalog by name (case-insensitive).
    public static func search(query: String) -> [Drink] {
        let lowercaseQuery = query.lowercased()
        return all.filter { $0.name.lowercased().contains(lowercaseQuery) }
    }

    public static func byID(_ id: String) -> Drink? {
        all.first { $0.id == id }
    }
}
