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
    public let sourceNotice: String?
    public let sourceURL: String
    public let licenses: [LicenseReference]
    public let isModified: Bool
    public let modificationNote: String?

    public init(sourceId: String, title: String, author: String, sourceURL: String,
                licenses: [LicenseReference], isModified: Bool = false, modificationNote: String? = nil,
                sourceNotice: String? = nil) {
        self.sourceId = sourceId
        self.title = title
        self.author = author
        self.sourceNotice = sourceNotice
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
/// documented here without being claimed as shipped.
public enum AttributionCatalog {
    public static let cc0 = LicenseReference(name: "CC0 1.0",
        url: "https://creativecommons.org/publicdomain/zero/1.0/")
    public static let ccBySa30 = LicenseReference(name: "CC BY-SA 3.0",
        url: "https://creativecommons.org/licenses/by-sa/3.0/")
    public static let ccBySa40 = LicenseReference(name: "CC BY-SA 4.0",
        url: "https://creativecommons.org/licenses/by-sa/4.0/")
    public static let cc0Universal = LicenseReference(name: "CC0 1.0 Universal",
        url: "https://creativecommons.org/publicdomain/zero/1.0/")
    public static let ccBy40 = LicenseReference(name: "CC BY 4.0",
        url: "https://creativecommons.org/licenses/by/4.0/")
    public static let etalabOpen2 = LicenseReference(name: "Etalab Open Licence 2.0",
        url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence")
    public static let openGovernment3 = LicenseReference(name: "Open Government Licence v3.0",
        url: "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/")
    public static let unlicense = LicenseReference(name: "Unlicense",
        url: "https://unlicense.org/")
    public static let mit = LicenseReference(name: "MIT",
        url: "https://opensource.org/license/mit")

    /// Sources the build ships. Append-only; adding an id here without a
    /// matching `entries` row fails `AttributionAudit`.
    public static let bundledSourceIds: [String] = [
        "workout-guide", "everkinetic", "usda", "ciqual", "cofid", "afcd"
    ]

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
        ),
        Attribution(
            sourceId: "usda",
            title: "USDA FoodData Central, Foundation Foods",
            author: "U.S. Department of Agriculture, Agricultural Research Service",
            sourceURL: "https://fdc.nal.usda.gov/",
            licenses: [cc0Universal],
            sourceNotice: "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019. fdc.nal.usda.gov."
        ),
        Attribution(
            sourceId: "ciqual",
            title: "ANSES-CIQUAL French food composition table 2025",
            author: "ANSES",
            sourceURL: "https://doi.org/10.5281/zenodo.17550133",
            licenses: [ccBy40, etalabOpen2],
            isModified: true,
            modificationNote: "Converted from ANSES's release XML into Almanac's normalized nutrition "
                + "schema; only mapped foods, nutrients and portions are retained. Published nutrient "
                + "values are preserved.",
            sourceNotice: "ANSES. Table de composition nutritionnelle des aliments Ciqual 2025. Licensed under CC BY 4.0."
        ),
        Attribution(
            sourceId: "cofid",
            title: "McCance and Widdowson's Composition of Foods Integrated Dataset 2021",
            author: "Public Health England",
            sourceURL: "https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid",
            licenses: [openGovernment3],
            isModified: true,
            modificationNote: "Converted from the integrated dataset into Almanac's normalized nutrition "
                + "schema; only mapped foods, nutrients and portions are retained. Published nutrient "
                + "values are preserved.",
            sourceNotice: "Contains public sector information licensed under the Open Government Licence v3.0. "
                + "Source: McCance and Widdowson's The Composition of Foods Integrated Dataset 2021, Public Health England."
        ),
        Attribution(
            sourceId: "afcd",
            title: "Australian Food Composition Database, Release 3",
            author: "Food Standards Australia New Zealand",
            sourceURL: "https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd",
            licenses: [ccBy40],
            isModified: true,
            modificationNote: "Converted into Almanac's normalized nutrition schema; only mapped foods, "
                + "nutrients and portions are retained. Published energy values were converted from kJ "
                + "to kcal.",
            sourceNotice: "Food Standards Australia New Zealand. Australian Food Composition Database, "
                + "Release 3. Licensed under CC BY 4.0. FSANZ does not endorse Almanac or its use of the work."
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
