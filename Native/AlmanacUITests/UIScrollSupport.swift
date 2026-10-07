import XCTest

/// Which way to scroll while looking for an element.
enum RevealDirection {
    case up
    case down
}

/// Plants hand-entered vitals on named logical days by relaunching the app with
/// `-AlmanacSeedVitals`, and the record of why that is the mechanism.
///
/// ## What it is for
///
/// `VitalsEntryEditor`'s "Measured at" picker is a compact `DatePicker`, so a
/// test cannot name a day by typing one: every hand-entered reading a UI test
/// creates lands on the current logical day. That was survivable while a day
/// could serve as its own baseline. It is not survivable now — a baseline
/// assembled only from the day being scored is reported as no baseline, which is
/// the point of the fix — so a test that wants a real multi-day baseline has to
/// be able to put a reading on a day that is not today.
///
/// ## Why a launch argument, and not the picker
///
/// The picker *was* measured, on the simulator this suite runs against. Tapping
/// `vitals-measured-at` expands a **graphical calendar**, not a set of wheels:
/// the day cells are buttons labelled `Thursday 1 October`, `Sunday 4 October`,
/// with `DatePicker.PreviousMonth` / `DatePicker.NextMonth` / `DatePicker.Show`
/// beside them. Tapping one does work — the field goes from `5 Oct 2026` to
/// `4 Oct 2026` — so the naive route is available and it was rejected on two
/// counts.
///
/// **It is locale-dependent, and the locale is not ours.** Those labels are
/// formatted dates: `Sunday 4 October` under en_GB, `Sunday, October 4` under
/// en_US. A helper would have to rebuild the label with its own formatter and
/// hope it matched.
///
/// **And it is version-dependent, which is the part that decided it.** `test-ios`
/// resolves the *newest* installed iOS runtime rather than pinning one — the
/// same discovery that makes a green run legible also means there is no fixed
/// UIKit to assert against. So a value string that works on a desk is not
/// guaranteed on a runner, and a green local run is evidence of nothing. The
/// seeding argument is locale-independent and runtime-independent: `rhr=52@-1`
/// means the same thing on every OS the suite has ever run on.
///
/// The cost is two lines of app code — an `if let` in `LaboratoryModel.open` —
/// and the logic itself lives in `VitalsSeedPlan` in `AlmanacCore`, so `swift
/// test` covers the guard, the grammar and the day arithmetic on every push and
/// on Linux. `VitalsSeedPlanTests` pins that a launch without the argument asks
/// for nothing.
///
/// **What protects a shipped build is reachability, not absence.** Checked
/// against a Release binary: `VitalsSeedPlan` and the string
/// `-AlmanacSeedVitals` are both present there, because AlmanacCore is compiled
/// whole into the app. The `#if DEBUG` around the one call site is what makes it
/// unreachable — a Release build has no path to `apply` — and the argument is the
/// gate that matters, since it is the one no ordinary launch can satisfy.
///
/// ## What it deliberately does not do
///
/// It does not *plant* what the test is meant to be driving. Today's readings are
/// still typed through the editor, because §6.7's manual fallback *is* what
/// checklist rows 7.10 and 7.11 claim to cover. Only the history the baseline
/// needs is planted.
///
/// It does *clear* today, and that is not the same thing. A spec entry with no
/// value — `rhr@0` — removes that metric's manual readings for today, because
/// `VitalsView` keeps today's readings off its log (`records(metric:from:to:)`'s
/// `to:` is exclusive) and the today card has no delete, so **nothing in the UI
/// can remove one**. Measured on this simulator: four runs of the two readiness
/// tests had left 16 readings on today, invisible to the delete helper the whole
/// time, and both tests still passed because `meanPerDay` averages within a day
/// before averaging across days. A test that means to assert about today's
/// readings has to name today.
extension XCUIApplication {
    /// Relaunches with `spec` planted, e.g.
    /// `seedVitals("rhr@0,hrv@0,rhr=52@-1,hrv=55@-1")` — which clears today's
    /// readings and plants yesterday's.
    ///
    /// Terminates rather than launching over the top: XCTest does not reliably
    /// deliver changed launch arguments to an already-running process, and a
    /// silently-unplanted launch would fail three screens later with a message
    /// about a score.
    ///
    /// Authoritative per `(metric, day)` rather than additive
    /// (`VitalsSeedPlan.apply`), so calling it twice with the same spec leaves
    /// the same state — which matters here because the simulator's database is
    /// shared across runs and never reset.
    @discardableResult
    func seedVitals(_ spec: String) -> Bool {
        terminate()
        launchArguments = launchArguments.filter { $0 != "-AlmanacSeedVitals" }
        launchArguments += ["-AlmanacSeedVitals", spec]
        launch()
        let failure = staticTexts["Almanac could not open"]
        return !failure.waitForExistence(timeout: 5)
    }

    /// Relaunches with Kitchen's fixture recipes planted (`KitchenSeedPlan`):
    /// `"recipes"`, `"recipes,peanuts"` or `"recipes,noallergens"`. Same shape
    /// and same reasons as `seedVitals`.
    @discardableResult
    func seedKitchen(_ spec: String) -> Bool {
        terminate()
        // The flag and the spec after it, so a second call does not leave the
        // first call's spec behind as a stray argument.
        while let index = launchArguments.firstIndex(of: "-AlmanacSeedKitchen") {
            launchArguments.removeSubrange(index..<min(index + 2, launchArguments.count))
        }
        launchArguments += ["-AlmanacSeedKitchen", spec]
        launch()
        let failure = staticTexts["Almanac could not open"]
        return !failure.waitForExistence(timeout: 5)
    }
}

