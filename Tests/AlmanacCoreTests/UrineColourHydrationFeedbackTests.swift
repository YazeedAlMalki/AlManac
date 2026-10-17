import Testing
import Foundation
@testable import AlmanacCore

/// BRD §6.3: "Color is outcome of hydration; intake is input. Dark color despite
/// target → raise target (suspended during religious dry fasts)."
///
/// Tested at the reader (`UrineColourHydrationFeedbackReader.feedback`), which
/// is what the hydration screen calls, and at the pure rule for the cases that
/// need no database.
@Suite("Urine colour hydration feedback")
struct UrineColourHydrationFeedbackTests {
    let db = try! TestDatabase()
    var urination: UrinationStore { UrinationStore(db: db) }
    var reader: UrineColourHydrationFeedbackReader { UrineColourHydrationFeedbackReader(db: db) }

    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func log(_ grade: UrinationColorGrade, _ time: String, day: String = "2026-10-14") throws {
        try urination.log(UrinationDraft(timestamp: at(time), colorGrade: grade), logicalDay: day)
    }

    @Test("A dark latest reading after the target was reached offers a raise of one step")
    func darkDespiteTargetRaises() throws {
        try log(.grade7, "2026-10-14T15:00:00Z")
        let verdict = try reader.feedback(on: "2026-10-14", intakeMilliliters: 2_600, targetMilliliters: 2_500)
        #expect(verdict == .raise(from: 2_500, to: 2_750, grade: .grade7))
    }

    @Test("A dark reading before the target is reached is not 'despite the target'")
    func targetNotReached() throws {
        try log(.grade8, "2026-10-14T15:00:00Z")
        let verdict = try reader.feedback(on: "2026-10-14", intakeMilliliters: 1_200, targetMilliliters: 2_500)
        #expect(verdict == .targetNotReached)
    }

    @Test("Only the latest reading of the day counts: a dark morning followed by a pale afternoon raises nothing")
    func latestReadingWins() throws {
        try log(.grade8, "2026-10-14T06:00:00Z")
        try log(.grade2, "2026-10-14T16:00:00Z")
        let verdict = try reader.feedback(on: "2026-10-14", intakeMilliliters: 3_000, targetMilliliters: 2_500)
        #expect(verdict == .noDarkReading)
    }

    @Test("Grade 5 is not dark under this rule, grade 6 is")
    func darkThreshold() {
        #expect(!UrineColourHydrationFeedback.isDark(.grade5))
        #expect(UrineColourHydrationFeedback.isDark(.grade6))
        #expect(UrineColourHydrationFeedback.isDark(.grade8))
    }

    @Test("No reading at all says so, rather than claiming the colour was fine")
    func noReadings() throws {
        let verdict = try reader.feedback(on: "2026-10-14", intakeMilliliters: 3_000, targetMilliliters: 2_500)
        #expect(verdict == .noReading)
    }

    @Test("On a religious fast day the rule is suspended, however dark the reading")
    func suspendedOnAFastDay() throws {
        let schedules = ReligiousFastScheduleStore(db: db)
        let id = try schedules.createSchedule(scheduleType: "mon_thu")
        try schedules.addManualCorrection(id: id, date: "2026-10-14", action: ManualCorrection.addFast)
        #expect(try schedules.isFastDay("2026-10-14"))

        try log(.grade8, "2026-10-14T15:00:00Z")
        let verdict = try reader.feedback(on: "2026-10-14", intakeMilliliters: 3_000, targetMilliliters: 2_500)
        #expect(verdict == .suspendedDuringDryFast)
    }

    @Test("A reading on another day does not count toward this one")
    func otherDaysIgnored() throws {
        try log(.grade8, "2026-10-13T15:00:00Z", day: "2026-10-13")
        let verdict = try reader.feedback(on: "2026-10-14", intakeMilliliters: 3_000, targetMilliliters: 2_500)
        #expect(verdict == .noReading)
    }

    @Test("A target of zero or less is not a target; nothing is offered")
    func noTarget() {
        let verdict = UrineColourHydrationFeedback.evaluate(
            latest: .grade8, intakeMilliliters: 3_000, targetMilliliters: 0, isReligiousFastDay: false)
        #expect(verdict == .targetNotReached)
    }

    @Test("The offered sentence names the grade in words and is labelled as not clinician-reviewed")
    func wordingIsLabelledDraft() {
        let text = UrineColourHydrationFeedback.Verdict
            .raise(from: 2_500, to: 2_750, grade: .grade7).message
        #expect(text?.contains("Colour grade 7 of 8") == true)
        #expect(text?.contains("not clinician-reviewed") == true)
        #expect(UrineColourHydrationFeedback.Verdict.suspendedDuringDryFast.message?
            .contains("fast") == true)
        #expect(UrineColourHydrationFeedback.Verdict.noDarkReading.message == nil)
    }
}
