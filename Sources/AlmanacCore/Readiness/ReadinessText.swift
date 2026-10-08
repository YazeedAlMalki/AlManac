import Foundation

/// Readiness's sentences, in the language the app runs in.
///
/// `ReadinessEngine` writes its description and recommendation in English, and
/// `readiness_record` stores them, so the database reads the same whatever
/// language the app runs in (#4). This translates one of those sentences —
/// today's, or a stored one on the trend — at the moment it is shown. It knows
/// the shapes the engine composes: a band sentence followed by ". · "-separated
/// context notes, the injury and fasted-session recommendations wrapped around
/// a band sentence, and the fixed sentences. Anything else is shown as stored.
public enum ReadinessText {
    public static func display(_ english: String) -> String {
        if let split = english.range(of: ". · ") {
            let notes = english[split.upperBound...].components(separatedBy: " · ")
            return sentence(String(english[..<split.lowerBound])) + ". "
                + notes.map { "· " + note($0) }.joined(separator: " ")
        }
        let injury = "Active injury (", injuryTail = ") — train around it. "
        if english.hasPrefix(injury), let tail = english.range(of: injuryTail) {
            let area = String(english[english.index(english.startIndex, offsetBy: injury.count)..<tail.lowerBound])
            var fallback = String(english[tail.upperBound...])
            if fallback.hasSuffix(".") { fallback.removeLast() }
            return localized("Active injury (%@) — train around it. %@.",
                             area == "unspecified area" ? localized("unspecified area") : area, sentence(fallback))
        }
        let fasted = ". Session is planned religiously fasted — compared against fasted days only."
        if english.hasSuffix(fasted) {
            return localized("%@. Session is planned religiously fasted — compared against fasted days only.",
                             sentence(String(english.dropLast(fasted.count))))
        }
        return sentence(english)
    }

    private static func sentence(_ english: String) -> String {
        switch english {
        case "Recovery is excellent — ready for maximum effort":
            return localized("Recovery is excellent — ready for maximum effort")
        case "Recovery is good — ready for a strong session":
            return localized("Recovery is good — ready for a strong session")
        case "Moderate recovery — train at reduced intensity":
            return localized("Moderate recovery — train at reduced intensity")
        case "Recovery is below baseline — consider a light session":
            return localized("Recovery is below baseline — consider a light session")
        case "Recovery is poor — prioritise rest today":
            return localized("Recovery is poor — prioritise rest today")
        case "Recovery is very low — rest is the best training decision":
            return localized("Recovery is very low — rest is the best training decision")
        case "Not enough data to score readiness.":
            return localized("Not enough data to score readiness.")
        case "Recovery day: rest as planned.":
            return localized("Recovery day: rest as planned.")
        case "Rest day as planned.":
            return localized("Rest day as planned.")
        case "Deload week: continue reduced load.":
            return localized("Deload week: continue reduced load.")
        default:
            return english
        }
    }

    private static func note(_ english: String) -> String {
        switch english {
        case "Fasted training context noted": return localized("Fasted training context noted")
        case "Limited comparable shift data": return localized("Limited comparable shift data")
        case "Planned deload — continue reduced load": return localized("Planned deload — continue reduced load")
        case "Planned rest day": return localized("Planned rest day")
        default:
            if english.hasPrefix("Active injury: ") {
                return localized("Active injury: %@", String(english.dropFirst("Active injury: ".count)))
            }
            let calibrating = "Score is preliminary (calibrating: "
            if english.hasPrefix(calibrating), english.hasSuffix(")") {
                let days = english.dropFirst(calibrating.count).dropLast().split(separator: "/")
                if days.count == 2 {
                    return localized("Score is preliminary (calibrating: %@/%@)",
                                     NumberDisplay.localized(String(days[0])), NumberDisplay.localized(String(days[1])))
                }
            }
            return english
        }
    }
}
