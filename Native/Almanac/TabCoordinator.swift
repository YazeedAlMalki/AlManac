import SwiftUI
import AlmanacCore

/// The single owner of which tab is selected and how deep each tab's stack is.
///
/// **Why this is above the bar.** Each tab owns a local `NavigationStack`, so a
/// `NavigationLink` can only ever push within its own tab. Tapping a button
/// that names a feature has to be able to cross that line, and the state it
/// needs — the selection, and a stack per tab — has to live in exactly one
/// place. Journal's and Settings' `NavigationStack`s are handed their paths
/// from here for that reason.
///
/// **This adapter holds no rules.** Every decision it makes is a `TabRouting`
/// plan, and those are pure functions in the core module, pinned by
/// `TabRoutingTests`. What is left here is the part SwiftUI needs and a test
/// cannot reach: a `Binding` per tab, the `@Published` that redraws the bar,
/// and the root identity that pops what no path holds.
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

    /// Bumped each time a tab is tapped while it is showing; the app gives
    /// the tab's root this as its identity. Separate from `state` because it
    /// is not a navigation decision — it exists for the screens a plain
    /// `NavigationLink { … }` pushed, which no path holds and so clearing a
    /// path cannot pop.
    @Published private var rootResets: [AppTab: Int] = [:]

    init(initial: AppTab = .today) {
        self.state = TabRouting.Plan(selection: initial, paths: [:])
    }

    // MARK: - What the bar binds to

    var selected: AppTab { state.selection }

    /// A tap on the bar. Tapping the tab already showing pops it to its root;
    /// tapping another switches to it with its stack as it was left.
    func tap(_ tab: AppTab) {
        if tab == state.selection {
            rootResets[tab, default: 0] += 1
        }
        apply(TabRouting.plan(selection: state.selection, paths: state.paths, reselecting: tab))
    }

    /// The identity of a tab's root view. Changes only when the tab is tapped
    /// while showing.
    func rootIdentity(for tab: AppTab) -> Int { rootResets[tab, default: 0] }

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

    /// Clear the current tab's stack.
    func popToRoot() {
        apply(TabRouting.plan(selection: state.selection, paths: state.paths, poppingToRoot: true))
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
