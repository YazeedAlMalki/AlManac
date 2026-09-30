import Foundation

/// The three bottom-bar destinations. Public and `CaseIterable` because the bar
/// itself is generated from this list — a fourth tab is a case here plus a
/// column in the bar, not an edit in two files.
public enum AppTab: String, Sendable, Hashable, CaseIterable, Identifiable {
    case today
    case trends
    case modules

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .trends: return "Trends"
        case .modules: return "Modules"
        }
    }

    public var icon: String {
        switch self {
        case .today: return AlmanacIcon.today
        case .trends: return AlmanacIcon.trends
        case .modules: return AlmanacIcon.modules
        }
    }

    /// The bar is laid out around the quick-log action: Today and Trends share
    /// one half, Modules takes the other. Expressed as a property so adding a
    /// tab is a value in the bar's arithmetic rather than a new `case` in a
    /// layout function — and so a fourth tab cannot be added somewhere the
    /// layout does not expect it.
    public enum BarGroup: Sendable, Hashable {
        case leadingHalf
        case trailingHalf
    }

    public var barGroup: BarGroup {
        switch self {
        case .today, .trends: return .leadingHalf
        case .modules: return .trailingHalf
        }
    }
}

/// Where a route lives in the Modules menu.
///
/// Data, not a hand-written `Section` per group, because the menu is generated
/// from `AppRoute.allCases` and a hand-written section cannot be checked against
/// that list. `order` is what makes the grouped list read the way it does —
/// `.allCases` is alphabetical, which is not an order anyone would choose.
public struct AppRouteSection: Sendable, Hashable, Identifiable {
    public let title: String
    public let order: Int

    public var id: Int { order }

    public init(title: String, order: Int) {
        self.title = title
        self.order = order
    }

    public static let track = AppRouteSection(title: "Track", order: 0)
    public static let dailyContext = AppRouteSection(title: "Daily context", order: 1)
    public static let records = AppRouteSection(title: "Records", order: 2)
    public static let app = AppRouteSection(title: "App", order: 3)
    /// Not shown. The roots and the pushed-only routes live here so that
    /// `section` is total without inventing a group for them.
    public static let hidden = AppRouteSection(title: "", order: 99)

}

/// One group of the Modules menu: a section and the rows under it.
///
/// A named type rather than a tuple, because `ForEach` needs `Identifiable` and
/// a tuple cannot conform to anything.
public struct AppRouteGroup: Sendable, Hashable, Identifiable {
    public let section: AppRouteSection
    public let routes: [AppRoute]

    public var id: Int { section.order }

    public init(section: AppRouteSection, routes: [AppRoute]) {
        self.section = section
        self.routes = routes
    }
}

/// One place a person can be sent to, from anywhere.
///
/// **This one enum is both the menu and the router.** `ModulesView` builds its
/// list from `allCases`, and every cross-tab link names a case. That is what
/// stops the two drifting: a screen in the menu that no route names is
/// unreachable from anywhere else, and a route no menu row shows is unreachable
/// from the menu, and both mistakes are invisible until someone taps the wrong
/// thing.
///
/// Every case carries its own `tab`, so a caller writes `go(to: .bodyComposition)`
/// and does not know or care that Body composition lives on Modules.
public enum AppRoute: Hashable, Sendable, CaseIterable, Identifiable {
    /// The screen a tab shows when nothing is pushed onto it. Present as a
    /// value rather than implied by an empty path, because an empty path and a
    /// path of one root are different things to a `NavigationStack` and a test
    /// asserting "you are back at the top" should say which it means.
    case todayRoot
    case trendsRoot
    case trendsDetail

    case training
    case hydration
    case nutrition
    case fasting
    case supplements
    case context
    case prayer
    case bodyCircumference
    case laboratory
    case laboratoryImportHistory
    case timeline
    case bodyComposition
    case profile
    case settings

    public var id: String { String(describing: self) }

    /// The tab that owns this route.
    ///
    /// Declared per case rather than in a lookup table so that the compiler
    /// enforces it: a new case with no `tab` is a non-exhaustive `switch` here,
    /// which is a build failure, not a route that resolves to nothing at
    /// runtime.
    public var tab: AppTab {
        switch self {
        case .todayRoot: return .today
        case .trendsRoot, .trendsDetail: return .trends
        case .training, .hydration, .nutrition, .fasting, .supplements, .context,
             .prayer, .bodyCircumference, .laboratory, .laboratoryImportHistory,
             .timeline, .bodyComposition, .profile, .settings:
            return .modules
        }
    }

    /// What the menu row says.
    public var title: String {
        switch self {
        case .todayRoot: return "Today"
        case .trendsRoot: return "Trends"
        case .trendsDetail: return "A trend"
        case .training: return "Training"
        case .hydration: return "Hydration"
        case .nutrition: return "Nutrition"
        case .fasting: return "Fasting"
        case .supplements: return "Supplements"
        case .context: return "Context"
        case .prayer: return "Prayer"
        case .bodyCircumference: return "Body circumferences"
        case .laboratory: return "Laboratory"
        case .laboratoryImportHistory: return "Import history"
        case .timeline: return "Timeline"
        case .bodyComposition: return "Body composition"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .todayRoot: return AlmanacIcon.today
        case .trendsRoot, .trendsDetail: return AlmanacIcon.trends
        case .training: return AlmanacIcon.training
        case .hydration: return AlmanacIcon.hydration
        case .nutrition: return AlmanacIcon.nutrition
        case .fasting: return AlmanacIcon.fasting
        case .supplements: return AlmanacIcon.supplement
        case .context: return AlmanacIcon.context
        case .prayer: return AlmanacIcon.prayer
        case .bodyCircumference: return AlmanacIcon.body
        case .laboratory: return AlmanacIcon.laboratory
        case .laboratoryImportHistory: return AlmanacIcon.importHistory
        case .timeline: return AlmanacIcon.timeline
        case .bodyComposition: return AlmanacIcon.bodyComposition
        case .profile: return AlmanacIcon.profile
        case .settings: return AlmanacIcon.settings
        }
    }

