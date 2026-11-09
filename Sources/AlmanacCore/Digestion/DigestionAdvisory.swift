import Foundation

/// BRD §6.3's three-level, non-diagnostic advisory for a bowel movement.
///
/// **Draft, not clinician-reviewed.** Built on the owner's G1 answer
/// (2026-10-16): "build now, with draft wording". The BRD's own condition still
/// stands — "Requires clinician review before App Store release" — so every
/// screen that shows one also shows `reviewNote`. Public guidance informs the
/// wording and escalation, but does not validate this classifier. The source
/// mapping and unresolved clinical questions are in
/// `docs/features/digestion-advisory-review.md`.
///
/// Worked out from the entries each time it is read and never stored:
/// `clinicianEscalationLevel` stays empty for a classifier a clinician has
/// approved, and a draft rule written into it would read as one.
public enum DigestionAdvisoryLevel: Int, Sendable, Hashable, Comparable, CaseIterable {
    case informational = 1
    case contactProfessional = 2
    case seekUrgentCare = 3

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .informational: return localized("For your information")
        case .contactProfessional: return localized("Consider contacting a healthcare professional")
        case .seekUrgentCare: return localized("Seek urgent medical attention")
        }
    }

    /// An explicit next step, separate from the facts that raised the level.
    public var actionText: String {
        switch self {
        case .informational:
            return localized("If symptoms continue, change, or worry you, contact a healthcare professional. Do not wait for another Almanac entry to get help.")
        case .contactProfessional:
            return localized("Contact a healthcare professional for advice. Do not wait for more entries if symptoms continue or you feel unwell.")
        case .seekUrgentCare:
            return localized("Get urgent medical help now. If bleeding is heavy or does not stop, you feel faint, or you have severe pain with bleeding, go to an emergency department or call your local emergency number. Do not drive yourself if you feel faint or dizzy.")
        }
    }
}

/// What in the entries raised the advisory. Each carries its own level, and the
/// advisory takes the highest.
public enum DigestionAdvisoryReason: String, Sendable, Hashable, CaseIterable {
    case largeBlood, bloodWithLooseStool, bloodWithDizziness, blackWithDizziness, painWithBleeding
    case black, red, smallBlood, unspecifiedBlood, repeatedBlood, severePain, dizziness, persistentLoose, persistentPale
    case streakOfBlood, pale, persistentHard

    public var level: DigestionAdvisoryLevel {
        switch self {
        case .largeBlood, .bloodWithLooseStool, .bloodWithDizziness, .blackWithDizziness, .painWithBleeding,
             .black, .severePain:
            return .seekUrgentCare
        case .red, .smallBlood, .unspecifiedBlood, .streakOfBlood, .repeatedBlood, .dizziness, .persistentLoose, .persistentPale:
            return .contactProfessional
        case .pale, .persistentHard:
            return .informational
        }
    }

    /// Calm, non-diagnostic, and naming the harmless explanations where there
    /// are common ones, as §6.3 asks. Says what was recorded, not what it means.
    public var sentence: String {
        switch self {
        case .largeBlood: return localized("You recorded a large amount of blood.")
        case .bloodWithLooseStool: return localized("You recorded blood with very loose stool.")
        case .bloodWithDizziness: return localized("You recorded blood together with dizziness or weakness.")
        case .blackWithDizziness: return localized("You recorded black stool together with dizziness or weakness.")
        case .painWithBleeding: return localized("You recorded severe pain together with blood or black stool.")
        case .black: return localized("You recorded black stool. Foods, iron tablets and some medicines can darken stool, but bleeding can also cause it. Do not assume a food or medicine explains it; seek urgent medical advice.")
        case .red: return localized("You recorded red stool. Foods such as beetroot can change its colour, but Almanac cannot tell whether it is blood. Ask a healthcare professional if the cause is unclear, it happens again, or you feel unwell.")
        case .smallBlood: return localized("You recorded a small amount of blood.")
        case .unspecifiedBlood: return localized("You recorded blood without a recognised amount. Almanac cannot judge how much bleeding there is. If it is heavy or does not stop, get emergency help now.")
        case .repeatedBlood: return localized("You have recorded blood more than once in the last 7 days.")
        case .severePain: return localized("You recorded severe pain.")
        case .dizziness: return localized("You recorded dizziness or weakness.")
        case .persistentLoose: return localized("You have recorded very loose stool on 3 or more days in the last 7.")
        case .persistentPale: return localized("You have recorded pale stool on more than one day in the last 7.")
        case .streakOfBlood: return localized("You recorded a streak of blood. Straining or a small tear can cause this, but Almanac cannot confirm the cause. Contact a healthcare professional for advice.")
        case .pale: return localized("You recorded pale stool. If it happens again, it is worth mentioning to a professional.")
        case .persistentHard: return localized("You have recorded hard stools on 3 or more days in the last 7. Fluids, fibre and movement often help.")
        }
    }
}

