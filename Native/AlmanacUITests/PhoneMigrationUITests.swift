import XCTest

/// BRD Appendix A, scenario A4 — phone migration — as far as a simulator can
/// drive it: a backup made from the app is restored by the app, the records go
/// back to what the backup held, and a change made after the backup is gone.
///
/// The marker is the Profile's free-text Sports field, set to a value unique to
/// this run, because the simulator's database is shared and never reset: a
/// drink or a meal could already be there from an earlier run, a fresh UUID
/// cannot. The field is put back as it was at the end.
///
/// What this cannot do, and where it is covered instead
/// (`docs/acceptance-checklist.md`, section 9):
/// - **A new install.** A UI test cannot uninstall its own app, so the backup
///   is restored over the same install. "Transactional, nothing partial" and
///   "corrupt or unsupported refused" are core tests (`BackupBundleTests`,
///   `BackupZipperTests`).
/// - **HealthKit asked again and reconciled.** Device only
///   (`docs/device-checklist.md`, check 3); de-duplication after a resync is
///   `RestoreHealthReconcileTests`.
final class PhoneMigrationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let sportsField = "Sports (comma-separated)"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launch()
    }

    func testABackupRestoresWhatItHeldAndDropsWhatCameAfter() {
        let run = UUID().uuidString.prefix(8)
        let before = "a4-before-\(run)"
        let after = "a4-after-\(run)"

        openProfile()
        let original = sports()
        setSports(before)
        // A backup needs a valid email on the profile (owner, 2026-10-20).
        openProfile()
        if email().isEmpty { saveEmail("a4@example.com") }
        back(from: "Profile")

        // Export: the backup is made, listed with its summary, and offered for
        // sharing as the zip a new phone would receive.
        openBackups()
        let create = app.buttons["Create backup"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Backup & restore offers no Create backup")
        create.tap()
        XCTAssertTrue(app.buttons["Share latest backup"].waitForExistence(timeout: 20),
                      "a backup was created but is not offered for sharing")
        shareEncrypted()
        let restore = app.buttons["Restore"].firstMatch  // newest first: the one just made
        XCTAssertTrue(restore.waitForExistence(timeout: 10),
                      "the new backup is not listed as restorable")
        back(from: "Backup & restore")
        back(from: "Settings")

        // A change the backup does not hold.
        openProfile()
        setSports(after)

        // Restore: a summary of what happens is shown before anything is replaced.
        openBackups()
        XCTAssertTrue(app.buttons["Restore"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Restore"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Replace your records?"].waitForExistence(timeout: 5),
                      "restore went ahead without saying what it replaces")
        let confirm = app.buttons["Restore and restart"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30),
                      "the app did not restart after the restore")

        // The restored install: the backup's records, not the later change.
        launch()
        openProfile()
        XCTAssertEqual(sports(), before,
                       "after the restore the profile should read as it did when the backup was made")

        setSports(original)
    }

    /// The owner's rule (2026-10-20): creating a backup needs a valid email on
    /// the profile. With none, Create backup is offered but disabled and says
    /// why; a malformed one is refused at Save; a valid one enables it.
    /// Restore is not gated, so a new phone can restore before it has a profile.
    func testCreatingABackupNeedsAValidEmail() {
        openProfile()
        let original = email()
        saveEmail("")
        back(from: "Profile")

        openBackups()
        let create = app.buttons["Create backup"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Backup & restore offers no Create backup")
        XCTAssertFalse(create.isEnabled, "Create backup is enabled with no email on the profile")
        XCTAssertTrue(app.element("backup-needs-email").waitForExistence(timeout: 5),
                      "Backup & restore does not say a backup needs an email")
        back(from: "Backup & restore")
        back(from: "Settings")

        openProfile()
        saveEmail("not-an-email")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "a malformed email was saved without a word")
        XCTAssertTrue(alert.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("valid email address") },
                      "the refusal does not say what is wrong: \(alert.staticTexts.allElementsBoundByIndex.map(\.label))")
        alert.buttons["OK"].tap()
        back(from: "Profile")

        openProfile()
        XCTAssertEqual(email(), "", "a malformed email was saved")
        saveEmail("name@example.com")
        back(from: "Profile")

        openBackups()
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        XCTAssertTrue(create.isEnabled, "Create backup stays disabled with a valid email on the profile")
        XCTAssertFalse(app.element("backup-needs-email").exists)
        back(from: "Backup & restore")
        back(from: "Settings")

        openProfile()
        saveEmail(original.isEmpty ? "name@example.com" : original)
        back(from: "Profile")
    }

    // MARK: - Helpers

    private func launch() {
        app.launch()
        XCTAssertFalse(app.staticTexts["Almanac could not open"].waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// Checked, so a lost tab tap is named as one (`openModulesTab`).
    private func openModules() {
        app.openModulesTab()
    }

    private func openProfile() {
        openModules()
        let row = app.buttons["Profile"]
        XCTAssertTrue(app.reveal(row), "no Profile row in Modules")
        XCTAssertTrue(app.waitUntilSettled(row), "the Profile row's frame kept moving")
        row.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10),
                      "Profile never opened after tapping its row; navigation bars: "
                      + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier)), "
                      + "keyboard shown: \(app.keyboards.count > 0)")
    }

    /// Sharing encrypts (owner, 2026-10-22): the passphrase is asked for
    /// twice, a mismatch is said and blocks Encrypt, and only an encrypted
    /// file is offered to the share sheet. The share sheet itself is the
    /// system's and is not driven.
    private func shareEncrypted() {
        app.buttons["Share latest backup"].tap()
        let passphrase = app.secureTextFields["backup-passphrase"]
        XCTAssertTrue(passphrase.waitForExistence(timeout: 5), "sharing did not ask for a passphrase")
        passphrase.tap()
        passphrase.typeText("a4-passphrase")
        let repeated = app.secureTextFields["backup-passphrase-repeat"]
        repeated.tap()
        repeated.typeText("a4-passphrasf")
        XCTAssertTrue(app.element("backup-passphrase-mismatch").waitForExistence(timeout: 5),
                      "two different passphrases were not called out")
        let encrypt = app.buttons["encrypt-backup"]
        XCTAssertFalse(encrypt.isEnabled, "Encrypt is offered for two different passphrases")
        repeated.typeText(XCUIKeyboardKey.delete.rawValue + "e\n")
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.keyboards.count == 0 }, "the keyboard did not close")
        XCTAssertTrue(app.reveal(encrypt), "the sheet offers no Encrypt")
        XCTAssertTrue(encrypt.isEnabled, "Encrypt stays disabled for matching passphrases")
        encrypt.tap()
        XCTAssertTrue(app.element("share-encrypted-backup").waitForExistence(timeout: 30),
                      "encrypting did not produce a file to share")
        app.navigationBars["Encrypt backup"].buttons["Done"].tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { !passphrase.exists }, "the passphrase sheet did not close")
    }

    private func openBackups() {
        openModules()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(app.reveal(settings), "Settings is not offered")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let link = app.buttons["Backup & restore"]
        XCTAssertTrue(app.reveal(link), "Settings does not offer Backup & restore")
        link.tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
    }

    private func sports() -> String {
        let field = app.textFields[sportsField]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Profile has no Sports field")
        let value = field.value as? String ?? ""
        return value == sportsField ? "" : value  // an empty field reads back its placeholder
    }

    private func email() -> String {
        let field = app.textFields["profile-email"]
        XCTAssertTrue(app.reveal(field), "Profile has no Email field")
        let value = field.value as? String ?? ""
        return value == "Email" ? "" : value  // an empty field reads back its placeholder
    }

    /// Types `text` into the Email field and taps Save, on an open Profile.
    /// Return closes the keyboard first, so Save and the back button are
    /// tapped on a screen that is not still moving.
    private func saveEmail(_ text: String) {
        let field = app.textFields["profile-email"]
        type(text + "\n", into: field)
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.keyboards.count == 0 }, "the keyboard did not close")
        app.buttons["Save"].tap()
    }

    /// Replaces a text field's contents with `text`.
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(app.reveal(field), "no such field")
        let current = (field.value as? String ?? "")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4) + text)
    }

    /// Replaces the field's text, saves, and reopens Profile to prove the write:
    /// the field reads back what was typed whether or not anything was saved.
    private func setSports(_ text: String) {
        let field = app.textFields[sportsField]
        XCTAssertTrue(app.reveal(field), "Profile has no Sports field")
        let current = sports()
        // The far end of the field puts the cursor after the text, so every
        // delete removes a character; spare deletes at the start do nothing.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4) + text)
        app.buttons["Save"].tap()
        back(from: "Profile")
        openProfile()
        XCTAssertEqual(sports(), text, "the profile did not save \(text)")
        back(from: "Profile")
    }

    /// The bar's back button, not its Save: the custom tab bar does not pop a
    /// stack, so every screen opened is left the way it was entered.
    private func back(from title: String) {
        let button = app.navigationBars[title].buttons
            .matching(NSPredicate(format: "label != %@", "Save")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no way back from \(title)")
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForNonExistence(timeout: 5), "still on \(title)")
    }
}
