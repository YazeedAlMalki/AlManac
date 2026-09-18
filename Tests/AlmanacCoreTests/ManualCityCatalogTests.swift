import Testing
import Foundation
@testable import AlmanacCore

@Suite("ManualCityCatalog Tests")
struct ManualCityCatalogTests {
    @Test("Bundles at least 200 cities, per §12.2's manual-fallback requirement")
    func atLeast200Cities() {
        #expect(ManualCityCatalog.allCities.count >= 200)
    }

    @Test("No duplicate name+country pairs")
    func noDuplicates() {
        let keys = ManualCityCatalog.allCities.map { "\($0.name.lowercased())|\($0.country.lowercased())" }
        #expect(Set(keys).count == keys.count)
    }

    @Test("Every coordinate is within valid latitude/longitude ranges")
    func validCoordinates() {
        for city in ManualCityCatalog.allCities {
            #expect((-90...90).contains(city.lat), "\(city.name): lat \(city.lat) out of range")
            #expect((-180...180).contains(city.lon), "\(city.name): lon \(city.lon) out of range")
        }
    }

    @Test("Every timezone identifier is one Foundation actually recognizes")
    func validTimezones() {
        for city in ManualCityCatalog.allCities {
            #expect(TimeZone(identifier: city.timezone) != nil,
                    "\(city.name), \(city.country): unrecognized timezone identifier \(city.timezone)")
        }
    }

    @Test("No blank name or country fields")
    func noBlankFields() {
        for city in ManualCityCatalog.allCities {
            #expect(!city.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!city.country.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("Riyadh's bundled coordinates match the ones AdhanCalculatorTests verifies against")
    func riyadhMatchesVerifiedCoordinates() throws {
        let riyadh = try #require(ManualCityCatalog.city(named: "Riyadh"))
        #expect(riyadh.lat == 24.7136)
        #expect(riyadh.lon == 46.6753)
        #expect(riyadh.timezone == "Asia/Riyadh")
    }

    @Test("Lookup by name is case-insensitive")
    func caseInsensitiveLookup() {
        #expect(ManualCityCatalog.city(named: "riyadh") != nil)
        #expect(ManualCityCatalog.city(named: "RIYADH") != nil)
    }

    @Test("Lookup disambiguates same-named cities by country")
    func disambiguatesByCountry() throws {
        // Riyadh has one entry; exercise the disambiguation path with a
        // country that doesn't match — should return nil, not the wrong city.
        #expect(ManualCityCatalog.city(named: "Riyadh", country: "Egypt") == nil)
        let riyadh = try #require(ManualCityCatalog.city(named: "Riyadh", country: "Saudi Arabia"))
        #expect(riyadh.country == "Saudi Arabia")
    }

    @Test("Search matches on country as well as city name")
    func searchMatchesCountry() {
        let results = ManualCityCatalog.search("Saudi Arabia")
        #expect(results.count == 5) // Riyadh, Jeddah, Mecca, Medina, Dammam
        #expect(results.allSatisfy { $0.country == "Saudi Arabia" })
    }

    @Test("Search is case-insensitive substring match, sorted by name")
    func searchCaseInsensitiveSorted() {
        let results = ManualCityCatalog.search("lon")
        #expect(results.contains { $0.name == "London" })
        #expect(results == results.sorted { $0.name < $1.name })
    }

    @Test("Empty search query returns every bundled city")
    func emptySearchReturnsAll() {
        #expect(ManualCityCatalog.search("").count == ManualCityCatalog.allCities.count)
    }

    @Test("A search with no matches returns an empty array, not nil-crashing behavior")
    func noMatchesReturnsEmpty() {
        #expect(ManualCityCatalog.search("Notacityanywhereonearthxyz").isEmpty)
    }
}
