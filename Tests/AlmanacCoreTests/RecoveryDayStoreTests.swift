import Testing
import Foundation
@testable import AlmanacCore

/// §9.6's "manually selected recovery day", from the row the person's switch
/// writes to the recommendation it changes. The precedence itself is pinned in
/// `ReadinessEngineTests`; this suite pins that a declaration belongs to exactly
/// the day it names.
@Suite("Recovery day declarations")
struct RecoveryDayStoreTests {
    let db = try! TestDatabase()
    var store: RecoveryDayStore { RecoveryDayStore(db: db) }
    let time = TimeModel.riyadh()
    let iso = ISO8601DateFormatter()

    @Test("Declaring and clearing a day")
    func declareAndClear() throws {
        let now = iso.date(from: "2026-10-16T05:00:00Z")!
        #expect(try store.isRecoveryDay("2026-10-16") == false)

        try store.declare(logicalDay: "2026-10-16", at: now)
        #expect(try store.isRecoveryDay("2026-10-16"))

        try store.clear(logicalDay: "2026-10-16")
        #expect(try store.isRecoveryDay("2026-10-16") == false)
    }

    @Test("A declaration is one day's and does not reach the next or the one before")
    func scopedToOneDay() throws {
        try store.declare(logicalDay: "2026-10-15", at: iso.date(from: "2026-10-15T05:00:00Z")!)
        #expect(try store.isRecoveryDay("2026-10-15"))
        #expect(try store.isRecoveryDay("2026-10-16") == false)
        #expect(try store.isRecoveryDay("2026-10-14") == false)
    }

    /// Made on the morning of the 16th, about the 15th. The store never works a
    /// day out from the time, so the declaration is the 15th's and the 16th —
    /// the day it was actually made on — is untouched.
    @Test("A back-dated declaration is attributed to the day it names")
    func backDated() throws {
        let madeAt = iso.date(from: "2026-10-16T07:00:00Z")!  // 10:00 Riyadh
        #expect(time.logicalDay(madeAt).value == "2026-10-16")

        try store.declare(logicalDay: "2026-10-15", at: madeAt)

        let declaration = try #require(try store.declaration(for: "2026-10-15"))
        #expect(declaration.logicalDay == "2026-10-15")
        #expect(declaration.declaredAt == madeAt)
        #expect(try store.isRecoveryDay(time.logicalDay(madeAt).value) == false)
    }

    @Test("Declaring a declared day again keeps the first time")
    func redeclareKeepsFirstTime() throws {
        let first = iso.date(from: "2026-10-16T05:00:00Z")!
        try store.declare(logicalDay: "2026-10-16", at: first)
        try store.declare(logicalDay: "2026-10-16", at: iso.date(from: "2026-10-16T09:00:00Z")!)
        #expect(try store.declaration(for: "2026-10-16")?.declaredAt == first)
    }

    @Test("Clearing a day never declared is not an error")
    func clearUndeclared() throws {
        try store.clear(logicalDay: "2026-10-16")
        #expect(try store.isRecoveryDay("2026-10-16") == false)
    }

    /// The dashboard's switch: on, off and on again without leaving the screen.
    @Test("The switch can be moved back and forth")
    func switchBackAndForth() throws {
        let now = iso.date(from: "2026-10-16T05:00:00Z")!
        try store.set(true, logicalDay: "2026-10-16", at: now)
        #expect(try store.isRecoveryDay("2026-10-16"))
        try store.set(false, logicalDay: "2026-10-16", at: now)
        #expect(try store.isRecoveryDay("2026-10-16") == false)
        try store.set(true, logicalDay: "2026-10-16", at: now)
        #expect(try store.isRecoveryDay("2026-10-16"))
    }

    /// Store to recommendation, the way `ReadinessModel.refresh()` assembles it:
    /// the declared day reads as a recovery day, the next day reads its band.
    @Test("A declared day's recommendation, and the next day's")
    func reachesTheRecommendation() throws {
        try store.declare(logicalDay: "2026-10-15", at: iso.date(from: "2026-10-15T05:00:00Z")!)
        let inputs = ReadinessInputs(sleepDurationMinutes: 480,
                                     stages: SleepStageBreakdown(deep: 0.25, rem: 0.25, core: 0.50),
                                     restingHeartRate: 48, hrv: 70)
        let baseline = ReadinessBaseline(context: .general, restingHeartRate: 52, hrv: 60, validDayCount: 40)

        func outcome(_ day: String) throws -> ReadinessOutcome {
            ReadinessEngine.evaluate(state: .provisional, inputs: inputs, baseline: baseline,
                                     context: ReadinessContext(manualRecoveryDay: try store.isRecoveryDay(day)))
        }

        let declared = try outcome("2026-10-15")
        let next = try outcome("2026-10-16")
        #expect(declared.recommendation == "Recovery day: rest as planned.")
        #expect(declared.precedenceApplied == [.manualRecovery])
        #expect(next.recommendation == ReadinessFormula.bandText(for: next.score!))
        #expect(declared.score == next.score)
        #expect(declared.color == next.color)
        #expect(declared.confidence == next.confidence)
    }
}
