import Foundation

/// One entry in the bundled manual-city fallback list (§12.2's third
/// coordinate-sourcing priority): `name`/`country`/`lat`/`lon`/`timezone`,
/// matching the spec's schema verbatim so `manual-cities.json` can be
/// re-derived from any standard city/timezone dataset without reshaping it.
public struct ManualCity: Sendable, Hashable, Codable {
    public let name: String
    public let country: String
    public let lat: Double
    public let lon: Double
    public let timezone: String
}

/// Loads and searches the bundled 200+-city manual fallback list (§12.2) —
/// what a user without a Core Location fix (denied, not yet granted, or
/// simply preferring a fixed location) picks from instead. A caller applies
/// a chosen city through the existing `PrayerSettingsStore.updateLocation`
/// (`manualCityOverride: true`), same as it would a detected GPS fix; this
/// type only resolves a name to coordinates; it does not touch settings
/// itself, matching the pattern of `AdhanCalculator` being a pure function
/// with no store dependency of its own.
public enum ManualCityCatalog {
    /// All bundled cities, loaded once and cached for the process lifetime —
    /// the file is static reference data, not something that changes at
    /// runtime.
    public static let allCities: [ManualCity] = loadCities()

    /// Case-insensitive substring match against `name` and `country`, sorted
    /// alphabetically by city name. An empty query returns every city.
    public static func search(_ query: String) -> [ManualCity] {
        guard !query.isEmpty else { return allCities }
        let lowered = query.lowercased()
        return allCities
            .filter { $0.name.lowercased().contains(lowered) || $0.country.lowercased().contains(lowered) }
            .sorted { $0.name < $1.name }
    }

    /// Exact case-insensitive match on `name`, disambiguated by `country`
    /// when given — for a caller that already has one specific city picked
    /// (e.g. from a search-result tap) and wants its coordinates. Returns
    /// the first match if more than one city shares a name and no country
    /// was given to disambiguate.
    public static func city(named name: String, country: String? = nil) -> ManualCity? {
        allCities.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                && (country == nil || $0.country.caseInsensitiveCompare(country!) == .orderedSame)
        }
    }

    private static func loadCities() -> [ManualCity] {
        guard let url = Bundle.module.url(forResource: "manual-cities", withExtension: "json") else {
            assertionFailure("manual-cities.json missing from AlmanacCore's resource bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ManualCity].self, from: data)
        } catch {
            assertionFailure("manual-cities.json failed to decode: \(error)")
            return []
        }
    }
}