    /// Which group of the Modules menu this appears under.
    ///
    /// Only meaningful for routes that are *shown*; the three roots and
    /// `laboratoryImportHistory` are reached by pushing, not by a menu row of
    /// their own. They still name a section so the enum stays total and
    /// `AppRouteSection` never has to be optional — a `nil` here would be a
    /// place where the menu and the router could disagree.
    public var section: AppRouteSection {
        switch self {
        case .training, .hydration, .nutrition, .fasting, .supplements, .context:
            return .track
        case .prayer, .fasting:
            return .dailyContext
        case .bodyCircumference, .laboratory, .laboratoryImportHistory, .timeline,
             .bodyComposition, .profile:
            return .records
        case .settings:
            return .app
        case .todayRoot, .trendsRoot, .trendsDetail:
            return .hidden
        }
    }

    /// Whether the menu shows a row for this route. `laboratoryImportHistory` is
    /// reached by pushing from Laboratory, so it has no row — but it is still a
    /// route, because a link to it from anywhere is a reasonable thing to want.
    public var appearsInMenu: Bool {
        switch self {
        case .laboratoryImportHistory, .todayRoot, .trendsRoot, .trendsDetail: return false
        default: return true
        }
    }

    /// The menu, in the order it is read. Built by grouping `allCases` by their
    /// section, so adding a route adds its menu row; there is no second list to
    /// forget.
    public static var menu: [AppRouteGroup] {
        let shown = allCases.filter(\.appearsInMenu)
        let groups = Dictionary(grouping: shown, by: \.section)
        return groups.keys.sorted { $0.order < $1.order }.map { key in
            AppRouteGroup(section: key, routes: groups[key, default: []].sorted { $0.title < $1.title })
        }
    }
}

/// The whole decision a navigation request makes, as a value.
///
/// Pure on purpose: "which tab, and what does each stack become" is the part
/// that is easy to get wrong and worth pinning. The `TabCoordinator` in the app
/// is a thin adapter that applies one of these; it holds no rules of its own,
/// which is why there is nothing in it that `swift test` cannot reach.
public enum TabRouting {
    /// The result of one navigation request: a new tab, and new stacks.
    public struct Plan: Sendable, Hashable {
        public let selection: AppTab
        public let paths: [AppTab: [AppRoute]]

        public init(selection: AppTab, paths: [AppTab: [AppRoute]]) {
            self.selection = selection
            self.paths = paths
        }

        public func path(for tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }
    }

    /// Go to a route from anywhere.
    ///
    /// Three rules, and each of them is a behaviour somebody would otherwise
    /// have to decide at a call site:
    /// 1. **The tab you leave is untouched.** Navigating back to where you were
    ///    is the promise; resetting Trends because you tapped a Modules link
    ///    would break it invisibly.
    /// 2. **Tapping the route already on top does nothing.** A duplicate push
    ///    leaves a Back button pointing at an identical screen, which reads as
    ///    a bug rather than as the app agreeing with you.
    /// 3. **A deeper re-selection pushes again**, because popping back to the
    ///    existing copy would throw away whatever you navigated through to
    ///    reach it — a jump nobody asked for.
    public static func plan(selection: AppTab,
                            paths: [AppTab: [AppRoute]],
                            goingTo route: AppRoute) -> Plan {
        let stack = paths[route.tab] ?? []
        // Rule 2, checked before the tab switch because it covers both readings:
        // already looking at the route, or already on its tab with that route on
        // top. Either way the tap asked for something that is already true.
        if route.tab == selection, stack.last == route {
            return Plan(selection: selection, paths: paths)
        }
        var updated = paths
        updated[route.tab, default: []].append(route)
        return Plan(selection: route.tab, paths: updated)
    }

    /// Pop one route off the owning tab's stack.
    public static func plan(selection: AppTab,
                            paths: [AppTab: [AppRoute]],
                            popping: Bool) -> Plan {
        var updated = paths
        // `max(1, …)` is the whole implementation: a one-route stack cannot lose
        // its only element, because a `NavigationStack` showing its root has an
        // empty path and popping an empty path is a crash, not a no-op.
        if let stack = updated[selection], stack.count > 1 {
            updated[selection] = Array(stack.dropLast())
        } else {
            updated[selection] = []
        }
        return Plan(selection: selection, paths: updated)
    }

    /// Clear a tab's stack, keeping the tab. This is what the Modules menu
    /// tapping the row you are already on should do — "take me to the list" is
    /// not "push the list onto itself".
    public static func plan(selection: AppTab,
                            paths: [AppTab: [AppRoute]],
                            poppingToRoot: Bool) -> Plan {
        var updated = paths
        updated[selection] = []
        return Plan(selection: selection, paths: updated)
    }

    /// Select a tab, leaving every stack alone.
    public static func plan(selection: AppTab,
                            paths: [AppTab: [AppRoute]],
                            goingToTab tab: AppTab) -> Plan {
        Plan(selection: tab, paths: paths)
    }

    private static func path(for tab: AppTab, in paths: [AppTab: [AppRoute]]) -> [AppRoute] {
        paths[tab] ?? []
    }
}
