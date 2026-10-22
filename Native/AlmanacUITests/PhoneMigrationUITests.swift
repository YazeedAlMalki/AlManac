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

        // Export: the backup is made, listed with its summary, and offered for
        // sharing (encrypted with a passphrase; see the sharing test below).
        openBackups()
        let create = app.buttons["Create backup"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Backup & restore offers no Create backup")
        create.tap()
        XCTAssertTrue(app.buttons["Share latest backup"].waitForExistence(timeout: 20),
                      "a backup was created but is not offered for sharing")
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

    /// The profile's email is optional and gates nothing: backups used to need one
    /// (owner, 2026-10-20), and the requirement was removed on 2026-10-22 after the
    /// security audit. With none, Create backup is enabled. A malformed address is
    /// still refused at Save, and a valid one is kept.
    func testBackupsDoNotNeedAnEmailAndAMalformedOneIsRefused() {
        openProfile()
        let original = email()
        saveEmail("")
        back(from: "Profile")

        openBackups()
        let create = app.buttons["Create backup"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Backup & restore offers no Create backup")
        XCTAssertTrue(create.isEnabled, "Create backup is disabled with no email on the profile")
        XCTAssertFalse(app.element("backup-needs-email").exists,
                       "Backup & restore still says a backup needs an email")
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

        openProfile()
        XCTAssertEqual(email(), "name@example.com", "a valid email was not kept")
        saveEmail(original)
        back(from: "Profile")
    }

    /// Sharing never hands out the plaintext container (audit finding S-02): the
    /// share sheet asks for a passphrase of at least 8 characters, typed twice, and
    /// only then offers an encrypted copy. What this cannot do: read the file back
    /// (a UI test cannot see the file), so the envelope is covered by
    /// `EncryptedBackupTests` in the core, and the real cipher by a device check.
    func testSharingABackupAsksForAPassphraseAndOffersAnEncryptedCopy() {
        openBackups()
        let create = app.buttons["Create backup"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Backup & restore offers no Create backup")
        create.tap()
        let share = app.buttons["Share latest backup"]
        XCTAssertTrue(share.waitForExistence(timeout: 20), "a backup was created but is not offered for sharing")
        share.tap()

        let encrypt = app.buttons["backup-encrypt"]
        XCTAssertTrue(encrypt.waitForExistence(timeout: 10), "sharing did not ask for a passphrase")
        XCTAssertFalse(encrypt.isEnabled, "Encrypt is enabled before a passphrase is typed")
        XCTAssertFalse(app.buttons["backup-share-encrypted"].exists, "a share link was offered before any passphrase")

        let first = app.secureTextFields["backup-passphrase"]
        let second = app.secureTextFields["backup-passphrase-repeat"]
        type("short\n", into: first)
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.keyboards.count == 0 }, "the keyboard did not close")
        XCTAssertFalse(encrypt.isEnabled, "Encrypt accepts a passphrase under 8 characters")

        type("a-long-enough-passphrase\n", into: first)
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.keyboards.count == 0 }, "the keyboard did not close")
        type("a-different-passphrase\n", into: second)
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.keyboards.count == 0 }, "the keyboard did not close")
        XCTAssertFalse(encrypt.isEnabled, "Encrypt accepts two passphrases that do not match")

        type("a-long-enough-passphrase\n", into: second)
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.keyboards.count == 0 }, "the keyboard did not close")
        XCTAssertTrue(encrypt.isEnabled, "Encrypt stays disabled with a good, repeated passphrase")
        encrypt.tap()

        // 600,000 rounds of key derivation take a moment, longer on a CI simulator.
        XCTAssertTrue(app.buttons["backup-share-encrypted"].waitForExistence(timeout: 90),
                      "no encrypted copy was offered after a passphrase was chosen")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["backup-share-encrypted"].waitForNonExistence(timeout: 10))
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
