import Foundation

/// Interface text written in AlmanacCore, in the language the app runs in.
///
/// The English text is the key, so a string with no Arabic entry yet shows in
/// English rather than as a key — and every test that reads English keeps
/// reading English, because the tests run in the development localisation.
/// The Arabic table is `Localization/Resources/ar.lproj/Localizable.strings`;
/// `LocalizationTableTests` checks that it names only real keys' specifiers.
///
/// The app switches language through iOS's own per-app Language setting
/// (#4), so there is no language state here: `Bundle.module` resolves against
/// the languages iOS hands the app.
func localized(_ english: String) -> String {
    NSLocalizedString(english, bundle: .module, comment: "")
}
