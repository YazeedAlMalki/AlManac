import Foundation
import Testing
@testable import AlmanacCore

/// The profile's email address and the backup it unlocks (owner, 2026-10-20:
/// backups are for a person "registered with a valid email").
@Suite("Profile email")
struct ProfileEmailTests {

    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    @Test("Well-formed addresses pass, trimmed")
    func wellFormed() {
        #expect(ProfileEmail.normalized("name@example.com") == "name@example.com")
        #expect(ProfileEmail.normalized("  first.last+tag@mail.example.co.uk \n")
                == "first.last+tag@mail.example.co.uk")
    }

    @Test("Anything else is refused")
    func malformed() {
        for input in ["", "   ", "name", "name@", "@example.com", "name@example", "name@example.",
                      "name@.com", "na me@example.com", "name@@example.com", "a@b@example.com"] {
            #expect(ProfileEmail.normalized(input) == nil, "\(input) was accepted")
        }
    }

    @Test("A new profile has no email, so it cannot create a backup")
    func freshProfileCannotBackUp() throws {
        let profile = try ProfileStore(db: try migrated()).profile()
        #expect(profile.email == nil)
        #expect(profile.mayCreateBackup == false)
    }

    @Test("A saved email round-trips and unlocks backups; clearing it locks them again")
    func emailRoundTrips() throws {
        let store = ProfileStore(db: try migrated())
        try store.updateEmail("  name@example.com ")
        #expect(try store.profile().email == "name@example.com")
        #expect(try store.profile().mayCreateBackup)
        try store.updateEmail("")
        #expect(try store.profile().email == nil)
        #expect(try store.profile().mayCreateBackup == false)
    }

    @Test("A malformed email is refused and the saved one is kept")
    func malformedIsNotSaved() throws {
        let store = ProfileStore(db: try migrated())
        try store.updateEmail("name@example.com")
        #expect(throws: ProfileEmailError.invalid) { try store.updateEmail("not-an-email") }
        #expect(try store.profile().email == "name@example.com")
    }
}
