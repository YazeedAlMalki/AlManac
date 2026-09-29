import Foundation

/// Folds text for alias matching: case, diacritics, punctuation and script
/// variants removed, whitespace collapsed.
///
/// Arabic normalisation is explicit rather than left to a locale: an Arabic
/// report writing إ where the catalog has ا must still match, and harakat and
/// tatweel are decoration, not identity.
///
/// **`%` is kept, as the token `pct`.** Everything else in this method is
/// erased on the grounds that the difference carries no identity — case,
/// hyphen, a trailing bracket. A percent sign does carry identity, and folding
/// it away makes two different analytes indistinguishable. "Neutrophils" and
/// "Neutrophils %" are an absolute count in `cellsPerVolume` and a proportion in
/// `percentage`, they move independently, and a fold that maps both to
/// `neutrophils` would make the importer pick between them at random — which is
/// the precise failure `LabCatalog.match`'s ambiguity handling exists to
/// prevent, provoked by the fold rather than by the catalog. Found by seeding
/// the five differential percentages, which was impossible until this changed.
public enum TextFold {
    public static func fold(_ input: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in input.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            if CharacterSet.nonBaseCharacters.contains(scalar) { continue }
            if scalar.value == 0x0640 { continue }               // Arabic tatweel
            if scalar.value == 0x0025 { scalars.append(" "); scalars.append("p"); scalars.append("c"); scalars.append("t"); continue }
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
