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
        var seen = Set<String>()
        var credits: [ExerciseAuthorCredit] = []
        for entry in entries {
            guard let author = entry.licenseAuthor, !author.isEmpty else { continue }
            let license = AttributionCatalog.licenseReference(forGroup: entry.licenseGroup)
            let key = "\(author)|\(license?.url ?? entry.licenseGroup)"
            guard seen.insert(key).inserted else { continue }
            credits.append(ExerciseAuthorCredit(author: author, license: license))
        }
        return credits.sorted { ($0.author, $0.license?.name ?? "") < ($1.author, $1.license?.name ?? "") }
    }
}
