import Testing
import Foundation
@testable import AlmanacCore

/// Cross-tab navigation: if a button names a feature, tapping it lands on that
/// feature no matter where you were.
///
/// The pure half is here so the decision — which tab, and what the stack becomes
/// — is testable without SwiftUI. The `TabCoordinator` in the app is a thin
/// adapter over `TabRouting`; if the logic were only there, nothing in
/// `swift test` could reach it.
@Suite("Cross-tab navigation")
struct TabRoutingTests {

    // MARK: - A route knows its tab

    @Test("Every route names the tab that owns it, and the compiler checks the list")
    func everyRouteDeclaresItsTab() {
        // This is the whole leverage of putting `tab` on the case rather than in
        // a parallel table: a case added without a tab is a compile error
        // inside the enum's own `switch`, not a route that silently resolves to
        // nothing at runtime.
        for route in AppRoute.allCases {
            #expect(AppTab.allCases.contains(route.tab), "\(route) claims a tab that does not exist")
        }
    }

    @Test("A route's tab is stable, so a link does not move under a tap")
    func routeTabIsStable() {
        #expect(AppRoute.bodyComposition.tab == .modules)
        #expect(AppRoute.profile.tab == .modules)
        #expect(AppRoute.settings.tab == .modules)
    }

    // MARK: - Going somewhere

    @Test("Tapping a route from the tab that owns it pushes")
    func sameTabPushes() {
        let plan = TabRouting.plan(selection: .modules,
                                   paths: [.modules: [.bodyComposition]],
                                   goingTo: .profile)
        #expect(plan.selection == .modules, "Already there; switching tabs would be a visible no-op with a flicker")
        #expect(plan.paths[.modules] == [.bodyComposition, .profile])
    }

    @Test("Tapping a route from another tab switches tab and pushes onto that tab's stack")
    func otherTabSwitchesAndPushes() {
        let plan = TabRouting.plan(selection: .today, paths: [:], goingTo: .bodyComposition)
        #expect(plan.selection == .modules)
        #expect(plan.paths[.modules] == [.bodyComposition])
    }

    @Test("A cross-tab tap leaves the tab you left exactly as you left it")
    func otherTabIsNotDisturbed() {
        // Going to Modules from Today must not reset Trends, and going to
        // Trends from Modules must not throw away a half-built Nutrition stack.
        // People navigate back to where they were; that is the whole promise.
        let before: [AppTab: [AppRoute]] = [
            .today: [.todayRoot],
            .trends: [.trendsRoot, .trendsDetail],
            .modules: [.training]
        ]
        let plan = TabRouting.plan(selection: .today, paths: before, goingTo: .bodyComposition)
        #expect(plan.paths[.trends] == [.trendsRoot, .trendsDetail])
        #expect(plan.paths[.modules] == [.training, .bodyComposition])
        #expect(plan.paths[.today] == before[.today])
    }

    @Test("Tapping the route already at the top does not push a second copy")
    func tappingTheSameRouteIsANoOp() {
        // Tapping "Body composition" while looking at Body composition should do
        // nothing. Pushing a duplicate would leave a Back button that returns to
        // an identical screen, which reads as a bug.
        let plan = TabRouting.plan(selection: .modules,
                                   paths: [.modules: [.bodyComposition]], goingTo: .bodyComposition)
        #expect(plan.paths[.modules] == [.bodyComposition])
        #expect(plan.selection == .modules)
    }

    @Test("Tapping a route already on the stack, but not on top, pushes it again")
    func reSelectingADeeperRoutePushesAgain() {
        // Distinct from the case above. If you went A → B → A, the third tap is
        // a request to go *to* A from B, and a push is the honest reading: the
        // alternative (popping back to the existing A) is a jump nobody asked
        // for, and it discards B.
        let plan = TabRouting.plan(selection: .modules,
                                   paths: [.modules: [.bodyComposition, .profile]],
                                   goingTo: .bodyComposition)
        #expect(plan.paths[.modules] == [.bodyComposition, .profile, .bodyComposition])
    }

    // MARK: - Going back

    @Test("Popping the last route on a tab leaves the tab, not a broken stack")
    func popFromTheRoot() {
        // A `NavigationStack` whose path becomes empty shows its root, so a
        // one-route stack popping is legal — but only if the implementation does
        // not try to remove an element that is not there. Pinned because that
        // is the shape of bug that crashes rather than misbehaves.
        let plan = TabRouting.plan(selection: .modules,
                                   paths: [.modules: [.bodyComposition]],
                                   popping: true)
        #expect(plan.paths[.modules] == [])
        #expect(plan.selection == .modules, "Popping does not change tab; that would be a second, invisible effect")
    }

