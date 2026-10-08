import Foundation

/// Interface text written in AlmanacCore, in the language the app runs in.
///
/// The English text is the key, so a string with no Arabic entry yet shows in
/// English rather than as a key — and every test that reads English keeps
/// reading English, because the tests run in the development localisation.
/// The Arabic table is `Localization/Resources/ar.lproj/Localizable.strings`;
/// `LocalizationTableTests` checks that every `localized("…")` key in this
/// module has an Arabic entry with the same specifiers.
///
/// The app switches language through iOS's own per-app Language setting
/// (#4), so there is no language state here: `Bundle.module` resolves against
/// the languages iOS hands the app.
///
/// **Only for text that is shown, never for text that is stored or compared.**
/// A default name written to the database, or a key a view groups by, stays
/// English; it is translated where it is displayed, so switching language
/// never changes the data.
func localized(_ english: String) -> String {
    NSLocalizedString(english, bundle: .module, comment: "")
}

/// `localized(_:)` with values in it: each `%@` takes the next argument, and a
/// translation that needs another order writes `%1$@`, `%2$@`.
///
/// Arguments are strings — a number is formatted by the caller — because
/// `String(format:)` cannot take a Swift `String` for `%@` on Linux, where the
/// core is tested.
func localized(_ english: String, _ arguments: String...) -> String {
    substitute(localized(english), arguments)
}

/// Fills `%1$@`-style and then plain `%@` placeholders from `arguments`,
/// scanning forwards so an argument that itself contains `%@` is left alone.
func substitute(_ format: String, _ arguments: [String]) -> String {
    var result = ""
    var next = 0
    var rest = Substring(format)
    while let percent = rest.firstIndex(of: "%") {
        result += rest[..<percent]
        let after = rest[rest.index(after: percent)...]
        if after.hasPrefix("@") {
            result += next < arguments.count ? arguments[next] : ""
            next += 1
            rest = after.dropFirst()
        } else if let dollar = after.firstIndex(of: "$"),
                  let position = Int(after[..<dollar]),
                  after[after.index(after: dollar)...].hasPrefix("@") {
            result += arguments.indices.contains(position - 1) ? arguments[position - 1] : ""
            rest = after[after.index(after: dollar)...].dropFirst()
        } else if after.hasPrefix("%") {
            result += "%"
            rest = after.dropFirst()
        } else {
            result += "%"
            rest = after
        }
    }
    return result + rest
}

/// "A", "A and B", "A, B and C", in the language the app runs in. The
/// connectors are table entries, so in Arabic the same list reads "أ، ب وج".
func localizedList(_ items: [String]) -> String {
    guard let last = items.last else { return "" }
    guard items.count > 1 else { return last }
    return localized("%@ and %@", items.dropLast().joined(separator: localized(", ")), last)
}
