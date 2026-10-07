import Foundation
import Testing
@testable import AlmanacCore

/// AlmanacCore's Arabic string table (#4): shipped in the package's bundle,
/// parseable, and faithful to its keys' format specifiers. A `%lld` dropped or
/// turned into `%@` in a translation is a wrong number or a crash at runtime,
/// and only on a phone running Arabic, so it is checked here, where it fails
/// on every push.
@Suite("Localization tables")
struct LocalizationTableTests {
    func table(_ language: String) throws -> [String: String] {
        let root = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let url = root.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, String(decoding: data, as: UTF8.self).contains("=") else { return [:] }
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
                            "\(language).lproj/Localizable.strings is not a strings table")
    }

    /// The format specifiers in `text`, without positions: `%2$@` is `%@`.
    func specifiers(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[-+ #0]*\\d*(?:\\.\\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcs%]")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range)
            .map { String(text[Range($0.range, in: text)!]) }
            .map { $0.replacingOccurrences(of: "\\d+\\$", with: "", options: .regularExpression) }
            .filter { $0 != "%%" }
            .sorted()
    }

    @Test("The Arabic table carries every specifier its key does, and no empty value")
    func specifiersMatch() throws {
        let arabic = try table("ar")
        #expect(!arabic.isEmpty)
        for (key, value) in arabic {
            #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "empty Arabic for \(key)")
            #expect(specifiers(value) == specifiers(key), "\(key) → \(value)")
        }
    }

    @Test("The bottom bar's titles are translated, and read as English here")
    func tabTitles() throws {
        let arabic = try table("ar")
        for tab in AppTab.allCases {
            // The tests run in the development language, so the key comes back.
            #expect(arabic[tab.title] != nil, "no Arabic for the \(tab.title) tab")
        }
        #expect(AppTab.today.title == "Today")
        #expect(arabic["Today"] == "اليوم")
    }

    @Test("The specifier check sees what it is meant to")
    func specifierExtraction() {
        #expect(specifiers("Logged on %lld of the last %lld days") == ["%lld", "%lld"])
        #expect(specifiers("%2$@ before %1$lld") == ["%@", "%lld"])
        #expect(specifiers("100%% sure") == [])
    }
}
