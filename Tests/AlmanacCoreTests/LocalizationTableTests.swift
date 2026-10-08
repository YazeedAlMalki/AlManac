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

    /// Every `localized("…")` key written in AlmanacCore, read from the source:
    /// the strict half of the gate the app's catalog gets from the compiler.
    func sourceKeys() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AlmanacCore")
        let call = try NSRegularExpression(pattern: #"\blocalized\(\s*"((?:[^"\\]|\\.)*)""#)
        var keys: Set<String> = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "Localized.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let literal = String(text[Range(match.range(at: 1), in: text)!])
                keys.insert(literal.replacingOccurrences(of: #"\""#, with: "\"")
                                   .replacingOccurrences(of: #"\\"#, with: "\\"))
            }
        }
        return keys
    }

    @Test("Every localized(…) key in AlmanacCore has Arabic")
    func everyKeyTranslated() throws {
        let arabic = try table("ar")
        let keys = try sourceKeys()
        #expect(keys.count >= 3, "the source scan found almost nothing: \(keys)")
        let missing = keys.filter { arabic[$0] == nil }.sorted()
        #expect(missing.isEmpty, "no Arabic for: \(missing)")
    }

    @Test("Arguments fill %@ in order, and %1$@ by position")
    func substitution() {
        #expect(substitute("Fajr is at %@. The fast begins soon.", ["04:41"]) == "Fajr is at 04:41. The fast begins soon.")
        #expect(substitute("%2$@ then %1$@", ["a", "b"]) == "b then a")
        #expect(substitute("%@ and %@", ["%@", "x"]) == "%@ and x")
        #expect(substitute("100%% of %@", ["goal"]) == "100% of goal")
        #expect(localized("Names %@", "Peanuts") == "Names Peanuts")
    }

    @Test("The specifier check sees what it is meant to")
    func specifierExtraction() {
        #expect(specifiers("Logged on %lld of the last %lld days") == ["%lld", "%lld"])
        #expect(specifiers("%2$@ before %1$lld") == ["%@", "%lld"])
        #expect(specifiers("100%% sure") == [])
    }
}

/// `ReadinessText` reads back every shape `ReadinessEngine` writes. In the
/// development language a translation is the identity, so each one must come
/// back exactly as the engine wrote it — which also proves the parse takes the
/// sentence apart and puts it back together at the same seams.
@Suite("Readiness text for display")
struct ReadinessTextTests {
    @Test("Every engine sentence survives the round trip unchanged")
    func roundTrip() {
        let band = ReadinessFormula.bandText(for: 72)
        for english in [
            band,
            "\(band). · Fasted training context noted · Active injury: left knee · Score is preliminary (calibrating: 4/28)",
            "Active injury (left knee) — train around it. \(band).",
            "Active injury (unspecified area) — train around it. Not enough data to score readiness..",
            "\(band). Session is planned religiously fasted — compared against fasted days only.",
            "Deload week: continue reduced load.",
            "Something the engine never wrote",
        ] {
            #expect(ReadinessText.display(english) == english)
        }
    }
}