public struct DigestionAdvisory: Sendable, Hashable {
    public let level: DigestionAdvisoryLevel
    /// Highest level first.
    public let reasons: [DigestionAdvisoryReason]

    /// Shown with every advisory, wherever it appears.
    public static var reviewNote: String {
        localized("Draft wording, not reviewed by a clinician. Almanac does not diagnose.")
    }

    /// The advisory for `entry`, or nil when nothing in it calls for one.
    ///
    /// `recent` is the person's other bowel-movement entries; only those in the
    /// seven logical days ending on the entry's own day count, and only for the
    /// "persistent" and "more than once" reasons. Passing the entry itself in
    /// `recent` is harmless.
    public static func assess(_ entry: BowelMovementEntry, recent: [BowelMovementEntry],
                              timeModel: TimeModel = TimeModel(timeZone: .current)) -> DigestionAdvisory? {
        var reasons: Set<DigestionAdvisoryReason> = []
        let color = entry.color.flatMap(StoolColor.init(rawValue:))
        let amount = entry.bloodAmount
        let blood = entry.bloodPresent && amount != "none"
        let loose = entry.bristolType.rawValue >= 6
        let dizzy = entry.dizzinessOrWeakness == true
        let pain = entry.severePain == true

        if blood && amount == "large" { reasons.insert(.largeBlood) }
        if blood && loose { reasons.insert(.bloodWithLooseStool) }
        if blood && dizzy { reasons.insert(.bloodWithDizziness) }
        if color == .black && dizzy { reasons.insert(.blackWithDizziness) }
        if pain && (blood || color == .black) { reasons.insert(.painWithBleeding) }

        if color == .black { reasons.insert(.black) }
        if color == .red && !blood { reasons.insert(.red) }
        if blood && amount == "small" { reasons.insert(.smallBlood) }
        if blood && amount == "streak" { reasons.insert(.streakOfBlood) }
        if blood && amount != "large" && amount != "small" && amount != "streak" {
            reasons.insert(.unspecifiedBlood)
        }
        if pain { reasons.insert(.severePain) }
        if dizzy { reasons.insert(.dizziness) }

        let window = Self.window(endingOn: entry.logicalDay, timeModel: timeModel)
        let others = recent.filter { $0.id != entry.id && window.contains($0.logicalDay) }
        let all = others + [entry]
        if blood && others.contains(where: { $0.bloodPresent && $0.bloodAmount != "none" }) {
            reasons.insert(.repeatedBlood)
        }
        func days(_ match: (BowelMovementEntry) -> Bool) -> Int { Set(all.filter(match).map(\.logicalDay)).count }
        if loose && days({ $0.bristolType.rawValue >= 6 }) >= 3 { reasons.insert(.persistentLoose) }
        if color == .pale && days({ $0.color == StoolColor.pale.rawValue }) >= 2 { reasons.insert(.persistentPale) }
        if entry.bristolType.rawValue <= 2 && days({ $0.bristolType.rawValue <= 2 }) >= 3 {
            reasons.insert(.persistentHard)
        }
        if color == .pale && !reasons.contains(.persistentPale) { reasons.insert(.pale) }

        guard let top = reasons.map(\.level).max() else { return nil }
        let ordered = DigestionAdvisoryReason.allCases.filter(reasons.contains)
            .sorted { $0.level > $1.level }
        return DigestionAdvisory(level: top, reasons: ordered)
    }

    /// The seven logical days ending on `day`, as day keys.
    static func window(endingOn day: String, timeModel: TimeModel) -> Set<String> {
        var keys: Set<String> = [day]
        var current = LogicalDay(day)
        for _ in 0..<6 {
            guard let previous = timeModel.day(before: current) else { break }
            keys.insert(previous.value)
            current = previous
        }
        return keys
    }
}
