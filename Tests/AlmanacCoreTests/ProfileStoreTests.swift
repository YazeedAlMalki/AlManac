import Testing
import Foundation
@testable import AlmanacCore

@Suite("ProfileStore Tests")
struct ProfileStoreTests {
    let db = try! TestDatabase()
    
    @Test("Read and write profile")
    func readWriteProfile() throws {
        let store = ProfileStore(db: db)
        
        // Initially should return default profile
        var profile = try store.profile()
        #expect(profile.displayName == "User")
        
        // Update display name
        try store.updateDisplayName("Yazeed")
        profile = try store.profile()
        #expect(profile.displayName == "Yazeed")
        
        // Update date of birth
        try store.updateDateOfBirth("1990-05-15")
        profile = try store.profile()
        #expect(profile.dateOfBirth == "1990-05-15")
        
        // Update sex
        try store.updateBiologicalSex("male")
        profile = try store.profile()
        #expect(profile.biologicalSex == "male")
        
        // Update height
        try store.updateHeight(180.5)
        profile = try store.profile()
        #expect(profile.heightCm == 180.5)
    }
    
    @Test("Update sports list")
    func updateSports() throws {
        let store = ProfileStore(db: db)
        
        let sports = ["sabre", "running", "swimming"]
        try store.updateSports(sports)
        
        let profile = try store.profile()
        #expect(profile.sports == sports)
    }
}
