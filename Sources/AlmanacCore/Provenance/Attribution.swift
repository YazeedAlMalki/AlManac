import Foundation

/// One licence a source ships under, with the link the Attributions page
/// shows. A source can carry more than one licence (wger licenses each
/// exercise separately), so an `Attribution` holds a list of these rather
/// than a single name/URL pair.
public struct LicenseReference: Sendable, Hashable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

/// A credits entry for one third-party source, in the shape the CC BY-SA
/// obligation needs: title, author, source link, licence(s) + link, and —
/// when Almanac changed the files — a statement of what changed.
public struct Attribution: Sendable, Hashable {
    public let sourceId: String
    public let title: String
    public let author: String
    public let sourceURL: String
    public let licenses: [LicenseReference]
    public let isModified: Bool
    public let modificationNote: String?

    public init(sourceId: String, title: String, author: String, sourceURL: String,
                licenses: [LicenseReference], isModified: Bool = false, modificationNote: String? = nil) {
        self.sourceId = sourceId
        self.title = title
        self.author = author
        self.sourceURL = sourceURL
        self.licenses = licenses
        self.isModified = isModified
        self.modificationNote = modificationNote
    }
}

public struct MissingAttribution: Error, CustomStringConvertible, Sendable {
    public let sourceId: String
    public init(sourceId: String) { self.sourceId = sourceId }
    public var description: String {
        "BUILD FAILURE: bundled source '\(sourceId)' has no entry on the Attributions page."
    }
}

public struct IncompleteAttribution: Error, CustomStringConvertible, Sendable {
    public let sourceId: String
    public let reason: String
    public init(sourceId: String, reason: String) {
        self.sourceId = sourceId
        self.reason = reason
    }
    public var description: String {
        "BUILD FAILURE: the attribution entry for '\(sourceId)' \(reason)."
    }
}

/// The Attributions page's content, bundled in the app so it works offline.
///
/// `bundledSourceIds` is the set of sources the build actually ships — it is
/// deliberately separate from `entries` so that a source can be vetted and
/// documented here without being claimed as shipped. `wger` is the only
/// third-party exercise source in the app today (its 21-row CC0 seed).
public enum AttributionCatalog {
    public static let cc0 = LicenseReference(name: "CC0 1.0",
        url: "https://creativecommons.org/publicdomain/zero/1.0/")
    public static let ccBySa30 = LicenseReference(name: "CC BY-SA 3.0",
        url: "https://creativecommons.org/licenses/by-sa/3.0/")
    public static let ccBySa40 = LicenseReference(name: "CC BY-SA 4.0",
        url: "https://creativecommons.org/licenses/by-sa/4.0/")
    public static let unlicense = LicenseReference(name: "Unlicense",
        url: "https://unlicense.org/")
    public static let mit = LicenseReference(name: "MIT",
        url: "https://opensource.org/license/mit")

    /// Sources the build ships. Append-only; adding an id here without a
    /// matching `entries` row fails `AttributionAudit`.
    public static let bundledSourceIds: [String] = ["workout-guide", "everkinetic"]

    public static let entries: [Attribution] = [
        Attribution(
            sourceId: "workout-guide",
            title: "workout-guide exercise illustrations and exercise list",
            author: "Bryl Lim",
            sourceURL: "https://github.com/bryllim/workout-guide",
            licenses: [ccBySa40]
        ),
        Attribution(
            sourceId: "everkinetic",
            title: "Everkinetic exercise illustrations",
            author: "Everkinetic",
            sourceURL: "https://github.com/everkinetic/data",
            licenses: [ccBySa40],
            // 76 of workout-guide's frames are derived from Everkinetic art, and
            // the derivation is a modification CC BY-SA requires us to state and
            // to release under the same licence. Almanac bundles the derived
            // PNGs without further change; the modification was made upstream
            // and its description is carried per frame in the bundled manifest.
            isModified: true,
            modificationNote: "76 of the 302 bundled illustrations are derived from these: "
                + "rasterized on a transparent 512 × 512 canvas, recoloured for monochrome "
                + "display, and vector-traced by workout-guide. Those 76 files are released by "
                + "workout-guide under CC BY-SA 4.0 and are shipped here unmodified."
        )
    ]

    public static func entry(for sourceId: String) -> Attribution? {
        entries.first { $0.sourceId == sourceId }
    }

    /// Maps the `exerciseCatalog.licenseGroup` codes the importer stores onto
    /// the licence name + link a per-exercise credit line shows.
    public static func licenseReference(forGroup group: String) -> LicenseReference? {
        switch group {
        case "cc0": return cc0
        case "cc_by_sa_3": return ccBySa30
        case "cc_by_sa_4": return ccBySa40
        case "unlicense": return unlicense
        case "mit": return mit
        default: return nil
        }
    }
}

/// The build guard the acceptance criteria call for: shipping a source with
/// no Attributions entry, or an incomplete entry, fails the build rather than
/// reaching users. Mirrors `BundleGuard.assertShippable`.
public enum AttributionAudit {
    public static func assertAttributed<S: Sequence>(
        _ bundledSourceIds: S,
        entries: [Attribution] = AttributionCatalog.entries
    ) throws where S.Element == String {
        var byId: [String: Attribution] = [:]
        for entry in entries {
            guard byId[entry.sourceId] == nil else {
                throw IncompleteAttribution(sourceId: entry.sourceId, reason: "has more than one entry")
            }
            byId[entry.sourceId] = entry
        }

        for sourceId in bundledSourceIds {
            guard let entry = byId[sourceId] else {
                throw MissingAttribution(sourceId: sourceId)
            }
            guard !entry.title.isEmpty, !entry.author.isEmpty, !entry.sourceURL.isEmpty else {
                throw IncompleteAttribution(sourceId: sourceId, reason: "is missing a title, author or source link")
            }
            guard !entry.licenses.isEmpty, entry.licenses.allSatisfy({ !$0.name.isEmpty && !$0.url.isEmpty }) else {
                throw IncompleteAttribution(sourceId: sourceId, reason: "is missing a licence name or link")
            }
            if entry.isModified, (entry.modificationNote ?? "").isEmpty {
                throw IncompleteAttribution(sourceId: sourceId,
                                            reason: "is marked as modified without saying what changed")
            }
        }
    }
}
