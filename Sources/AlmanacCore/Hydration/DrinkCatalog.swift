import Foundation

/// Represents a beverage with nutritional information
public struct Drink: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let liquidType: LiquidType
    public let volumeMilliliters: Double
    public let caloriesKcal: Double
    public let sodiumMilligrams: Double
    public let sugarGrams: Double?
    public let isCustom: Bool
    public let userId: String?  // nil for catalog drinks, set for custom
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
        userId: String? = nil,
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
        self.userId = userId
        self.createdAt = createdAt
    }
}

/// Standard catalog of common beverages
public enum CatalogDrinks {
    /// Get all predefined drinks in the catalog
    public static let all: [Drink] = [
        // Water
        Drink(
            id: "catalog_water",
            name: "Water",
            liquidType: .water,
            volumeMilliliters: 250,
            caloriesKcal: 0,
            sodiumMilligrams: 0
        ),

        // Sodas - Regular
        Drink(
            id: "catalog_pepsi",
            name: "Pepsi",
            liquidType: .other,
            volumeMilliliters: 355,  // 12 oz
            caloriesKcal: 150,
            sodiumMilligrams: 30,
            sugarGrams: 41
        ),
        Drink(
            id: "catalog_coke",
            name: "Coca-Cola",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 140,
            sodiumMilligrams: 34,
            sugarGrams: 39
        ),
        Drink(
            id: "catalog_sprite",
            name: "Sprite",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 140,
            sodiumMilligrams: 65,
            sugarGrams: 38
        ),
        Drink(
            id: "catalog_fanta",
            name: "Fanta",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 160,
            sodiumMilligrams: 45,
            sugarGrams: 42
        ),

        // Sodas - Diet/Zero Sugar
        Drink(
            id: "catalog_pepsi_diet",
            name: "Diet Pepsi",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 0,
            sodiumMilligrams: 35,
            sugarGrams: 0
        ),
        Drink(
            id: "catalog_coke_diet",
            name: "Diet Coke",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 0,
            sodiumMilligrams: 46,
            sugarGrams: 0
        ),
        Drink(
            id: "catalog_coke_zero",
            name: "Coke Zero",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 0,
            sodiumMilligrams: 50,
            sugarGrams: 0
        ),

        // Sports Drinks
        Drink(
            id: "catalog_gatorade",
            name: "Gatorade (Orange)",
            liquidType: .sportsDrink,
            volumeMilliliters: 591,  // 20 oz
            caloriesKcal: 140,
            sodiumMilligrams: 290,
            sugarGrams: 37
        ),
        Drink(
            id: "catalog_powerade",
            name: "Powerade (Fruit Punch)",
            liquidType: .sportsDrink,
            volumeMilliliters: 591,
            caloriesKcal: 150,
            sodiumMilligrams: 200,
            sugarGrams: 39
        ),
        Drink(
            id: "catalog_gatorade_zero",
            name: "Gatorade Zero",
            liquidType: .sportsDrink,
            volumeMilliliters: 591,
            caloriesKcal: 0,
            sodiumMilligrams: 310,
            sugarGrams: 0
        ),

        // Electrolyte Solutions
        Drink(
            id: "catalog_pedialyte",
            name: "Pedialyte",
            liquidType: .electrolyteSolution,
            volumeMilliliters: 1000,
            caloriesKcal: 0,
            sodiumMilligrams: 750,
            sugarGrams: 25
        ),
        Drink(
            id: "catalog_coconut_water",
            name: "Coconut Water",
            liquidType: .coconutWater,
            volumeMilliliters: 240,
            caloriesKcal: 45,
            sodiumMilligrams: 250,
            sugarGrams: 9
        ),

        // Coffee
        Drink(
            id: "catalog_coffee_black",
            name: "Black Coffee",
            liquidType: .coffee,
            volumeMilliliters: 240,
            caloriesKcal: 2,
            sodiumMilligrams: 5,
            sugarGrams: 0
        ),
        Drink(
            id: "catalog_coffee_latte",
            name: "Latte (2% Milk)",
            liquidType: .coffee,
            volumeMilliliters: 240,
            caloriesKcal: 150,
            sodiumMilligrams: 150,
            sugarGrams: 12
        ),
        Drink(
            id: "catalog_coffee_cappuccino",
            name: "Cappuccino",
            liquidType: .coffee,
            volumeMilliliters: 240,
            caloriesKcal: 120,
            sodiumMilligrams: 120,
            sugarGrams: 8
        ),

        // Tea
        Drink(
            id: "catalog_tea_black",
            name: "Black Tea",
            liquidType: .tea,
            volumeMilliliters: 240,
            caloriesKcal: 2,
            sodiumMilligrams: 0,
            sugarGrams: 0
        ),
        Drink(
            id: "catalog_tea_green",
            name: "Green Tea",
            liquidType: .tea,
            volumeMilliliters: 240,
            caloriesKcal: 2,
            sodiumMilligrams: 0,
            sugarGrams: 0
        ),
        Drink(
            id: "catalog_iced_tea",
            name: "Iced Tea (Sweetened)",
            liquidType: .tea,
            volumeMilliliters: 240,
            caloriesKcal: 90,
            sodiumMilligrams: 10,
            sugarGrams: 22
        ),

        // Milk & Dairy
        Drink(
            id: "catalog_milk_whole",
            name: "Whole Milk",
            liquidType: .milk,
            volumeMilliliters: 240,
            caloriesKcal: 150,
            sodiumMilligrams: 120,
            sugarGrams: 12
        ),
        Drink(
            id: "catalog_milk_skim",
            name: "Skim Milk",
            liquidType: .milk,
            volumeMilliliters: 240,
            caloriesKcal: 80,
            sodiumMilligrams: 125,
            sugarGrams: 12
        ),
        Drink(
            id: "catalog_chocolate_milk",
            name: "Chocolate Milk",
            liquidType: .milk,
            volumeMilliliters: 240,
            caloriesKcal: 190,
            sodiumMilligrams: 150,
            sugarGrams: 24
        ),

        // Juice
        Drink(
            id: "catalog_orange_juice",
            name: "Orange Juice",
            liquidType: .juice,
            volumeMilliliters: 240,
            caloriesKcal: 110,
            sodiumMilligrams: 0,
            sugarGrams: 26
        ),
        Drink(
            id: "catalog_apple_juice",
            name: "Apple Juice",
            liquidType: .juice,
            volumeMilliliters: 240,
            caloriesKcal: 114,
            sodiumMilligrams: 10,
            sugarGrams: 29
        ),
        Drink(
            id: "catalog_cranberry_juice",
            name: "Cranberry Juice",
            liquidType: .juice,
            volumeMilliliters: 240,
            caloriesKcal: 137,
            sodiumMilligrams: 60,
            sugarGrams: 33
        ),

        // Energy & Other
        Drink(
            id: "catalog_redbull",
            name: "Red Bull",
            liquidType: .other,
            volumeMilliliters: 250,
            caloriesKcal: 110,
            sodiumMilligrams: 200,
            sugarGrams: 27
        ),
        Drink(
            id: "catalog_monster",
            name: "Monster Energy",
            liquidType: .other,
            volumeMilliliters: 355,
            caloriesKcal: 160,
            sodiumMilligrams: 370,
            sugarGrams: 54
        ),
        Drink(
            id: "catalog_kombucha",
            name: "Kombucha",
            liquidType: .other,
            volumeMilliliters: 240,
            caloriesKcal: 30,
            sodiumMilligrams: 15,
            sugarGrams: 4
        ),
    ]

    /// Search catalog by name (case-insensitive)
    public static func search(query: String) -> [Drink] {
        let lowercaseQuery = query.lowercased()
        return all.filter { drink in
            drink.name.lowercased().contains(lowercaseQuery)
        }
    }

    /// Get drink by ID
    public static func byId(_ id: String) -> Drink? {
        all.first { $0.id == id }
    }
}
