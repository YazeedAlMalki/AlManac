import Testing
import Foundation
@testable import AlmanacCore

@Suite("PrayerSettingsStore Tests")
struct PrayerSettingsStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    @Test("Reading settings before any write returns the schema's own defaults")
    func defaultsBeforeAnyWrite() throws {
        let store = PrayerSettingsStore(db: db)
        let settings = try store.settings()

        #expect(settings.calculationMethod == "umm_al_qura")
        #expect(settings.timezone == "Asia/Riyadh")
        #expect(settings.manualCityOverride == false)
        #expect(settings.latitude == nil)
        #expect(settings.longitude == nil)
    }

    @Test("Updating location on a fresh database self-heals the singleton row")
    func updateLocationSelfHeals() throws {
        let store = PrayerSettingsStore(db: db)
        try store.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh", country: "Saudi Arabia", manualCityOverride: true)

        let settings = try store.settings()
        #expect(settings.latitude == 24.7136)
        #expect(settings.longitude == 46.6753)
        #expect(settings.city == "Riyadh")
        #expect(settings.manualCityOverride == true)
    }

    @Test("Updating the calculation method to custom stores its own angles")
    func customMethodStoresAngles() throws {
        let store = PrayerSettingsStore(db: db)
        try store.updateCalculationMethod("custom", customFajrAngleDeg: 16, customIshaAngleDeg: 16)

        let settings = try store.settings()
        #expect(settings.calculationMethod == "custom")
        #expect(settings.customFajrAngleDeg == 16)
        #expect(settings.customIshaAngleDeg == 16)
    }

    @Test("Updating one offset leaves the others at their defaults")
    func partialOffsetUpdate() throws {
        let store = PrayerSettingsStore(db: db)
        try store.updateOffsets(fajr: 5)

        let settings = try store.settings()
        #expect(settings.fajrOffsetMin == 5)
        #expect(settings.dhuhrOffsetMin == 0)
        #expect(settings.ishaOffsetMin == 0)
    }

    @Test("A second location update overwrites the first rather than duplicating rows")
    func secondUpdateOverwrites() throws {
        let store = PrayerSettingsStore(db: db)
        try store.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh", country: "Saudi Arabia", manualCityOverride: true)
        try store.updateLocation(latitude: 21.4225, longitude: 39.8262, city: "Makkah", country: "Saudi Arabia", manualCityOverride: true)

        let settings = try store.settings()
        #expect(settings.city == "Makkah")
        let count = try db.query("SELECT COUNT(*) as n FROM prayer_settings;").first?.int("n")
        #expect(count == 1)
    }
}
