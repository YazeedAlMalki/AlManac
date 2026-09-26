import XCTest

/// Which way to scroll while looking for an element.
enum RevealDirection {
    case up
    case down
}

extension XCUIApplication {
    /// Scrolls until `element` is genuinely on screen, clear of the navigation
    /// bar above and the custom bottom bar below. Returns whether it got there.
    ///
    /// ## Why this exists rather than a swipe budget
    ///
    /// Two things make "swipe N times, then assert" the wrong shape here.
    ///
    /// **How far down a row sits depends on the data, not on the layout.** Both
    /// `Form`s in this app are lazily built, so their length varies with what is
    /// logged. `testSettingsCanToggleTheDigestionActivityRing` passed on a
    /// populated simulator and failed on a virgin one purely because the switch
    /// sat further down with no rows above it. Any budget tuned against one
    /// state is wrong for the other, and a bounded loop is the only thing that
    /// survives both.
    ///
    /// **`isHittable` raises instead of returning `false`.** On a `Form` row
    /// that has been found in the accessibility tree but never rendered, XCTest
    /// does not answer "not hittable" — it throws
    /// *"Failed to determine hittability … Activation point invalid and no
    /// suggested hit points based on element frame"*, failing the test rather
    /// than continuing the loop. So `isHittable` cannot be a loop condition
    /// here, and `for _ in 0..<8 where !element.isHittable` is a crash waiting
    /// for an empty database.
    ///
    /// Asking about the frame is also simply the more honest question: "can I
    /// tap this" depends on having a rendered frame inside the window, and that
    /// is exactly what is checked.
    @discardableResult
    func reveal(_ element: XCUIElement,
                maxSwipes: Int = 24,
                direction: RevealDirection = .up) -> Bool {
        for _ in 0..<maxSwipes {
            if isRevealed(element) { return true }
            direction == .up ? swipeUp() : swipeDown()
        }
        return isRevealed(element)
    }

    /// Polls `condition` until it holds or `timeout` elapses.
    ///
    /// `wait(for:timeout:)` on an `expectation` reports only "Exceeded timeout
    /// … with unfulfilled expectations", which throws away the one thing worth
    /// knowing when a UI assertion fails: what the state actually was. A caller
    /// using this can put that state in its own assertion message, and the
    /// message becomes the diagnosis instead of a restatement of the failure.
    ///
    /// Returns whether the condition holds at the end, so it is a predicate and
    /// not just a sleep — `waitUntil(timeout: 5) { a != b }` reads as what it
    /// is.
    @discardableResult
    func waitUntil(timeout: TimeInterval,
                   pollInterval: TimeInterval = 0.1,
                   _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    /// True when `element` is genuinely tappable: it has a rendered frame, it is
    /// not buried under the custom bottom bar, and it is not scrolled up under
    /// the navigation bar.
    ///
    /// The navigation-bar case needs care, because two situations are
    /// *geometrically identical* — a toolbar item in the bar, and a list row
    /// that has scrolled up behind it — and they need opposite answers. A
    /// toolbar item is always tappable, a hidden row is not, and their frames
    /// are indistinguishable. So this is decided by asking whether the
    /// navigation bar *owns* the element, not by where the frame happens to sit.
    ///
    /// Ownership is matched on identifier, then on label: SwiftUI gives
    /// `Button("Log a drink", systemImage: "plus")` a label but no identifier,
    /// so an identifier-only check would report the one button most likely to be
    /// needed — the `+` in the toolbar — as unreachable.
    func isRevealed(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }

        // The bottom bar is the app's own chrome, laid out in flow, so its top
        // edge comes from the "Today" tab rather than a hard-coded height.
        // `firstMatch` because a screen can legitimately show more than one
        // element labelled "Today" — the readiness card names the day — and an
        // ambiguous query raises instead of answering, which would fail the test
        // for a reason that has nothing to do with what it is testing.
        let todayTab = buttons["Today"].firstMatch
        let floor = todayTab.exists ? todayTab.frame.minY : frame.maxY
        guard frame.midY < floor - 8 else { return false }

        // Below every navigation bar, the element is plain content and is
        // tappable.
        let ceiling = navigationBars.allElementsBoundByIndex
            .map(\.frame.maxY)
            .max() ?? frame.minY
        if frame.midY > ceiling + 8 { return true }

        return isOwnedByNavigationBar(element)
    }

