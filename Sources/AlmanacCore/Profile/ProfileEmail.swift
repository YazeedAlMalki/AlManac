import Foundation

/// The rule for the profile's email address, and the one thing it unlocks.
///
/// The owner (2026-10-20): backups are for a person "registered with a valid
/// email". Valid here means *well formed*, which is all a phone can check on
/// its own: proving the address exists means sending it mail, and Almanac has
/// no server (BRD §1, principle 5). One `@`, something before it, a domain with
/// a dot after it, and no spaces.
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

extension UserProfile {
    /// Whether this person may create a backup: they have saved a well-formed
    /// email address. Restoring is not gated; a new phone restores before it
    /// has a profile of its own.
    public var mayCreateBackup: Bool { ProfileEmail.isValid(email) }
}
