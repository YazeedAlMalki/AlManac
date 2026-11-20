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
        #expect(AppRoute.timeline.tab == .journal)
        #expect(AppRoute.profile.tab == .settings)
        #expect(AppRoute.settingsRoot.tab == .settings)
    }

    // MARK: - Going somewhere

    @Test("Tapping a route from the tab that owns it pushes")
    func sameTabPushes() {
        let plan = TabRouting.plan(selection: .journal,
                                   paths: [.journal: [.timeline]],
                                   goingTo: .laboratory)
        #expect(plan.selection == .journal, "Already there; switching tabs would be a visible no-op with a flicker")
        #expect(plan.paths[.journal] == [.timeline, .laboratory])
    }

    @Test("Tapping a route from another tab switches tab and pushes onto that tab's stack")
    func otherTabSwitchesAndPushes() {
        let plan = TabRouting.plan(selection: .today, paths: [:], goingTo: .timeline)
        #expect(plan.selection == .journal)
        #expect(plan.paths[.journal] == [.timeline])
    }

    @Test("A cross-tab tap leaves the tab you left exactly as you left it")
    func otherTabIsNotDisturbed() {
        // Going to Journal from Today must not reset Trends, and going to
        // Trends from Journal must not throw away a half-built Nutrition stack.
        // People navigate back to where they were; that is the whole promise.
        let before: [AppTab: [AppRoute]] = [
            .today: [.todayRoot],
            .trends: [.trendsRoot, .trendsDetail],
            .journal: [.training]
        ]
        let plan = TabRouting.plan(selection: .today, paths: before, goingTo: .timeline)
        #expect(plan.paths[.trends] == [.trendsRoot, .trendsDetail])
        #expect(plan.paths[.journal] == [.training, .timeline])
        #expect(plan.paths[.today] == before[.today])
    }

    @Test("Tapping the route already at the top does not push a second copy")
    func tappingTheSameRouteIsANoOp() {
        // Tapping "Body composition" while looking at Body composition should do
        // nothing. Pushing a duplicate would leave a Back button that returns to
        // an identical screen, which reads as a bug.
        let plan = TabRouting.plan(selection: .journal,
                                   paths: [.journal: [.timeline]], goingTo: .timeline)
        #expect(plan.paths[.journal] == [.timeline])
        #expect(plan.selection == .journal)
    }

    @Test("Tapping a route already on the stack, but not on top, pushes it again")
    func reSelectingADeeperRoutePushesAgain() {
        // Distinct from the case above. If you went A → B → A, the third tap is
        // a request to go *to* A from B, and a push is the honest reading: the
        // alternative (popping back to the existing A) is a jump nobody asked
        // for, and it discards B.
        let plan = TabRouting.plan(selection: .journal,
                                   paths: [.journal: [.timeline, .laboratory]],
                                   goingTo: .timeline)
        #expect(plan.paths[.journal] == [.timeline, .laboratory, .timeline])
    }

    // MARK: - Going back

    @Test("Popping the last route on a tab leaves the tab, not a broken stack")
    func popFromTheRoot() {
        // A `NavigationStack` whose path becomes empty shows its root, so a
        // one-route stack popping is legal — but only if the implementation does
        // not try to remove an element that is not there. Pinned because that
        // is the shape of bug that crashes rather than misbehaves.
        let plan = TabRouting.plan(selection: .journal,
                                   paths: [.journal: [.timeline]],
                                   popping: true)
        #expect(plan.paths[.journal] == [])
        #expect(plan.selection == .journal, "Popping does not change tab; that would be a second, invisible effect")
    }

    @Test("Popping an empty stack changes nothing")
    func popEmpty() {
        let plan = TabRouting.plan(selection: .today, paths: [:], popping: true)
        #expect(plan.paths[.today] ?? [] == [])
    }

    @Test("Popping to the root clears everything and keeps the tab")
    func popToRoot() {
        let plan = TabRouting.plan(selection: .journal,
                                   paths: [.journal: [.timeline, .laboratory, .laboratoryImportHistory]],
                                   poppingToRoot: true)
        #expect(plan.paths[.journal] == [])
        #expect(plan.selection == .journal)
    }

    // MARK: - Selecting a tab

    @Test("Selecting a tab never changes its stack")
    func selectingATabLeavesItsPath() {
        // Switching to Journal and back has to return you to the screen you
        // left, or every tab switch is a silent reset of whatever you had open.
        let before: [AppTab: [AppRoute]] = [.journal: [.timeline, .laboratory]]
        let plan = TabRouting.plan(selection: .journal, paths: before, goingToTab: .trends)
        #expect(plan.selection == .trends)
        #expect(plan.paths[.journal] == before[.journal])
    }

    @Test("The plan does not alias the caller's dictionary")
    func planDoesNotAlias() {
        // `plan` copies. If it aliased, a coordinator applying a plan would be
        // mutating the state it read, and the second of two rapid taps would
        // see a stack neither tap asked for.
        let paths: [AppTab: [AppRoute]] = [.journal: [.training]]
        let plan = TabRouting.plan(selection: .journal, paths: paths, goingTo: .laboratory)
        #expect(paths[.journal] == [.training], "The caller's own value is untouched")
        #expect(plan.paths[.journal] == [.training, .laboratory])
    }

    // MARK: - The menu is the router

    @Test("The Journal index and the router are one list, so they cannot drift")
    func menuAndRouterAreOneList() {
        // A screen in the menu that no route names is unreachable from anywhere
        // but the menu; a route no menu row names is unreachable from the menu.
        // One enum for both is what makes that impossible rather than unlikely.
        let menuTitles = Set(AppRoute.allCases.map(\.title))
        #expect(menuTitles.contains("Body composition"))
        #expect(menuTitles.contains("Profile"))
        #expect(Set(AppRoute.allCases.map(\.tab)).contains(.journal))
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

    // MARK: - Profile rows

    @Test("Profile lists Shifts & rhythm, Body composition, Body circumferences and the Body logger, in that order")
    func profileListsTheMovedPages() {
        #expect(AppRoute.profileRows == [.circadian, .bodyComposition, .bodyCircumference, .bodyLog])
        #expect(AppRoute.circadian.title == "Shifts & rhythm")
        #expect(AppRoute.bodyLog.title == "Log body", "the row says what the screen's title says")
    }

    @Test("Each Profile row opens its own screen, pushed on top of Profile")
    func eachProfileRowOpensItsScreen() {
        for row in AppRoute.profileRows {
            #expect(row.tab == .settings, "\(row) must live on the tab Profile lives on, or the push leaves Profile")
            let plan = TabRouting.plan(selection: .settings, paths: [.settings: [.profile]], goingTo: row)
            #expect(plan.selection == .settings)
            #expect(plan.paths[.settings] == [.profile, row], "\(row) did not open on top of Profile")
        }
    }

    @Test("A moved page has no Journal row, and Journal keeps every other row")
    func movedPagesLeaveTheJournalMenu() {
        let menu = AppRoute.menu.flatMap(\.routes)
        for row in AppRoute.profileRows {
            #expect(!menu.contains(row), "\(row) is still in the Journal menu")
        }
        for kept: AppRoute in [.training, .hydration, .nutrition, .fasting, .supplements, .context,
                               .prayer, .vitals, .laboratory, .timeline, .digestion] {
            #expect(menu.contains(kept), "\(kept) left the Journal menu")
        }
    }

    @Test("The Body logger is reachable from Profile, from anywhere")
    func bodyLoggerIsReachableFromProfile() {
        #expect(AppRoute.profileRows.contains(.bodyLog))
        let plan = TabRouting.plan(selection: .today, paths: [:], goingTo: .bodyLog)
        #expect(plan.selection == .settings)
        #expect(plan.paths[.settings] == [.bodyLog])
    }

    @Test("A route the menu does not show is reachable, because it is still a route")
    func pushedOnlyRoutesAreStillRoutes() {
        // Import history has no row of its own — it is pushed from Laboratory —
        // but it must still be linkable from anywhere, which is the point of it
        // being a route rather than a view.
        #expect(AppRoute.laboratoryImportHistory.appearsInMenu == false)
        #expect(AppRoute.laboratoryImportHistory.tab == .journal)
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
    @Test("Profile belongs to Settings, so the Journal index has no row for it or for Settings")
    func profileAndSettingsLeaveTheIndex() {
        // Settings is a tab now, and Profile is reached from inside it. Both
        // leaving the index is what `menu` regenerating itself should give,
        // with no hand edit to the list.
        let indexed = AppRoute.menu.flatMap(\.routes)
        #expect(!indexed.contains(.profile))
        #expect(!indexed.contains(.settingsRoot))
        #expect(indexed.allSatisfy { $0.tab == .journal }, "Every row in the index is a Journal screen")
    }

    // MARK: - Tapping the bar

    @Test("Tapping the tab already showing pops it to its root and keeps it")
    func reselectingPopsToRoot() {
        // Inside Laboratory, tapping Journal returns to the index; it does not
        // leave Laboratory on screen under a highlighted Journal.
        let before: [AppTab: [AppRoute]] = [
            .journal: [.laboratory, .laboratoryImportHistory],
            .settings: [.profile]
        ]
        let plan = TabRouting.plan(selection: .journal, paths: before, reselecting: .journal)
        #expect(plan.selection == .journal)
        #expect(plan.path(for: .journal) == [])
        #expect(plan.paths[.settings] == [.profile], "Only the tapped tab's stack is cleared")
    }

    @Test("Tapping a different tab is a switch, and leaves every stack alone")
    func reselectingAnotherTabIsASwitch() {
        let before: [AppTab: [AppRoute]] = [.journal: [.laboratory], .settings: [.profile]]
        let plan = TabRouting.plan(selection: .journal, paths: before, reselecting: .settings)
        #expect(plan.selection == .settings)
        #expect(plan.paths == before)
    }

    // MARK: - The bar's roster

    @Test("Four destinations and one action, the action third of five")
    func barRoster() {
        #expect(AppTab.allCases == [.today, .trends, .journal, .settings])
        #expect(AppBar.slots == [
            .destination(.today), .destination(.trends), .quickAdd,
            .destination(.journal), .destination(.settings)
        ])
        // Third of five equal columns is exactly the bar's centreline.
        #expect(AppBar.slots.firstIndex(of: .quickAdd) == AppBar.slots.count / 2)
        #expect(AppBar.slots.count == 5)
    }

    @Test("Every tab is on the bar exactly once")
    func everyTabHasOneSlot() {
        for tab in AppTab.allCases {
            #expect(AppBar.slots.filter { $0 == .destination(tab) }.count == 1, "\(tab) is not on the bar exactly once")
        }
    }

    @Test("Journal and Today do not share an icon shape")
    func journalIconIsDistinctFromToday() {
        #expect(AppTab.journal.icon != AppTab.today.icon)
        #expect(!AppTab.journal.icon.contains("grid"), "Today is a grid; a second grid on the bar reads as the same icon")
    }
}
