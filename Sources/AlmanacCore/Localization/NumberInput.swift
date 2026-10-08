import Foundation

/// Numbers as a person types them, in either of the app's languages.
///
/// With Almanac in Arabic, the number pad types Arabic-Indic digits (٧٢٫٥) and
/// `Double("٧٢٫٥")` is nil, so every numeric field would refuse every value.
/// Each field parses through `Double(userInput:)` or `Int(userInput:)`
/// instead. They read Arabic-Indic and Persian digits and the Arabic decimal
/// separator, and ignore the direction marks an Arabic text field can insert.
/// What reaches the database is the same number either way (#4, decision 2).
public enum NumberInput {
    /// `text` with its digits and separators in ASCII and surrounding
    /// whitespace trimmed. ٠–٩ and ۰–۹ become 0–9, the Arabic decimal
    /// separator (٫) becomes ".", and the Arabic thousands separator (٬) and
    /// bidirectional marks are dropped. Anything else is left for the parser to
    /// accept or refuse.
    public static func ascii(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0660...0x0669: result.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9: result.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0x066B: result += "."
            case 0x066C, 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: continue
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Double {
    /// What a person typed, in either language's digits. Nil for whatever
    /// `Double(_:)` refuses once the digits are ASCII, an empty field included.
    public init?(userInput text: String) {
        self.init(NumberInput.ascii(text))
    }
}

extension Int {
    /// What a person typed, in either language's digits. Nil for whatever
    /// `Int(_:)` refuses once the digits are ASCII, an empty field included.
    public init?(userInput text: String) {
        self.init(NumberInput.ascii(text))
    }
}

/// Numbers on screen, in the digits of the language the app runs in (#4,
/// decision 3): ٧٢٫٥ in Arabic, 72.5 in English.
///
/// Takes text a number has already been written into with ASCII digits and
/// ".", by `String(_:)` or `String(format:)`, and changes only the glyphs. So
/// rounding, padding and the number of decimals stay exactly what the caller
/// chose, and an English run, Linux tests included, gets back the same text.
/// Only for a number on its own: a sentence or a name can hold digits that are
/// not a quantity.
///
/// Only a locale whose digits are not ASCII changes anything, so what this
/// writes is always what `NumberInput` reads back. An English run in Germany
/// keeps "72.5" rather than getting a "72,5" its own fields would refuse.
public enum NumberDisplay {
    public static func localized(_ ascii: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        guard let zero = formatter.string(from: 0)?.unicodeScalars.first, zero != "0" else { return ascii }
        let separator = formatter.decimalSeparator ?? "."
        var result = ""
        for scalar in ascii.unicodeScalars {
            if ("0"..."9").contains(scalar),
               let digit = Unicode.Scalar(zero.value + scalar.value - 0x30) {
                result.unicodeScalars.append(digit)
            } else if scalar == "." {
                result += separator
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
