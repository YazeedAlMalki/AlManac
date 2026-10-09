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

    // MARK: - The screenshot pass

    /// Every Modules row, by the Arabic its menu shows (AlmanacCore's
    /// `ar.lproj`), with a short ASCII name for the attachment. Each is opened
    /// from a fresh launch, so the order here is only the attachments' order.
    private static let modules: [(name: String, arabic: String)] = [
        ("context", "السياق"),
        ("hydration", "الترطيب"),
        ("fasting", "الصيام"),
        ("training", "التدريب"),
        ("nutrition", "التغذية"),
        ("supplements", "المكمّلات"),
        ("prayer", "الصلاة"),
        ("timeline", "الخط الزمني"),
        ("profile", "الملف الشخصي"),
        ("body-composition", "تكوين الجسم"),
        ("laboratory", "المختبر"),
        ("vitals", "المؤشرات الحيوية"),
        ("body-circumferences", "محيطات الجسم"),
        ("settings", "الإعدادات"),
    ]

    /// Walks every screen in Arabic and keeps a screenshot of each page of it in
    /// the result bundle (`Attach the result bundle` in CI; "Arabic
    /// screenshots" there is the same images as plain PNGs).
    ///
    /// The gates see only keys: a `String` the app builds and shows verbatim, a
    /// row that runs off the edge, or a chart that reads the wrong way are
    /// visible only on screen. So besides the pictures, each page's Latin-script
    /// text and any element outside the window are printed as `ARABIC-PASS`
    /// lines, which CI gathers at the end of the log. They are a report, not an
    /// assertion: brand names, units and stored English data are Latin by design
    /// (docs/features/arabic.md, "What stays English").
    ///
    /// Read-only, like the test above: it opens screens and scrolls them, and
    /// taps nothing that writes.
    ///
    /// CI runs it twice. In the suite it runs early, on an empty database, so it
    /// sees empty states. A second step runs it again after the whole suite,
    /// with `ALMANAC_ARABIC_PASS=populated`, on the database the English tests
    /// filled. In that run it also plants two weeks of readiness history —
    /// nights, morning vitals and the scores they earn, climbing — so Trends has
    /// a chart with a direction and Insights has trends to draw arrows for,
    /// and it prints where everything on the chart screens sits
    /// (`layout` lines), which is how the charts' direction is read from the
    /// log. Its names carry a `pop-` prefix.
    func testScreenshotEveryScreenInArabic() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            print("ARABIC-PASS\talert\t\(alert.label)")
            return false
        }
        app.launch()
        if populated {
            XCTAssertTrue(app.seedReadinessHistory(days: 14), "the readiness history seed was refused")
        }
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15), "no bottom bar")

        capture(app, "01-today")

        app.buttons["quick-log"].tap()
        settle(app)
        capture(app, "02-quick-log", pages: 1)
        app.terminate()
        app.launch()

        let trends = app.buttons["tab-trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 15))
        trends.tap()
        capture(app, "03-trends")
        let insights = app.buttons["insights-link"]
        if app.reveal(insights) {
            insights.tap()
            capture(app, "04-insights")
        } else {
            print("ARABIC-PASS\t\(tag("04-insights"))\tnot reachable from Trends")
        }

        openModulesRoot(app)
        capture(app, "05-modules")

        for (index, module) in Self.modules.enumerated() {
            let name = String(format: "%02d-%@", index + 10, module.name)
            openModulesRoot(app)
            let row = app.buttons[module.arabic]
            guard app.reveal(row) else {
                print("ARABIC-PASS\t\(tag(name))\tno Modules row reads \(module.arabic)")
                continue
            }
            row.tap()
            capture(app, name)
        }
    }

    /// The second run, on the database the suite left behind (see above).
    private var populated: Bool {
        ProcessInfo.processInfo.environment["ALMANAC_ARABIC_PASS"] == "populated"
    }

    private func tag(_ name: String) -> String { populated ? "pop-\(name)" : name }

    /// Screens with charts, whose element positions are printed in the
    /// populated run.
    private static let chartScreens: Set<String> = ["03-trends", "04-insights", "21-vitals"]

    /// The Modules tab at its root. A relaunch rather than the back button:
    /// it is the one route back that works from any screen, sheet or alert.
    private func openModulesRoot(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        let modules = app.buttons["tab-modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 15), "no bottom bar")
        modules.tap()
        _ = app.navigationBars["الأقسام"].waitForExistence(timeout: 10)
        settle(app)
    }

    /// Lets a screen's `.task` load before it is photographed.
    private func settle(_ app: XCUIApplication) {
        _ = app.waitUntil(timeout: 1.5) { false }
    }

    /// One screenshot per page, scrolling until the page stops changing, and the
    /// page's report lines.
    private func capture(_ app: XCUIApplication, _ screen: String, pages: Int = 6) {
        let name = tag(screen)
        let layout = populated && Self.chartScreens.contains(screen)
        settle(app)
        var seen = Set<String>()
        var last: [String] = []
        for page in 1...pages {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "ar-\(name)-\(page)"
            shot.lifetime = .keepAlways
            add(shot)

            let now = report(app, name, seen: &seen, layout: layout)
            if page > 1, now == last { break }
            last = now
            if page < pages {
                app.swipeUp()
                settle(app)
            }
        }
    }

    /// Prints what on this page is Latin script or outside the window, once per
    /// screen, and returns the page's text with positions so the caller can tell
    /// whether a swipe moved anything.
    private func report(_ app: XCUIApplication, _ name: String, seen: inout Set<String>,
                        layout: Bool = false) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        let window = root.frame
        var page: [String] = []
        var printed = seen
        defer { seen = printed }
        func line(_ kind: String, _ text: String) {
            let entry = "\(kind)\t\(text)"
            if printed.insert(entry).inserted { print("ARABIC-PASS\t\(name)\t\(entry)") }
        }
        func walk(_ node: XCUIElementSnapshot) {
            let text = [node.label, node.identifier, node.value as? String ?? "", node.placeholderValue ?? ""]
            let shown: String
            switch node.elementType {
            case .staticText, .button, .textField, .switch, .cell, .link, .segmentedControl:
                shown = node.label.isEmpty ? (node.value as? String ?? "") : node.label
            case .navigationBar:
                // A bar with no title is named after its SwiftUI host type
                // (`_TtGC7SwiftUI…`), which is not text anyone sees.
                shown = node.identifier.hasPrefix("_Tt") ? "" : node.identifier
            default:
                shown = ""
            }
            if layout, node.frame.width > 0, !(shown.isEmpty && node.label.isEmpty) {
                let kind = node.elementType == .image ? "image"
                    : node.elementType == .staticText ? "text" : "\(node.elementType.rawValue)"
                let said = shown.isEmpty ? node.label : shown
                line("layout", "\(kind) x=\(Int(node.frame.minX))…\(Int(node.frame.maxX)) y=\(Int(node.frame.minY)) \(said.prefix(80))")
            }
            if !shown.isEmpty {
                page.append("\(shown)@\(Int(node.frame.minY))")
                if shown.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil,
                   !text.contains(where: { $0.hasPrefix("tab-") || $0 == "quick-log" }) {
                    line("latin", shown)
                }
                if node.frame.width > 1, node.frame.height > 1,
                   node.frame.minX < window.minX - 1 || node.frame.maxX > window.maxX + 1 {
                    line("offscreen-x", "\(shown) \(Int(node.frame.minX))…\(Int(node.frame.maxX)) of \(Int(window.width))")
                }
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return page
    }
}
