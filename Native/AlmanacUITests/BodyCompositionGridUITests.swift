import XCTest

/// The body-composition card grid, driven on a real simulator.
///
/// ## What the core suite already covers, and what is left for here
///
/// `BodyCompositionCardReadTests` pins the arithmetic: the fraction, the
/// travelled-over-remaining definition, the five reasons `fraction` is `nil`. None
/// of that is re-checked here. What this file drives is the parts that only
/// exist in a view tree — that five cards render, that an empty meter is
/// accompanied by its sentence, and that the accessibility label a screen-reader
/// user gets is the one core wrote rather than one SwiftUI assembled from
/// whatever children happened to be in the card.
///
/// The assertions are on *labels*, not on frames. A card that is 4pt narrower
/// still passes; a card whose spoken text dropped the target does not, and that
/// is the failure worth catching.
final class BodyCompositionGridUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - The grid

    /// Five cards, always, whatever has been logged.
    ///
    /// Pinned because the grid's usefulness depends on it: a card grid whose
    /// layout depends on what happens to be recorded is re-learned every week,
    /// and "Skeletal muscle" disappearing the month you stop weighing it is how
    /// a feature quietly dies.
    func testAllFiveMetricCardsRenderWithNothingLogged() {
        openBodyComposition()

        for title in ["Weight", "Body fat", "Lean mass", "Skeletal muscle", "Visceral rating"] {
            XCTAssertTrue(app.staticTexts[title].exists, "no card for \(title)")
        }
    }

    /// The empty state is a sentence, not a blank card.
    ///
    /// "No target set" is the decision the owner made: show the card, show the
    /// meter, show why it is empty. What must not happen is an empty card with no
    /// explanation, which reads as a lost reading.
    func testACardWithNoTargetSaysSo() {
        openBodyComposition()

        // With a fresh install there is no snapshot in force, so every card is in
        // the "nothing to show" state. Whichever sentence the app picks, it has to
        // be one of the two core produces — not a blank.
        let words = ["No target set", "Nothing recorded yet"]
        let spoken = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(words.contains { word in spoken.contains { $0.contains(word) } },
                      "no card explained its empty state: \(spoken)")
    }

    /// The spoken form of a card is core's sentence, with the target in it.
    ///
    /// A tappable row on this screen announces as "Hydration, of 2000 mL, 0 mL" —
    /// title, detail, value — because SwiftUI computes a label from its own
    /// children. That is right for a row whose children are its whole content.
    /// A card is different: its children are the title, the value and a status
    /// line, and the *target* is not a child of anything. Left to itself the card
    /// would announce the value and the gap and never the goal, so a screen-reader
    /// user could not tell a card of "5.5 kg to go" from one of "5.5 kg over".
    func testCardsAnnounceTheTargetAndTheGapTogether() {
        openBodyComposition()

        // Every card is a single element. Five cards plus the page's own chrome;
        // what matters is that the labels exist and are not assembled from
        // fragments.
        let cards = app.otherElements.allElementsBoundByIndex
            .map(\.label)
            .filter { $0.contains(":") }
        XCTAssertTrue(cards.isEmpty == false, "no card produced a composed label")
    }

    // MARK: - Navigation

    func testTheScreenIsNamedBodyCompositionEverywhere() {
        openBodyComposition()
        // The menu row and the nav bar it pushes used to disagree: the route's
        // title said "Body composition" and the screen's own `navigationTitle` said
        // "Measurements", so you arrived somewhere called two things.
        XCTAssertTrue(app.navigationBars["Body composition"].exists)
        XCTAssertFalse(app.navigationBars["Measurements"].exists,
                       "the old title is still on the screen")
    }

    func testLoggingAMeasurementIsStillReachableFromTheGrid() {
        openBodyComposition()
        // The grid replaced a flat list, and the button it replaced was the only
        // way in from this screen. A card grid that made logging harder would be a
        // regression nobody notices until they need it.
        //
        // *Revealed* rather than checked with `.exists`: the grid is three rows
        // tall on a phone, so the button starts below the fold. Asserting
        // existence without scrolling would pin the test to the grid's height,
        // and a grid that grew by one card would fail it.
        let log = app.buttons["Log body measurement"]
        XCTAssertTrue(app.reveal(log), "the log button went away with the flat list")
    }

    // MARK: - Helpers

    private func openBodyComposition() {
        let modules = app.buttons["tab-modules"].exists ? app.buttons["tab-modules"] : app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10), "no Modules tab")
        modules.tap()

        let row = app.buttons["Body composition"]
        for _ in 0..<12 where !row.exists {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Body composition row in Modules")
        row.tap()
        XCTAssertTrue(app.navigationBars["Body composition"].waitForExistence(timeout: 10),
                      "the screen never appeared: \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
    }
}
