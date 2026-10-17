import Testing
import Foundation
@testable import AlmanacCore

/// BRD §6.3's draft advisory (owner, G1, 2026-10-16). Each test is one trigger
/// the BRD names, at the level this build gives it, plus the two properties the
/// BRD insists on: nothing is said about an ordinary entry, and nothing is
/// stored.
@Suite("Digestion advisory (draft)")
struct DigestionAdvisoryTests {
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    var nextID: Int64 = 1

    func entry(_ day: String = "2026-10-16", bristol: BristolType = .type4, color: StoolColor? = .brown,
               blood: String? = nil, pain: Bool? = nil, dizzy: Bool? = nil, id: Int64 = 1) -> BowelMovementEntry {
        BowelMovementEntry(id: id, logicalDay: day, timestamp: Date(), bristolType: bristol,
                           color: color?.rawValue, bloodPresent: blood != nil, bloodAmount: blood, gas: nil,
                           urgency: nil, notes: nil, clinicianEscalationLevel: nil, createdAt: Date(),
                           severePain: pain, dizzinessOrWeakness: dizzy)
    }

    func level(_ e: BowelMovementEntry, recent: [BowelMovementEntry] = []) -> DigestionAdvisoryLevel? {
        DigestionAdvisory.assess(e, recent: recent, timeModel: timeModel)?.level
    }

    @Test("An ordinary entry gets no advisory at all")
    func ordinaryEntry() {
        #expect(level(entry()) == nil)
        #expect(level(entry(bristol: .type3, color: .yellow)) == nil)
        #expect(level(entry(bristol: .type6)) == nil, "one loose stool is not persistent")
        #expect(level(entry(color: .green)) == nil)
        #expect(level(entry(blood: "none")) == nil, "\"none seen\" is not blood")
    }

    @Test("Urgent: a large amount of blood, bloody diarrhoea, bleeding with dizziness or severe pain")
    func urgent() {
        #expect(level(entry(blood: "large")) == .seekUrgentCare)
        #expect(level(entry(bristol: .type7, blood: "streak")) == .seekUrgentCare)
        #expect(level(entry(blood: "small", dizzy: true)) == .seekUrgentCare)
        #expect(level(entry(color: .black, dizzy: true)) == .seekUrgentCare)
        #expect(level(entry(color: .black, pain: true)) == .seekUrgentCare)
    }

    @Test("Contact a professional: black, red without blood, a small amount, pain or dizziness alone")
    func contact() {
        #expect(level(entry(color: .black)) == .contactProfessional)
        #expect(level(entry(color: .red)) == .contactProfessional)
        #expect(level(entry(blood: "small")) == .contactProfessional)
        #expect(level(entry(pain: true)) == .contactProfessional)
        #expect(level(entry(dizzy: true)) == .contactProfessional)
    }

    @Test("Informational: one streak of blood, one pale stool")
    func informational() {
        #expect(level(entry(blood: "streak")) == .informational)
        #expect(level(entry(color: .pale)) == .informational)
    }

    @Test("Persistent: what is informational once is more when it repeats within 7 days")
    func persistence() {
        let streak = entry("2026-10-16", blood: "streak", id: 9)
        let earlier = entry("2026-10-12", blood: "streak", id: 2)
        let tooEarly = entry("2026-10-01", blood: "streak", id: 3)
        #expect(level(streak, recent: [earlier]) == .contactProfessional)
        #expect(level(streak, recent: [tooEarly]) == .informational, "outside the 7 days it does not count")

        let loose = [entry("2026-10-14", bristol: .type6, id: 4), entry("2026-10-15", bristol: .type7, id: 5)]
        #expect(level(entry(bristol: .type6, id: 6), recent: loose) == .contactProfessional)

        let pale = entry(color: .pale, id: 7)
        #expect(level(pale, recent: [entry("2026-10-13", color: .pale, id: 8)]) == .contactProfessional)

        let hard = [entry("2026-10-14", bristol: .type1, id: 10), entry("2026-10-15", bristol: .type2, id: 11)]
        let advisory = DigestionAdvisory.assess(entry(bristol: .type1, id: 12), recent: hard, timeModel: timeModel)
        #expect(advisory?.level == .informational)
        #expect(advisory?.reasons == [.persistentHard])
    }

    @Test("The reasons are listed highest level first, and the advisory takes the highest")
    func ordering() {
        let advisory = DigestionAdvisory.assess(entry(color: .black, blood: "large", pain: true), recent: [],
                                                timeModel: timeModel)
        #expect(advisory?.level == .seekUrgentCare)
        #expect(advisory?.reasons.first?.level == .seekUrgentCare)
        #expect(advisory?.reasons.contains(.black) == true)
        #expect(advisory?.reasons.map(\.level) == advisory?.reasons.map(\.level).sorted(by: >))
    }

    @Test("The two new questions are stored as yes, no or not stated, and no level is ever stored")
    func storage() throws {
        let db = try TestDatabase()
        let store = DigestionStore(db: db)
        let yes = try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type4, color: "black",
                                                   severePain: true, dizzinessOrWeakness: false),
                                logicalDay: "2026-10-16")
        let unstated = try store.log(BowelMovementDraft(timestamp: Date(), bristolType: .type4),
                                     logicalDay: "2026-10-16")
        let first = try #require(try store.entry(id: yes))
        #expect(first.severePain == true)
        #expect(first.dizzinessOrWeakness == false)
        #expect(first.clinicianEscalationLevel == nil, "a draft rule's level is never written")
        let second = try #require(try store.entry(id: unstated))
        #expect(second.severePain == nil)
        #expect(second.dizzinessOrWeakness == nil)
        #expect(DigestionAdvisory.assess(first, recent: [], timeModel: timeModel)?.level == .seekUrgentCare)
    }
}