    /// Whether any navigation bar owns `element` — i.e. it is a toolbar item
    /// rather than list content that has scrolled up behind a bar.
    ///
    /// "Any", not "the first", and not "the one that contains it", because the
    /// two cases cannot be told apart by geometry: when the drink logger is
    /// presented as a sheet there are two bars on screen and they *overlap*
    /// vertically (the underlying screen's spans y 47–153, the sheet's spans
    /// y 63–117), so a single containment test happily matches the wrong one
    /// and then fails to find the "Log" button that bar does not own. Asking
    /// every bar that contains the element, and accepting if any of them owns
    /// it, is the rule that actually holds.
    ///
    /// Matched on identifier first, then on label. Both are needed:
    /// `Button("Log a drink", systemImage: "plus")` has a label and no
    /// identifier, so an identifier-only check would report the single button
    /// most likely to be wanted — the `+` in the toolbar — as unreachable.
    ///
    /// Only `buttons` and `menus` are searched rather than the whole subtree: a
    /// toolbar item in this app is a `Button` or a `Menu`, and a full
    /// `descendants` query per candidate is a hierarchy snapshot per call.
    private func isOwnedByNavigationBar(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        for bar in navigationBars.allElementsBoundByIndex {
            guard bar.frame.contains(frame) else { continue }
            for query in [bar.buttons, bar.menus] {
                if !element.identifier.isEmpty, query[element.identifier].exists { return true }
                if !element.label.isEmpty, query[element.label].exists { return true }
            }
        }
        return false
    }
}

extension XCUIElement {
    /// Taps the control at the trailing edge of a SwiftUI `Toggle` row.
    ///
    /// SwiftUI exposes the whole labeled row as a single switch element whose
    /// activation point is the label, not the switch — so tapping the element
    /// centre does nothing useful. Both call sites that toggle a setting hit
    /// near `dx: 0.93` for this reason.
    func tapSwitchControl() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
}

extension XCUIApplication {
    /// The element with `identifier`, whichever control type SwiftUI happened
    /// to expose it as.
    ///
    /// A `Picker` in a `Form` row is a menu button, a segmented `Picker` is a
    /// segmented control, and a `DatePicker` stays a date picker — but a test
    /// should not have to know which of those a given screen chose, and pinning
    /// it to one type makes the test fail on a presentation change that did not
    /// change the behaviour. `datePickers` has to be in this list: a
    /// `DatePicker` keeps its own element type and does *not* answer as a button
    /// with the same identifier, so omitting it silently loses the control.
    ///
    /// Order matters only in that `switches` is checked before `buttons`, since
    /// a SwiftUI `Toggle` row can also answer as a button.
    func element(_ identifier: String) -> XCUIElement {
        for query in [segmentedControls, switches, datePickers, pickers, buttons,
                      staticTexts, otherElements] {
            let match = query[identifier]
            if match.exists { return match }
        }
        // Nothing matched, but returning the button query means a failing
        // assertion reports the identifier rather than a nil crash.
        return buttons[identifier]
    }

    /// The first element whose identifier starts with `prefix`.
    func firstElement(identifierPrefix prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        for query in [buttons, cells, staticTexts, otherElements] {
            let match = query.matching(predicate).firstMatch
            if match.exists { return match }
        }
        return buttons.matching(predicate).firstMatch
    }

    /// The first static text whose *label* starts with `prefix`.
    ///
    /// Prefix rather than equality, because `AlmanacProblemNote` deliberately
    /// publishes one accessibility label made of its message and its action
    /// ("Could not read today's hydration log. Figures below may be out of
    /// date."). Matching the message exactly would make every assertion on a
    /// note depend on the wording of the advice beside it, so changing "try
    /// again" to something better would break a test about something else.
    func staticText(beginningWith prefix: String) -> XCUIElement {
        staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}

