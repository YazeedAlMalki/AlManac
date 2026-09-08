import Foundation

/// Folds text for alias matching: case, diacritics, punctuation and script
/// variants removed, whitespace collapsed.
///
/// Arabic normalisation is explicit rather than left to a locale: an Arabic
/// report writing إ where the catalog has ا must still match, and harakat and
/// tatweel are decoration, not identity.
public enum TextFold {
    public static func fold(_ input: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in input.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            if CharacterSet.nonBaseCharacters.contains(scalar) { continue }
            if scalar.value == 0x0640 { continue }               // Arabic tatweel
            let mapped = normalise(scalar)
            if CharacterSet.alphanumerics.contains(mapped) {
                scalars.append(mapped)
            } else {
                scalars.append(" ")
            }
        }
        return String(String(scalars).split(separator: " ").joined(separator: " "))
    }

    private static func normalise(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0x0622, 0x0623, 0x0625, 0x0671: return "\u{0627}"   // آ أ إ ٱ -> ا
        case 0x0649, 0x0626:                 return "\u{064A}"   // ى ئ -> ي
        case 0x0629:                         return "\u{0647}"   // ة -> ه
        case 0x0624:                         return "\u{0648}"   // ؤ -> و
        case 0x0660...0x0669:                                     // Arabic-Indic digits
            return Unicode.Scalar(scalar.value - 0x0660 + 0x30)!
        case 0x06F0...0x06F9:                                     // Extended Arabic-Indic
            return Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!
        default: return scalar
        }
    }
}
