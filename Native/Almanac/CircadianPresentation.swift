import AlmanacCore

/// The wording for a day's circadian context (§13, BRD §4.3).
///
/// `CircadianContextType` is the schema's enumeration, and it is not written to
/// be read aloud: `transition_later` and `stable_evening` are column values, not
/// sentences. This is the one place a user's own rhythm is put into words, so
/// the wording is here rather than scattered across whichever screen happens to
/// show it.
///
/// **Every case has a sentence, including the boring ones.** `.unknown` is not
/// an error state to be hidden — it is what a user with no shift schedule gets,
/// which §6.11 requires to stay fully supported, and the honest thing to say
/// about it is nothing rather than "your circadian rhythm is irregular".
enum CircadianPresentation {

    /// One line describing the day, or nil when there is nothing worth saying.
    ///
    /// Nil for `.unknown` specifically: with no shift schedule there is no
    /// circadian claim to make, and a screen that printed "No schedule recorded"
    /// on every day of a non-shift user's life would be noise dressed as
    /// information.
    static func line(for type: CircadianContextType, transitionDayN: Int?) -> String? {
        switch type {
        case .stableDay: return "A settled daytime rhythm."
        case .stableEvening: return "A settled evening rhythm."
        case .stableNight: return "A settled night rhythm."
        case .transitionEarlier:
            return earlier(transitionDayN)
        case .transitionLater:
            return later(transitionDayN)
        case .firstDayAfterNight:
            return "The first day back after a run of night shifts."
        case .recovery: return "A rest day."
        case .irregular: return "A pattern that does not settle into a rhythm yet."
        case .unknown: return nil
        }
    }

    /// A short label for a dense surface, where the sentence above will not fit.
    static func shortLabel(for type: CircadianContextType) -> String? {
        switch type {
        case .stableDay: return "Day rhythm"
        case .stableEvening: return "Evening rhythm"
        case .stableNight: return "Night rhythm"
        case .transitionEarlier: return "Moving earlier"
        case .transitionLater: return "Moving later"
        case .firstDayAfterNight: return "First day back"
        case .recovery: return "Rest day"
        case .irregular: return "Still irregular"
        case .unknown: return nil
        }
    }

    /// Whether this context is one a correlation should not be computed across.
    /// Kept beside the wording because the two are the same fact: the sentence
    /// above tells the user why a number was narrowed, and this is the narrowing.
    static func isTransition(_ type: CircadianContextType) -> Bool {
        type == .transitionEarlier || type == .transitionLater
    }

    // MARK: - Private

    /// §13.1 names the two directions: coming off nights onto days moves
    /// everything earlier, and the reverse moves it later. The day number is
    /// stated because "moving later" is a process and a user in the middle of
    /// one wants to know how far in they are.
    private static func earlier(_ n: Int?) -> String {
        guard let n, n > 1 else { return "The first day of a move to earlier hours." }
        return "Day \(n) of moving to earlier hours."
    }

    private static func later(_ n: Int?) -> String {
        guard let n, n > 1 else { return "The first day of a move to later hours." }
        return "Day \(n) of moving to later hours."
    }
}