extension XCUIApplication {
    /// Scrolls until `element` is genuinely on screen, clear of the navigation
    /// bar above and the custom bottom bar below. Returns whether it got there.
    ///
    /// ## Why this exists rather than a swipe budget
    ///
    /// Two things make "swipe N times, then assert" the wrong shape here.
    ///
    /// **A swipe is not always a scroll.** The loop also watches whether the
    /// content actually moved, and falls back to a press-then-drag after two
    /// consecutive swipes that changed nothing. This is not hypothetical: on
    /// the Timeline screen, which is a plain `List` with a short first section
    /// and a picker below the fold, `swipeDown()` left the hierarchy
    /// byte-identical across a dozen attempts while a single drag scrolled it
    /// in one gesture. A budget-only loop reports that as "not there", which is
    /// indistinguishable from the element genuinely being absent — and the fix
    /// for a real absence (a control that was never offered) would have been to
    /// add an identifier to something that already had one.
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
        /// Where the list's own content currently starts, so "did that move?" is
        /// answerable rather than guessed at.
        ///
        /// Scoped to the collection view's own descendants, and that scoping is
        /// load-bearing in both directions. A version that read
        /// `staticTexts` at the application level reported "the list never
        /// moved" for a list that scrolled perfectly well, because the largest
        /// `maxY` in that set belongs to the custom tab bar — chrome, pinned to
        /// the window, identical before and after any scroll. The stuck-signal
        /// that this exists to detect is therefore one the chrome manufactures,
        /// and the fallback never fires. `cells` is no better: this app's
        /// `List`s expose no cells at all, so that query is always empty and the
        /// check is silently off.
        ///
        /// Read from one snapshot, not element by element. The list is still
        /// settling after a swipe, and `allElementsBoundByIndex` resolves each
        /// index again when its frame is read: when the set has shrunk in
        /// between, XCTest fails the test ("No matches found for Element at
        /// index 12", CI 2026-10-07, in BodyCircumference and ProblemChannel)
        /// rather than answering. A snapshot is immutable, so it cannot lose an
        /// element halfway through being read.
        func anchor() -> CGFloat? {
            guard let root = try? collectionViews.firstMatch.snapshot() else { return nil }
            var top: CGFloat?
            func walk(_ node: XCUIElementSnapshot) {
                if node.elementType == .staticText, node.frame.height > 1 {
                    top = min(top ?? node.frame.minY, node.frame.minY)
                }
                node.children.forEach(walk)
            }
            walk(root)
            return top
        }

        var lastSeen = anchor()
        var stuckCount = 0
        for _ in 0..<maxSwipes {
            if isRevealed(element) { return true }
            direction == .up ? swipeUp() : swipeDown()
            let now = anchor()
            if let now, let lastSeen, abs(now - lastSeen) < 0.5 {
                stuckCount += 1
            } else {
                stuckCount = 0
            }
            lastSeen = now
            // A plain swipe is a fast flick, and a flick is not always a scroll:
            // on some lists it is absorbed as a selection or lands on a row that
            // does not consume it, leaving the hierarchy byte-identical while
            // the loop happily burns its whole budget. A press-then-drag moves
            // the content under a held touch, which is what actually scrolls.
            // Two consecutive no-move swipes is the trigger, not the first, so a
            // list that is genuinely at its end does not pay for a drag.
            if stuckCount >= 2, collectionViews.firstMatch.exists {
                drag(collectionViews.firstMatch, direction: direction)
                stuckCount = 0
            }
        }
        return isRevealed(element)
    }

    /// A press-then-drag across the middle of `list`, which scrolls it a long
    /// way in one gesture. Falls back to a swipe if the drag does not land.
    private func drag(_ list: XCUIElement, direction: RevealDirection) {
        let start = direction == .up ? CGVector(dx: 0.5, dy: 0.75) : CGVector(dx: 0.5, dy: 0.25)
        let end = direction == .up ? CGVector(dx: 0.5, dy: 0.2) : CGVector(dx: 0.5, dy: 0.75)
        list.coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: end))
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

    /// True once `element` is revealed *and* its frame has stopped settling.
    ///
    /// `reveal` proves an element is on screen with a real frame, but on a lazy
    /// `List` that frame can go stale in the moment between the check and the
    /// tap: a row parked just above the custom bottom bar is re-laid-out as the
    /// list winds down, and a tap synthesized from the stale frame lands on the
    /// row next door. On the Training screen "Start workout" and "Templates"
    /// are adjacent rows, so that stale tap opens the template editor instead
    /// of the program picker — which the test then reports as a missing
    /// feature. Waiting for the position to stop changing closes the window:
    /// every poll re-reads the frame, and the tap that follows targets the
    /// *actual* rendered row.
    ///
    /// Returns true when the element stays put for the whole wait, i.e. the
    /// frame read on the final poll is still the one read at the start.
    @discardableResult
    func waitUntilSettled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        guard isRevealed(element) else { return false }
        let first = element.frame
        return waitUntil(timeout: timeout) {
            guard isRevealed(element) else { return false }
            let now = element.frame
            return now.midY == first.midY
                && now.minX == first.minX
                && now.width == first.width
        }
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
    ///
    /// `menus` and `pickers` come before `buttons` because a SwiftUI `.menu`
    /// `Picker` — the session's equipment-variant selector — answers as a menu
    /// or picker rather than as a button, and a test that means "find the
    /// picker" must not be told the identifier matches nothing.
    func firstElement(identifierPrefix prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        for query in [menus, pickers, buttons, cells, staticTexts, otherElements] {
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

