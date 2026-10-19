import Foundation

/// One distinct exercise author credited on the Attributions page, with the
/// licence their rows carry. wger licenses and names an author per exercise,
/// so the page lists these individually rather than one credit per row.
public struct ExerciseAuthorCredit: Sendable, Hashable, Identifiable {
    public let author: String
    public let license: LicenseReference?

    public var id: String { "\(author)|\(license?.url ?? "")" }

    public init(author: String, license: LicenseReference?) {
        self.author = author
        self.license = license
    }
}

public enum ExerciseAuthorCredits {
    /// Distinct (author, licence) pairs across the given catalog rows — nil or
    /// blank authors dropped, deterministic order. Pure, so the page's
    /// rendering has nothing to get wrong and the list is testable without UI.
    public static func distinct(from entries: [ExerciseCatalogEntry]) -> [ExerciseAuthorCredit] {
        distinct(entries.map { (author: $0.licenseAuthor, licenseGroup: $0.licenseGroup) })
    }

    /// The same for the sources merged into records (`exerciseSource`), whose
    /// authors a catalogue row alone would not name.
    public static func distinct(from sources: [ExerciseSourceRecord]) -> [ExerciseAuthorCredit] {
        distinct(sources.map { (author: $0.licenseAuthor, licenseGroup: $0.licenseGroup) })
    }

    public static func distinct(_ pairs: [(author: String?, licenseGroup: String)]) -> [ExerciseAuthorCredit] {
        var seen = Set<String>()
        var credits: [ExerciseAuthorCredit] = []
        for (author, licenseGroup) in pairs {
            guard let author, !author.isEmpty else { continue }
            let license = AttributionCatalog.licenseReference(forGroup: licenseGroup)
            let key = "\(author)|\(license?.url ?? licenseGroup)"
            guard seen.insert(key).inserted else { continue }
            credits.append(ExerciseAuthorCredit(author: author, license: license))
        }
        return credits.sorted { ($0.author, $0.license?.name ?? "") < ($1.author, $1.license?.name ?? "") }
    }
}
