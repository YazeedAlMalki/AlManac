import XCTest

/// The Bristol and grade vocabularies, copied rather than imported.
///
/// The UI test target does not link `AlmanacCore`, and deriving the expected
/// strings from the enum under test would make these assertions tautological.
private enum BristolType: Int, CaseIterable {
    case type1 = 1, type2, type3, type4, type5, type6, type7

    var displayName: String {
        switch self {
        case .type1: return "Separate hard lumps"
        case .type2: return "Lumpy, sausage-shaped"
        case .type3: return "Sausage-shaped, smooth"
        case .type4: return "Smooth, soft sausage"
        case .type5: return "Soft blobs with clear edges"
        case .type6: return "Mushy pieces"
        case .type7: return "Entirely liquid"
        }
    }
}

/// Digestion quick entry, reached from Quick Log.
///
/// What these cover is the part the store tests cannot see: that the screen
/// renders, that the Bristol scale is a *scale* (seven named rows, not a wheel
/// of bare numbers), and that saving writes something a later read can find.
///
/// **The screen deliberately says nothing about whether an entry is concerning.**
/// BRD §6.3's advisory wording is held for clinician review, so there is no
/// escalation copy here to assert on, and asserting its absence is the one
/// assertion worth making.
final class DigestionQuickEntryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testQuickLogOffersDigestion() {
        openDigestion()
    }

    /// The Bristol scale as seven described rows on their own screen. A wheel of
    /// `1 2 3 4 5 6 7` would satisfy a count but not the BRD, which asks for the
    /// descriptions — the number only means something next to what it names.
    ///
    /// The names are repeated here rather than imported, because the UI test
    /// target does not link `AlmanacCore`. A copy that drifts from the enum is
    /// caught by `DigestionStoreTests`' distinct-names test, and the *display*
    /// names are what this test is asserting on, so it must not derive them from
    /// the thing under test.
    func testBristolScaleOffersSevenNamedTypes() {
        openBristolScale()
        for type in BristolType.allCases {
            let row = app.buttons["bristol-type-\(type.rawValue)"]
            XCTAssertTrue(row.exists, "Bristol type \(type.rawValue) is not offered")
            expectContainsText(row, "Type \(type.rawValue), \(type.displayName)")
        }
    }

    /// Choosing a type has to be visible on the row that was tapped, not only in
    /// the form behind it.
    func testChoosingABristolTypeMarksIt() {
        openBristolScale()
        let row = app.buttons["bristol-type-2"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["bristol-type-2"].isSelected, "the chosen type is not marked as chosen")
        XCTAssertFalse(app.buttons["bristol-type-4"].isSelected, "the previous choice is still marked")
    }

    /// The eight grade rows, each carrying the number, the scale and the name.
    func testUrinationOffersEightGradedRowsWithNames() {
        openGradeChart()
        for grade in 1...8 {
            let row = app.buttons["urine-grade-\(grade)"]
            XCTAssertTrue(row.exists, "colour grade \(grade) is not offered")
            expectContainsText(row, "Colour grade \(grade) of 8")
        }
    }

    /// Blood and its amount are offered together, and the amount control only
    /// appears once blood is said to be present — the BRD's escalation rule
    /// names "amount/type of blood", so a yes/no alone cannot record it.
    func testBloodAmountOnlyAsksAfterBloodIsPresent() {
        openDigestion()
        // A SwiftUI `Toggle` is exposed as a switch, not a button, and a
        // `Picker` in a Form row as a menu button — so this goes through
        // `element(_:)` rather than a query that names one control type.
        let blood = app.element("digestion-blood")
        XCTAssertTrue(app.reveal(blood), "the blood flag is not offered")
        XCTAssertFalse(app.element("digestion-blood-amount").exists,
                       "an amount is being asked for before blood was said to be present")

        // `tapSwitchControl`, not `tap`: SwiftUI exposes the whole labelled row
        // as one switch element whose activation point is the label, so tapping
        // the element's centre lands on the text and flips nothing.
        blood.tapSwitchControl()
        XCTAssertTrue(app.element("digestion-blood-amount").waitForExistence(timeout: 3),
                      "saying blood was seen did not ask how much")
    }

    /// "Not stated" has to be a real choice, and distinct from "no": a user who
    /// was not asked has recorded something different from a user who noticed
    /// nothing.
    func testGasOffersNotStatedAsItsOwnValue() {
        openDigestion()
        let gas = app.element("digestion-gas")
        XCTAssertTrue(app.reveal(gas), "the gas field is not offered")
        gas.tap()
        XCTAssertTrue(app.buttons["Not stated"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["No"].exists)
    }

    /// Logging a bowel movement puts it in today's list.
    ///
    /// Saving closes the sheet on purpose — Quick Log stays open so a second
    /// entry is one tap away — so the check reopens it rather than expecting the
    /// confirmation to still be on screen. The note is a marker no earlier test
    /// used, because the database persists between tests in a run and "the list
    /// is empty" is not a premise this can rely on.
    func testLoggingABowelMovementShowsItInTodaysList() {
        openDigestion()
        let type = 6
        openBristolScale()
        app.buttons["bristol-type-\(type)"].tap()
        // The choice has to be visible on the row that was tapped, or a tap
        // that missed would be indistinguishable from one that worked.
        XCTAssertTrue(app.buttons["bristol-type-\(type)"].isSelected)
        app.navigationBars["Bristol type"].buttons.firstMatch.tap()

        // …and it has to have reached the form, which is what gets saved.
        XCTAssertTrue(app.buttons["bristol-link"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bristol-link"].label.contains("Type \(type)"),
                      "the chosen type did not reach the form: \(app.buttons["bristol-link"].label)")

        let notes = app.textFields["Optional"]
        XCTAssertTrue(app.reveal(notes), "the notes field is unreachable")
        notes.tap()
        let marker = "uitest \(Int(Date().timeIntervalSince1970))"
        notes.typeText(marker)

        app.navigationBars["Log digestion"].buttons["Save"].tap()

        // Wait for the digest sheet to be *gone*, not for Quick Log to be
        // visible. Quick Log's own text is already in the accessibility tree
        // behind the sheet that is animating away, so a visibility wait passes
        // immediately and the next tap lands on a card a dismissing view is
        // still covering.
        XCTAssertTrue(app.waitUntil(timeout: 5) {
            !self.app.navigationBars["Log digestion"].exists
        }, "the digest sheet did not close after saving")

        openDigestion()
        // Today's list is the last section of a lazily-built form, so it has to
        // be scrolled to before its rows exist at all — polling `.exists`
        // without scrolling would just time out on a row that is not built.
        let found = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        for _ in 0..<8 where !found.exists {
            app.swipeUp()
        }
        XCTAssertTrue(found.exists, "the entry was not added to today's list; visible: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - Helpers

    private func expectContainsText(_ element: XCUIElement, _ fragment: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.label.contains(fragment),
                      "expected \(element.identifier) to mention \"\(fragment)\", got \"\(element.label)\"",
                      file: file, line: line)
    }

    private func openDigestion() {
        openQuickLog()
        let card = app.buttons["quicklog-destination-digestion"]
        XCTAssertTrue(app.reveal(card), "Quick Log does not offer digestion")
        // Tapped a quarter of the way down rather than at its centre. The
        // digestion card is the last item in the sheet, so `reveal` leaves it as
        // low as the sheet will go, which puts its bottom edge under the custom
        // bar the underlying screen still owns. A partially-occluded element
        // raises from `isHittable` with no hint that occlusion is the cause, so
        // the tap is aimed at the part that is demonstrably clear — the same
        // reasoning as `tapSwitchControl` in `UIScrollSupport.swift`.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.navigationBars["Log digestion"].waitForExistence(timeout: 5))
    }

    private func openBristolScale() {
        openDigestion()
        let link = app.buttons["bristol-link"]
        XCTAssertTrue(app.reveal(link), "the Bristol type is not offered on the form")
        link.tap()
        XCTAssertTrue(app.navigationBars["Bristol type"].waitForExistence(timeout: 5))
    }

    private func openGradeChart() {
        openDigestion()
        // The kind control is a segmented `Picker`, so its options are buttons.
        let kind = app.element("digestion-kind")
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        kind.tap()
        let urination = app.buttons["Urination"]
        XCTAssertTrue(urination.waitForExistence(timeout: 3))
        urination.tap()

        let link = app.buttons["grade-link"]
        XCTAssertTrue(app.reveal(link), "the colour grade is not offered on the form")
        link.tap()
        XCTAssertTrue(app.navigationBars["Colour grade"].waitForExistence(timeout: 5))
    }

    private func openQuickLog() {
        // Idempotent, because saving a digestion entry returns the user *to* the
        // Quick Log sheet by design — it stays open so a second entry is one tap
        // away. Tapping the `+` again from there is a second, different
        // interaction, and the element behind the sheet is still in the
        // accessibility tree, so it would silently do something else.
        if app.staticTexts["Quick log"].exists { return }
        let quickLog = app.buttons["quick-log"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 10))
        quickLog.tap()
        XCTAssertTrue(app.staticTexts["Quick log"].waitForExistence(timeout: 5))
    }
}
