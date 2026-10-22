import Foundation

/// The rule for the profile's optional email address.
///
/// The email is not used for anything: it unlocks nothing and is never sent
/// (Almanac has no server, BRD §1 principle 5). Creating a backup used to need
/// one (owner, 2026-10-20); the security audit found that a collected value with
/// no purpose, which also travels inside every backup, is data minimisation noise
/// (finding §5.2 row 5), and the owner authorised removing the requirement on
/// 2026-10-22. Valid here means *well formed*, which is all a phone can check on
/// its own. One `@`, something before it, a domain with a dot after it, and no
/// spaces.
public enum ProfileEmail {
    /// `text` trimmed, if it is a well-formed address; `nil` otherwise.
    public static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count <= 254,
              !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        return trimmed
    }

    public static func isValid(_ text: String?) -> Bool { normalized(text) != nil }
}

public enum ProfileEmailError: Error, Equatable {
    /// Not saved: the text is not a well-formed address.
    case invalid
}
