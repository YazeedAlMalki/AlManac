import Testing
import Foundation
@testable import AlmanacCore

/// The Attributions page is content bundled in the app, and this suite is the
/// build gate that keeps it honest: every source the app actually bundles must
/// have an entry, and each entry must carry the four things a CC BY-SA
/// obligation needs — title, author, source link, licence + link. Mirrors
/// `ProvenanceTests`' `BundleGuard` pattern: a missing entry is a test
/// failure, and therefore a build failure, not a discovery made after ship.
@Suite("Attribution catalog + build guard")
struct AttributionTests {

    @Test("Every bundled source passes the attribution build guard")
    func bundledSourcesAreAttributed() throws {
        // Reads the real registry and the real bundled-source list, so this
        // test is the guard rather than a restatement of it.
        try AttributionAudit.assertAttributed(AttributionCatalog.bundledSourceIds)
    }

    @Test("Every shipped nutrition source has its publisher and licence details")
    func nutritionSourcesAreCredited() {
        let expected: [String: (title: String, author: String, notice: String, url: String,
                                licenses: [String: String], modified: Bool)] = [
            "usda": ("USDA FoodData Central, Foundation Foods",
                     "U.S. Department of Agriculture, Agricultural Research Service",
                     "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019. fdc.nal.usda.gov.",
                     "https://fdc.nal.usda.gov/",
                     ["CC0 1.0 Universal": "https://creativecommons.org/publicdomain/zero/1.0/"], false),
            "ciqual": ("ANSES-CIQUAL French food composition table 2025", "ANSES",
                       "ANSES. Table de composition nutritionnelle des aliments Ciqual 2025. Licensed under CC BY 4.0.",
                       "https://doi.org/10.5281/zenodo.17550133",
                       ["CC BY 4.0": "https://creativecommons.org/licenses/by/4.0/",
                        "Etalab Open Licence 2.0": "https://www.etalab.gouv.fr/licence-ouverte-open-licence"], true),
            "cofid": ("McCance and Widdowson's Composition of Foods Integrated Dataset 2021",
                      "Public Health England",
                      "Contains public sector information licensed under the Open Government Licence v3.0. Source: McCance and Widdowson's The Composition of Foods Integrated Dataset 2021, Public Health England.",
                      "https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid",
                      ["Open Government Licence v3.0": "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/"], true),
            "afcd": ("Australian Food Composition Database, Release 3",
                     "Food Standards Australia New Zealand",
                     "Food Standards Australia New Zealand. Australian Food Composition Database, Release 3. Licensed under CC BY 4.0. FSANZ does not endorse Almanac or its use of the work.",
                     "https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd",
                     ["CC BY 4.0": "https://creativecommons.org/licenses/by/4.0/"], true)
        ]

        #expect(Set(expected.keys).isSubset(of: Set(AttributionCatalog.bundledSourceIds)))
        for (id, details) in expected {
            let entry = AttributionCatalog.entry(for: id)
            #expect(entry?.title == details.title, "\(id) title")
            #expect(entry?.author == details.author, "\(id) author")
            #expect(entry?.sourceNotice == details.notice, "\(id) source notice")
            #expect(entry?.sourceURL == details.url, "\(id) source URL")
            #expect(Set(entry?.licenses.map(\.name) ?? []) == Set(details.licenses.keys), "\(id) licences")
            #expect(Dictionary(uniqueKeysWithValues: entry?.licenses.map { ($0.name, $0.url) } ?? [])
                    == details.licenses, "\(id) licence links")
            #expect(entry?.isModified == details.modified, "\(id) modification status")
            if details.modified {
                let note = entry?.modificationNote ?? ""
                #expect(note.isEmpty == false, "\(id) change note")
            }
        }
    }

    @Test("A bundled source with no entry fails the build")
    func missingEntryFailsTheBuild() {
        #expect(throws: MissingAttribution.self) {
            try AttributionAudit.assertAttributed(["free-exercise-db"])
        }
    }

    @Test("Every entry carries title, author, source link and at least one licence link")
    func entriesAreComplete() {
        #expect(!AttributionCatalog.entries.isEmpty)
        for entry in AttributionCatalog.entries {
            #expect(!entry.title.isEmpty, "\(entry.sourceId) needs a title")
            #expect(!entry.author.isEmpty, "\(entry.sourceId) needs an author")
            #expect(!entry.sourceURL.isEmpty, "\(entry.sourceId) needs a source link")
            #expect(!entry.licenses.isEmpty, "\(entry.sourceId) needs at least one licence")
            for license in entry.licenses {
                #expect(!license.name.isEmpty, "\(entry.sourceId) has an unnamed licence")
                #expect(license.url.hasPrefix("https://"), "\(entry.sourceId) licence link must be a URL")
            }
        }
    }

    @Test("Every bundled source id resolves to an entry")
    func bundledIdsResolve() {
        for id in AttributionCatalog.bundledSourceIds {
            #expect(AttributionCatalog.entry(for: id) != nil, "\(id) is bundled but has no entry")
        }
    }

    @Test("An entry marked modified without a description fails the build")
    func modifiedWithoutNoteFailsTheBuild() {
        let bad = Attribution(sourceId: "x", title: "X", author: "A", sourceURL: "https://example.org",
                              licenses: [AttributionCatalog.cc0], isModified: true, modificationNote: nil)
        #expect(throws: IncompleteAttribution.self) {
            try AttributionAudit.assertAttributed(["x"], entries: [bad])
        }
    }

    @Test("A modified entry that describes the change passes")
    func modifiedWithNotePasses() throws {
        let good = Attribution(sourceId: "x", title: "X", author: "A", sourceURL: "https://example.org",
                               licenses: [AttributionCatalog.cc0], isModified: true,
                               modificationNote: "Recoloured at render time; no pixels changed.")
        try AttributionAudit.assertAttributed(["x"], entries: [good])
    }

    @Test("Stored exercise licence-group codes map to a licence and link")
    func licenceGroupCodesMap() {
        #expect(AttributionCatalog.licenseReference(forGroup: "cc0")?.name == "CC0 1.0")
        #expect(AttributionCatalog.licenseReference(forGroup: "cc_by_sa_3")?.name == "CC BY-SA 3.0")
        #expect(AttributionCatalog.licenseReference(forGroup: "cc_by_sa_4")?.url
                == "https://creativecommons.org/licenses/by-sa/4.0/")
        #expect(AttributionCatalog.licenseReference(forGroup: "not_a_licence") == nil)
    }
}
