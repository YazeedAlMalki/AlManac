import XCTest

/// The person's privacy screen and data rights (remediation P1-5): what the app
/// says about where data lives, the readable export, and "Erase all data".
///
/// **What this does not do:** it never confirms an erase. The simulator's database
/// is shared by the whole suite and never reset, so a real erase would delete what
/// every later test builds on. The erase itself (every file gone, a failure
/// reported) is `LocalDataEraserTests` in the core; the app-side steps (reminders,
/// preferences, quitting) are a device check (`docs/device-checklist.md`).
final class PrivacyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertFalse(app.staticTexts["Almanac could not open"].waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    private func openSettings() {
        app.openModulesTab()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(app.reveal(settings), "Settings is not offered")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testThePrivacyScreenSaysWhereDataLives() {
        openSettings()
        let link = app.buttons["settings-privacy"]
        XCTAssertTrue(app.reveal(link), "Settings offers no Privacy screen")
        link.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("no account, no server") },
                      "the Privacy screen does not say there is no account or server: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testEraseAsksFirstAndCancelChangesNothing() {
        openSettings()
        let erase = app.buttons["settings-erase-data"]
        XCTAssertTrue(app.reveal(erase), "Settings offers no Erase all data")
        erase.tap()
        XCTAssertTrue(app.staticTexts["Erase everything?"].waitForExistence(timeout: 5),
                      "Erase all data went ahead without asking")
        XCTAssertTrue(app.buttons["Erase everything and restart"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Erase everything?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Settings"].exists, "cancelling left Settings")
        XCTAssertEqual(app.state, .runningForeground, "the app quit after Cancel")
    }

    func testExportIsOfferedAndSaysItIsNotEncrypted() {
        openSettings()
        let export = app.buttons["settings-export-data"]
        XCTAssertTrue(app.reveal(export), "Settings offers no Export my data")
        export.tap()
        // Every table of a populated simulator database is read and written, so
        // allow more than a minute.
        XCTAssertTrue(app.buttons["settings-share-export"].waitForExistence(timeout: 180),
                      "no export was offered")
        XCTAssertTrue(app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("not encrypted") },
                      "the export screen does not say the file is not encrypted: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["settings-share-export"].waitForNonExistence(timeout: 10))
    }
}
