import Testing
import Foundation
@testable import AlmanacCore

@Suite("SleepTrackingSettingsStore Tests")
struct SleepTrackingSettingsStoreTests {
    let db = try! TestDatabase()
    var store: SleepTrackingSettingsStore { SleepTrackingSettingsStore(db: db) }

    @Test("With no row yet, tracking defaults to on")
    func defaultsToEnabled() throws {
        #expect(try store.isEnabled() == true)
    }

    @Test("Setting tracking off persists and reads back")
    func setEnabledPersists() throws {
        try store.setEnabled(false)
        #expect(try store.isEnabled() == false)
    }

    @Test("Toggling back on persists too")
    func setEnabledRoundTrips() throws {
        try store.setEnabled(false)
        try store.setEnabled(true)
        #expect(try store.isEnabled() == true)
    }
}
