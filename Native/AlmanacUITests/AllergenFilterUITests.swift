import XCTest

/// The allergen gate, driven end to end through the two screens it spans.
///
/// ## Why this has to be a UI test
///
/// `AllergenFilteredSearchTests` proves the filter removes the right rows and
/// `FoodAllergenTests` proves the verdicts are right. Neither can catch the
/// failure this file exists for: that the **profile screen never records an
/// allergen at all**, so the gate is inert for every real user while every test
/// over it passes. A hard filter that is never switched on is not a feature, and
/// it fails silently — no error, just a search that ignores a recorded peanut
/// allergy.
///
/// So this drives the real controls: toggle an allergen in the profile, save,
/// search for a food that names it, and require that the screen says what it did.
/// Assertions are on the *shape* of the response rather than on a specific food,
/// so updating the reference bundle does not break them for an unrelated reason.
final class AllergenFilterUITests: XCTestCase {
    /// A food the filter is certain to catch, whatever the catalogue holds.
    ///
    /// "peanut" rather than a named dish: catalogue row names change between
    /// releases, and a test pinned to "Peanut Butter, Smooth" fails on a bundle
    /// update for no reason connected to this code. The filter matches on the
    /// name, and "peanut" is in the word list.
    private static let allergenQuery = "peanut"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let failure = app.staticTexts["Almanac could not open"]
        XCTAssertFalse(failure.waitForExistence(timeout: 5),
                       "the app refused to open: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    // MARK: - The profile control exists

    /// All fourteen allergens are offered, each with its guidance.
    ///
    /// Fourteen because that is what the labelling laws publish and what
    /// `food_allergen` seeds. A picker showing fewer would be a picker that
    /// cannot record what somebody actually has — and the filter would then be
    /// silent about it, which is the failure this whole file is about.
    func testTheProfileOffersEveryPublishedAllergen() throws {
        try openProfile()

        // Scrolled to the section first: a `Form` is lazily built, so an allergy
        // row that has never been scrolled to is not in the tree at all and
        // `.exists` is false. Asserting before scrolling measures the form's
        // laziness, not what it offers.
        try openAllergySection()

        // By identifier, not by title text: the toggle's own label is its title
        // *and* its guidance sentence joined together, so a title query matches
        // nothing. The identifiers are derived from the raw values, which are the
        // column's values — so a rename of a case changes the id and this test
        // fails loudly rather than silently checking a different allergen.
        // Sweep the section once and collect every identifier that appears,
        // rather than checking fourteen rows one at a time.
        //
        // `Form` is lazy, so a row the list has not built has no element at all:
        // measured on iPhone 16e, with the section header on screen six of the
        // fourteen switches exist and the other eight identifiers come back empty.
        // Checking one at a time cannot work, because `reveal` only ever scrolls in
        // one direction — a row that has gone off the top is gone for the rest of
        // the test. Accumulating over one downward pass is the only shape that can
        // see all fourteen, and it also happens to be the assertion that matters:
        // the *set*, not any one control.
        var seen: Set<String> = []
        var stagnant = 0
        for _ in 0..<24 {
            let now = Set(app.switches.allElementsBoundByIndex
                .map(\.identifier)
                .filter { $0.hasPrefix("allergen-") })
            if now.subtracting(seen).isEmpty {
                stagnant += 1
                // Three swipes with nothing new: the section is exhausted. One is
                // not enough — a single swipe can land without building a row.
                if stagnant >= 3 { break }
            } else {
                stagnant = 0
                seen.formUnion(now)
            }
            app.swipeUp()
        }

        let expected: Set<String> = ["peanuts", "nuts", "milk", "eggs", "fish",
                                     "crustaceans", "molluscs", "soy", "gluten",
                                     "celery", "mustard", "sesame", "sulphites", "lupin"]
        XCTAssertEqual(seen, Set(expected.map { "allergen-\($0)" }),
                       "the profile does not offer exactly the published fourteen. "
                       + "Missing: \(expected.subtracting(seen.map { $0.replacingOccurrences(of: "allergen-", with: "") }))")
        // And the titles are the labelling laws' wording, which is the point of
        // seeding them as data. "Tree nuts" is checked separately because "Nuts"
        // would be the reading that hides a peanut allergy from somebody who has
        // one — peanuts and tree nuts are separate allergens in the vocabulary and
        // a merge would be a safety defect.
        XCTAssertTrue(app.staticTexts["Tree nuts"].exists, "tree nuts are not titled as such")
    }

    /// A toggled allergen survives the save.
    ///
    /// The write is a diffing `setAllergens`, so a row that was not touched keeps
    /// its `createdAt`. A test that only checked the toggle *stayed on* would pass
    /// against a screen that renders what it loaded and never writes anything, so
    /// this reopens the profile: what is on screen the second time is what the
    /// database holds.
    func testAToggledAllergenIsStillThereAfterReopening() throws {
        try openProfile()

        let peanuts = try openAllergySection()
        set(peanuts, to: true)
        app.buttons["Save"].tap()

        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        try openProfile()

        let persisted = try openAllergySection()
        XCTAssertTrue(isOn(persisted),
                      "the allergy was not written: the toggle reads \(persisted.value ?? "nil")")

        // Put it back. Without this the test leaves a peanut allergy behind, and
        // the next test's "somebody with none recorded" premise is no longer the
        // state of the simulator.
        set(persisted, to: false)
        app.buttons["Save"].tap()
    }

    /// Nothing about allergies is said to somebody who has recorded none.
    ///
    /// The other half of the gate's honesty. A note shown over an empty set is
    /// noise that trains people to ignore the note — and the note is the only
    /// thing standing between "the filter ran" and "this food is safe for you".
    func testSearchSaysNothingAboutAllergiesToSomebodyWithNone() throws {
        try openFoodSearch()

        XCTAssertFalse(app.staticTexts["Hidden by your allergens"].exists,
                       "the withheld section is showing with nothing withheld")
        let spoken = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        XCTAssertFalse(spoken.contains("ingredient lists"),
                       "the allergen disclaimer is showing for an unfiltered search: \(spoken)")
    }

    // MARK: - The gate, once an allergen is recorded

    /// With peanuts recorded, a search for "peanut" must say it checked names and
    /// must not claim safety.
    ///
    /// The disclaimer is the assertion that matters, and it is required to be
    /// present whether or not anything was withheld — a screen that goes quiet when
    /// the filter finds nothing is exactly the screen that reads as a clean bill of
    /// health. If the seeded catalogue holds nothing matching, the withheld section
    /// is legitimately absent and only the disclaimer is checked.
    func testRecordingPeanutsMakesTheSearchSayWhatItChecked() throws {
        try openProfile()
        let peanuts = try openAllergySection()
        set(peanuts, to: true)
        app.buttons["Save"].tap()

        try openFoodSearch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.tap()
        field.typeText(Self.allergenQuery)

        XCTAssertTrue(app.waitUntil(timeout: 15) {
            app.staticTexts.allElementsBoundByIndex
                .contains { $0.label.contains("no ingredient lists") }
        }, "the allergen disclaimer never appeared: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        // And anything withheld is listed by name with its reason, never dropped.
        if app.staticTexts["Hidden by your allergens"].exists {
            let list = app.staticTexts.allElementsBoundByIndex.map(\.label)
            XCTAssertTrue(list.contains { $0.hasPrefix("Names ") },
                          "withheld foods were listed without saying why: \(list)")
        }
    }

    // MARK: - Helpers

    /// A toggle's state, without depending on how XCTest spells it.
    ///
    /// `"0"`/`"1"` on iOS. Anything unrecognised counts as *off*, which is the safe
    /// direction: the test taps and finds out rather than assuming it is set.
    private func isOn(_ toggle: XCUIElement) -> Bool {
        guard let raw = toggle.value as? String else { return false }
        return raw == "1" || raw.lowercased() == "true"
    }

    /// Flips a toggle if it is not already in the wanted state.
    ///
    /// ## Why this taps a coordinate and not the element
    ///
    /// Measured: `toggle.tap()` on a `Toggle` inside a `Form` lands on the centre
    /// of the *row*, which is the label — and a Form row's label does not toggle
    /// it. The tap registers, the value stays `"0"`, and the test's own report is
    /// "the allergy was not written", which points at the store rather than at the
    /// tap. This is platform behaviour, not a defect here: Settings.app does the
    /// same, and a person expecting otherwise would be wrong about every iOS
    /// settings screen they have used.
    ///
    /// `0.9` is inside the switch on the trailing edge of a Form row at every
    /// Dynamic Type size that keeps the row one line high. It is a fixed fraction
    /// rather than a computed offset because the switch's own frame is not
    /// addressable — the element XCUITest resolves is the whole row.
    private func set(_ toggle: XCUIElement, to wanted: Bool) {
        guard isOn(toggle) != wanted else { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { isOn(toggle) == wanted },
                      "the toggle did not flip: reads \(toggle.value.map { "\($0)" } ?? "nil")")
    }

    /// Scrolls the profile to the allergy section and returns the Peanuts toggle.
    ///
    /// ## Why this is not `reveal()`
    ///
    /// A `Form` is lazily built, so a row that has not been scrolled to *is not in
    /// the accessibility tree at all* — `.exists` is false and `reveal`'s loop sees
    /// an element it can never satisfy. The precondition is "the section header is
    /// on screen", which is a real, checkable thing, so this waits for the header
    /// and then queries. Measured on iPhone 16e: the section header is the 9th
    /// static text and the Peanuts toggle the 12th descendant carrying an
    /// `allergen-` identifier, with 14 switches in the tree once it is built.
    private func openAllergySection() throws -> XCUIElement {
        let header = app.staticTexts["Food allergies"]
        for _ in 0..<14 where !header.exists { app.swipeUp() }
        XCTAssertTrue(header.exists, "the profile has no Food allergies section")

        let toggle = app.switches.matching(identifier: "allergen-peanuts").firstMatch
        XCTAssertTrue(app.reveal(toggle, maxSwipes: 6),
                      "no allergen-peanuts toggle: \(app.switches.allElementsBoundByIndex.map(\.identifier))")
        return toggle
    }

    private func openProfile() throws {
        let modules = app.buttons["tab-modules"].exists ? app.buttons["tab-modules"] : app.buttons["Modules"]
        XCTAssertTrue(modules.waitForExistence(timeout: 10), "no Modules tab")
        modules.tap()

        let row = app.buttons["Profile"]
        for _ in 0..<12 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Profile row in Modules")
        row.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10),
                      "Profile never opened: \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
    }

    /// Quick Log → Food → Select food.
    ///
    /// The app's own navigation, deliberately: a test that reached the search some
    /// other way would not catch a regression where the search has become
    /// unreachable, which is the same class of bug as the one this file is about.
    private func openFoodSearch() throws {
        let quickLog = app.buttons["Quick log"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 10),
                      "no Quick log tab: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        quickLog.tap()

        // By identifier. The card's accessibility label is "Food, Search the
        // catalogue and record a meal." — title and detail combined — so a query
        // on "Food" matches no button at all, which is how the first version of
        // this test passed a missing control.
        let food = app.buttons["quicklog-destination-food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5),
                      "no Food card in Quick log: \(app.buttons.allElementsBoundByIndex.map(\.identifier))")
        food.tap()

        let select = app.buttons["Select food"]
        XCTAssertTrue(select.waitForExistence(timeout: 10),
                      "no Select food control: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        select.tap()

        XCTAssertTrue(app.navigationBars["Food search"].waitForExistence(timeout: 10),
                      "the food search never opened")
    }
}
