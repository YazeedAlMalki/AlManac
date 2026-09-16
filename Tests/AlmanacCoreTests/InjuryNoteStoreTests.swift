import Testing
import Foundation
@testable import AlmanacCore

@Suite("InjuryNoteStore Tests")
struct InjuryNoteStoreTests {
    let db = try! TestDatabase()
    var store: InjuryNoteStore { InjuryNoteStore(db: db) }
    
    @Test("Log injury note")
    func logInjury() throws {
        let draft = InjuryNoteDraft(startDate: "2026-09-10", bodyArea: "left knee",
                                     description: "Slight meniscus strain")
        let id = try store.log(draft)
        
        let note = try store.note(id: id)
        #expect(note?.bodyArea == "left knee")
        #expect(note?.startDate == "2026-09-10")
        #expect(note?.isActive == true)
        #expect(note?.affectsTraining == true)
    }
    
    @Test("Mark injury resolved")
    func markResolved() throws {
        let draft = InjuryNoteDraft(startDate: "2026-09-10", bodyArea: "ankle",
                                     description: "Mild sprain")
        let id = try store.log(draft)
        
        try store.markResolved(id: id, endDate: "2026-09-15")
        
        let note = try store.note(id: id)
        #expect(note?.endDate == "2026-09-15")
        #expect(note?.isActive == false)
    }
    
    @Test("Fetch active injuries")
    func activeInjuries() throws {
        try store.log(InjuryNoteDraft(startDate: "2026-09-10", bodyArea: "knee", description: "Strain"))
        let id2 = try store.log(InjuryNoteDraft(startDate: "2026-09-05", bodyArea: "shoulder", description: "Sore"))
        
        try store.markResolved(id: id2, endDate: "2026-09-12")
        
        let active = try store.activeInjuries()
        #expect(active.count == 1)
        #expect(active[0].bodyArea == "knee")
    }
    
    @Test("Fetch injuries by body area")
    func injuriesByBodyArea() throws {
        try store.log(InjuryNoteDraft(startDate: "2026-09-10", bodyArea: "knee", description: "Strain"))
        try store.log(InjuryNoteDraft(startDate: "2026-09-05", bodyArea: "knee", description: "Old injury"))
        try store.log(InjuryNoteDraft(startDate: "2026-09-08", bodyArea: "shoulder", description: "Sore"))
        
        let kneeInjuries = try store.injuries(for: "knee")
        let shoulderInjuries = try store.injuries(for: "shoulder")
        
        #expect(kneeInjuries.count == 2)
        #expect(shoulderInjuries.count == 1)
    }
}
