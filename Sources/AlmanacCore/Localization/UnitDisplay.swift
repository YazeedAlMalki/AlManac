import Foundation

/// A unit as shown, for the handful Almanac writes itself.
///
/// Units are stored as codes ("ml", "bpm") and compared as codes, so they are
/// never translated where they are kept. This translates them where they are
/// read. Any other unit, such as a laboratory's "mmol/L", is the source's own
/// text and is shown as it was given.
public enum UnitDisplay {
    public static func localized(_ unit: String) -> String {
        switch unit {
        case "ml", "mL": return AlmanacCore.localized("mL")
        case "kg": return AlmanacCore.localized("kg")
        case "bpm": return AlmanacCore.localized("bpm")
        case "ms": return AlmanacCore.localized("ms")
        case "min": return AlmanacCore.localized("min")
        case "kcal": return AlmanacCore.localized("kcal")
        case "mg": return AlmanacCore.localized("mg")
        case "/10": return AlmanacCore.localized("/10")
        default: return unit
        }
    }
}
