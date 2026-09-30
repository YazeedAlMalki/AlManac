import SwiftUI
import AlmanacCore

/// The single owner of which tab is selected and how deep each tab's stack is.
///
/// **Why this is above the bar.** Each tab owns a local `NavigationStack`, so a
/// `NavigationLink` can only ever push within its own tab. Tapping a button
/// that names a feature has to be able to cross that line, and the state it
/// needs — the selection, and a stack per tab — has to live in exactly one
/// place. Two of the three tabs' `NavigationStack`s are created here for that
/// reason; Modules' already is, and is handed its path.
///
/// **This adapter holds no rules.** Every decision it makes is a `TabRouting`
/// plan, and those are pure functions in the core module with 16 tests over
/// them. What is left here is the part SwiftUI needs and a test cannot reach:
/// a `Binding` per tab, and the `@Published` that redraws the bar.
///
/// It is a `class` rather than a `struct` for one reason: `NavigationStack`'s
/// path is a `Binding`, and a `Binding` into a value type rebuilt on every
/// render would write into a copy that is immediately thrown away.
@MainActor
final class TabCoordinator: ObservableObject {
    /// The state itself. Held as one value rather than as separate `@Published`
    /// selection and paths, because a navigation request changes both
    /// together — publishing them separately would render the bar and the
    /// stacks against two different states for a frame.
    @Published private var state: TabRouting.Plan

    init(initial: AppTab = .today) {
        self.state = TabRouting.Plan(selection: initial, paths: [:])
    }

    // MARK: - What the bar binds to

    var selected: AppTab { state.selection }

    /// The bar's own selection, so tapping a tab is a `Binding` assignment and
    /// not a bespoke action.
    var selectionBinding: Binding<AppTab> {
        Binding(
            get: { [weak self] in self?.state.selection ?? .today },
            set: { [weak self] newValue in
                guard let self else { return }
                self.apply(TabRouting.plan(selection: self.state.selection,
                                           paths: self.state.paths,
                                           goingToTab: newValue))
            }
        )
    }

    /// One tab's stack, as `NavigationStack(path:)` wants it.
    ///
    /// The `set` deliberately goes through `TabRouting` rather than assigning
    /// the array. SwiftUI writes the whole stack back on every pop, and a
    /// straight assignment would let a stale write resurrect a route the
    /// coordinator had already decided about.
    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { [weak self] in self?.state.path(for: tab) ?? [] },
            set: { [weak self] newValue in
                guard let self else { return }
                self.replacePath(newValue, for: tab)
            }
        )
    }

    // MARK: - The one call a view makes

    /// Go to `route` from wherever you are, switching tab if it has to.
    ///
    /// This is the whole interface for "take me to that feature". A caller does
    /// not know which tab owns the route, does not check whether it is already
    /// showing, and does not have to decide what to do about a duplicate tap.
    func go(to route: AppRoute) {
        apply(TabRouting.plan(selection: state.selection, paths: state.paths, goingTo: route))
    }

    /// Go to a tab without pushing anything. What the bar does.
    func select(_ tab: AppTab) {
        apply(TabRouting.plan(selection: state.selection, paths: state.paths, goingToTab: tab))
    }

    /// Back out of whatever is pushed, staying on the tab.
    ///
    /// There is no explicit caller in the app today — the system's own back
    /// gesture drives the stack's `Binding` — but "go back" is part of what this
    /// module promises, and a promise with no way to keep it is not one.
    func back() {
        apply(TabRouting.plan(selection: state.selection, paths: state.paths, popping: true))
    }

    /// Clear the current tab's stack. Tapping the Modules tab while deep inside
    /// it should return you to the list, not leave you where you were.
    func popToRoot() {
        apply(TabRouting.plan(selection: state.selection, paths: state.paths, poppingToRoot: true))
    }

    /// Whether a route is the one currently on screen, for a caller that wants
    /// to mark it rather than push it.
    func isShowing(_ route: AppRoute) -> Bool {
        state.selection == route.tab && state.path(for: route.tab).last == route
    }

    // MARK: - Private

    private func apply(_ plan: TabRouting.Plan) {
        // Guarded rather than assigned unconditionally: a plan that changes
        // nothing (the no-op tap) should not publish, because a `@Published`
        // write re-renders every `NavigationStack` in the app.
        guard plan != state else { return }
        state = plan
    }

    private func replacePath(_ newValue: [AppRoute], for tab: AppTab) {
        let existing = state.path(for: tab)
        guard newValue != existing else { return }
        var paths = state.paths
        if newValue.isEmpty {
            paths.removeValue(forKey: tab)
        } else {
            paths[tab] = newValue
        }
        state = TabRouting.Plan(selection: state.selection, paths: paths)
    }
}

private struct TabCoordinatorKey: EnvironmentKey {
    static let defaultValue: TabCoordinator? = nil
}

extension EnvironmentValues {
    /// The coordinator, for any view that needs to send someone somewhere.
    ///
    /// **Optional**, and that is deliberate. A view that only ever navigates
    /// inside its own tab — which is most of them — should not have a
    /// coordinator in its environment at all, and a non-optional value would
    /// have to invent a placeholder coordinator for the preview and for every
    /// test that renders a view in isolation. A view that does need it reads it
    /// and says what to do when it is missing.
    var tabCoordinator: TabCoordinator? {
        get { self[TabCoordinatorKey.self] }
        set { self[TabCoordinatorKey.self] = newValue }
    }
}
