import Foundation

/// BRD §6.3: "Color is outcome of hydration; intake is input. Dark color despite
/// target → raise target (suspended during religious dry fasts)."
///
/// **Every number here is an unconfirmed build decision**, recorded in
/// `CONTEXT.md` ("Digestion and urination (2026-10-15)") with how to overrule
/// it. The BRD gives the rule's shape and no thresholds:
///
/// - **"Dark" is grade 6, 7 or 8** — the top three of the eight-level chart.
///   The chart names only its two ends, and this codebase does not name the
///   middle (`UrinationColorGrade.displayName`); the threshold is a position on
///   the scale, not a colour description.
/// - **"Despite the target" means the day's intake has reached the day's
///   target**, and the reading judged is the **latest** of the day — a dark
///   first-morning reading followed by a pale afternoon is not a dark day.
/// - **The raise is one step of 250 mL**, offered to the person, never applied
///   silently: the target is theirs.
/// - **Suspended for the whole of a religious fast day.** A religious fast is a
///   dry fast; dark urine during it is the fast, not a target that is too low.
///
/// The wording it offers is a draft and says so: it is "not clinician-reviewed",
/// the same status BRD §8 gives every advisory before release.
public enum UrineColourHydrationFeedback {
    /// The grades counted as dark. Unconfirmed — see the type's doc comment.
    public static let darkGrades: ClosedRange<Int> = 6...8
    /// The step a raise offers, in millilitres. Unconfirmed.
    public static let raiseStepMilliliters: Double = 250

    public enum Verdict: Sendable, Hashable {
        /// No urination recorded on the day.
        case noReading
        /// The latest reading is not dark.
        case noDarkReading
        /// The latest reading is dark, but the target has not been reached, so
        /// this is not "despite the target".
        case targetNotReached
        /// A religious (dry) fast day: the rule does not apply.
        case suspendedDuringDryFast
        /// Dark despite the target: offer to raise it.
        case raise(from: Double, to: Double, grade: UrinationColorGrade)

        /// What the hydration screen says, or nil when it says nothing.
        /// Draft wording, labelled as such.
        public var message: String? {
            switch self {
            case .noReading, .noDarkReading, .targetNotReached:
                return nil
            case .suspendedDuringDryFast:
                return localized("Urine colour does not change your water target on a fast day.")
            case let .raise(from, to, grade):
                return localized("Your latest urine was %@ after you reached your %@ mL target. Raise it to %@ mL? Draft wording, not clinician-reviewed.",
                                 grade.accessibilityLabel,
                                 NumberDisplay.localized(String(Int(from.rounded()))),
                                 NumberDisplay.localized(String(Int(to.rounded()))))
            }
        }
    }

    public static func isDark(_ grade: UrinationColorGrade) -> Bool {
        darkGrades.contains(grade.rawValue)
    }

    /// The rule, with nothing read from storage.
    public static func evaluate(latest: UrinationColorGrade?,
                                intakeMilliliters: Double,
                                targetMilliliters: Double,
                                isReligiousFastDay: Bool) -> Verdict {
        if isReligiousFastDay { return .suspendedDuringDryFast }
        guard let latest else { return .noReading }
        guard isDark(latest) else { return .noDarkReading }
        guard targetMilliliters > 0, intakeMilliliters >= targetMilliliters else { return .targetNotReached }
        return .raise(from: targetMilliliters, to: targetMilliliters + raiseStepMilliliters, grade: latest)
    }
}

/// Reads the day's urination and fast-day status and applies the rule. The
/// intake and target come from the caller, which already holds both: the
/// hydration screen shows them.
public struct UrineColourHydrationFeedbackReader: @unchecked Sendable {
    let db: Database

    public init(db: Database) { self.db = db }

    public func feedback(on logicalDay: String,
                         intakeMilliliters: Double,
                         targetMilliliters: Double) throws -> UrineColourHydrationFeedback.Verdict {
        let isFastDay = try ReligiousFastScheduleStore(db: db).isFastDay(logicalDay)
        let latest = try UrinationStore(db: db).logs(for: logicalDay)
            .max { $0.timestamp < $1.timestamp }?.colorGrade
        return UrineColourHydrationFeedback.evaluate(latest: latest,
                                                    intakeMilliliters: intakeMilliliters,
                                                    targetMilliliters: targetMilliliters,
                                                    isReligiousFastDay: isFastDay)
    }
}
