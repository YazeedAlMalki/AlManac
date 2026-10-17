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
        // sharing as the zip a new phone would receive.
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

    // MARK: - Helpers

    private func launch() {
        app.launch()
        XCTAssertFalse(app.staticTexts["Almanac could not open"].waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    private func openModules() {
        let modules = app.buttons["tab-modules"].exists ? app.buttons["tab-modules"] : app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10), "no Modules tab")
        modules.tap()
    }

    private func openProfile() {
        openModules()
        let row = app.buttons["Profile"]
        XCTAssertTrue(app.reveal(row), "no Profile row in Modules")
        row.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10), "Profile never opened")
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
