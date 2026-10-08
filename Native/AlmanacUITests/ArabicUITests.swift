import XCTest

/// The app in Arabic (#4): what a person sees when Almanac's language is set to
/// Arabic in iOS Settings, which is the only way it switches.
///
/// Two paths carry the text, and this drives both: the bottom bar's labels are
/// written by AlmanacCore (`AppTab.title`, through its own `ar.lproj` table),
/// and the Modules screen's title is a SwiftUI literal (the app's
/// `Localizable.xcstrings`). Then the direction: in Arabic the bar runs right
/// to left, so Today — the bar's leading tab — sits to the right of Modules.
///
/// Every other UI suite pins `-AppleLanguages (en)`, so this one launch is the
/// only Arabic one, and PR #2's ASCII day keys keep it from writing anything the
/// English suites would then misread.
final class ArabicUITests: XCTestCase {
    func testTheAppRunsInArabicRightToLeft() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()

        let today = app.buttons["tab-today"]
        let modules = app.buttons["tab-modules"]
        XCTAssertTrue(today.waitForExistence(timeout: 15), "no bottom bar")
        XCTAssertEqual(today.label, "اليوم", "the Today tab is not in Arabic")
        XCTAssertEqual(app.buttons["tab-trends"].label, "الاتجاهات", "the Trends tab is not in Arabic")
        XCTAssertEqual(modules.label, "الأقسام", "the Modules tab is not in Arabic")
        XCTAssertGreaterThan(today.frame.minX, modules.frame.minX,
                             "the bar is not right to left: Today should sit to the right of Modules")

        modules.tap()
        XCTAssertTrue(app.navigationBars["الأقسام"].waitForExistence(timeout: 10),
                      "the Modules screen's title is not in Arabic: "
                      + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
    }
}