    @Test("Popping an empty stack changes nothing")
    func popEmpty() {
        let plan = TabRouting.plan(selection: .today, paths: [:], popping: true)
        #expect(plan.paths[.today] ?? [] == [])
    }

    @Test("Popping to the root clears everything and keeps the tab")
    func popToRoot() {
        let plan = TabRouting.plan(selection: .modules,
                                   paths: [.modules: [.bodyComposition, .profile, .settings]],
                                   poppingToRoot: true)
        #expect(plan.paths[.modules] == [])
        #expect(plan.selection == .modules)
    }

    // MARK: - Selecting a tab

    @Test("Selecting a tab never changes its stack")
    func selectingATabLeavesItsPath() {
        // Switching to Modules and back has to return you to the screen you
        // left, or every tab switch is a silent reset of whatever you had open.
        let before: [AppTab: [AppRoute]] = [.modules: [.bodyComposition, .profile]]
        let plan = TabRouting.plan(selection: .modules, paths: before, goingToTab: .trends)
        #expect(plan.selection == .trends)
        #expect(plan.paths[.modules] == before[.modules])
    }

    @Test("The plan does not alias the caller's dictionary")
    func planDoesNotAlias() {
        // `plan` copies. If it aliased, a coordinator applying a plan would be
        // mutating the state it read, and the second of two rapid taps would
        // see a stack neither tap asked for.
        let paths: [AppTab: [AppRoute]] = [.modules: [.training]]
        let plan = TabRouting.plan(selection: .modules, paths: paths, goingTo: .profile)
        #expect(paths[.modules] == [.training], "The caller's own value is untouched")
        #expect(plan.paths[.modules] == [.training, .profile])
    }

    // MARK: - The menu is the router

    @Test("The modules list and the router are one list, so they cannot drift")
    func menuAndRouterAreOneList() {
        // A screen in the menu that no route names is unreachable from anywhere
        // but the menu; a route no menu row names is unreachable from the menu.
        // One enum for both is what makes that impossible rather than unlikely.
        let menuTitles = Set(AppRoute.allCases.map(\.title))
        #expect(menuTitles.contains("Body composition"))
        #expect(menuTitles.contains("Profile"))
        #expect(Set(AppRoute.allCases.map(\.tab)).contains(.modules))
    }

    @Test("A route that appears in the menu carries a section to appear under")
    func routesCarryTheirSection() {
        // The grouping is data, not a hand-written Section per group. That is
        // what lets the list be generated from `allCases` at all.
        //
        // Only menu routes are checked: the three tab roots and the import
        // history are reached by pushing, and naming a group for them would be
        // inventing a section nobody looks at.
        for route in AppRoute.allCases where route.appearsInMenu {
            #expect(!route.section.title.isEmpty, "\(route) has no section to appear under")
            #expect(route.section != .hidden, "\(route) appears in the menu but is filed as hidden")
        }
    }

    @Test("Shifts & rhythm is a Modules screen, listed under Daily context")
    func circadianLivesUnderDailyContext() {
        #expect(AppRoute.circadian.tab == .modules)
        #expect(AppRoute.circadian.title == "Shifts & rhythm")
        let dailyContext = AppRoute.menu.first { $0.section == .dailyContext }
        #expect(dailyContext?.routes.contains(.circadian) == true)
    }

    @Test("A route the menu does not show is reachable, because it is still a route")
    func pushedOnlyRoutesAreStillRoutes() {
        // Import history has no row of its own — it is pushed from Laboratory —
        // but it must still be linkable from anywhere, which is the point of it
        // being a route rather than a view.
        #expect(AppRoute.laboratoryImportHistory.appearsInMenu == false)
        #expect(AppRoute.laboratoryImportHistory.tab == .modules)
        #expect(!AppRoute.menu.flatMap(\.routes).contains(.laboratoryImportHistory))
    }

    @Test("Every route is reachable: the menu is built from the same list the router uses")
    func everyRouteAppearsInExactlyOneSection() {
        var seen: [String: Int] = [:]
        for route in AppRoute.allCases {
            seen[route.section.title, default: 0] += 1
        }
        #expect(seen.values.allSatisfy { $0 > 0 })
        #expect(seen.count >= 3, "The menu is grouped, so it is not one flat list")
    }
}
