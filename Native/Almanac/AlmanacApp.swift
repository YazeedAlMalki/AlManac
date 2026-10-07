import SwiftUI
import AlmanacCore

@main
@MainActor
struct AlmanacApp: App {
    @StateObject private var model = LaboratoryModel()
    @StateObject private var readinessModel = ReadinessModel()
    @StateObject private var hydrationModel = HydrationModel()
    @StateObject private var nutritionModel = NutritionModel()
    @StateObject private var trainingModel = TrainingModel()
    @StateObject private var programModel = ProgramModel()
    @StateObject private var healthModel = HealthModel()
    @StateObject private var prayerModel = PrayerModel()
    @StateObject private var fastingModel = FastingModel()
    @StateObject private var trackingModel = TrackingCalendarModel()
    @StateObject private var notificationModel = NotificationModel()
    /// Owned here, above the bar, because it is the one piece of state that has
    /// to be shared by all three tabs: which tab is showing, and how deep each
    /// tab's stack is. Everything else in the app is per-feature.
    @StateObject private var tabs = TabCoordinator()
    @State private var quickLogging = false
    @AppStorage("almanac.appearance") private var appearanceRaw = AlmanacAppearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var appearance: AlmanacAppearance {
        AlmanacAppearance(rawValue: appearanceRaw) ?? .system
    }

    init() {
        AlmanacFontRegistration.registerBundledFonts()
        #if DEBUG
        if !AlmanacFontRegistration.hasDisplayFont() {
            print("Almanac design warning: bundled Fraunces did not register; display text will use the system fallback.")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.store != nil {
                    appShell
                } else {
                    ContentUnavailableView {
                        Label("Almanac could not open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(model.startupError ?? "Opening your records…")
                    } actions: {
                        Button("Try again") { model.open() }
                    }
                    .almanacScreen()
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    prayerModel.ensureCache()
                    fastingModel.ensureToday()
                    prayerModel.refreshLocationIfAutomatic()
                    // §2.5's import outcomes. Synchronous and one query when
                    // there is nothing stale, so it belongs with the other
                    // `ensure…` passes rather than in the async block below —
                    // putting it after the awaits would let the import history
                    // screen read a count from before the pass that fixes it.
                    model.reconcileImportJobs()
                    // Await both syncs before refreshing: sleep, vitals and water
                    // all feed the homepage, and a fire-and-forget hydration
                    // sync would leave the tracking calendar one refresh behind.
                    // Both syncs are no-ops until HealthKit is connected.
                    Task {
                        await hydrationModel.syncOnForeground()
                        await healthModel.syncNow()
                        // Water imported from Apple Health is intake like any
                        // other: a dry fast it broke is re-derived now, before
                        // the reminders that depend on the fast are planned.
                        fastingModel.ensureToday()
                        readinessModel.refresh()
                        trackingModel.refresh()
                        // §14.1's scheduling pass, after prayer times and today's
                        // fast are current — suhoor and iftar triggers are derived
                        // from exactly those. Awaiting it here rather than letting
                        // it race the fast/pass it depends on.
                        await notificationModel.reconcileNotifications()
                        await notificationModel.deliverSnackSuggestionIfWarranted()
                    }
                } else if phase == .background {
                    prayerModel.pauseLocation()
                }
            }
        }
    }

    private var appShell: some View {
        // The bar is laid out in flow rather than attached with
        // `safeAreaInset`: a navigation stack swallows that inset, so every
        // scroll view kept the full screen height and its last row stayed
        // trapped behind the bar — Settings could not be scrolled to.
        VStack(spacing: 0) {
            selectedDestination
            AlmanacNavigationBar(selection: tabs.selectionBinding, quickLog: { quickLogging = true })
        }
            .environment(\.tabCoordinator, tabs)
            .sheet(isPresented: $quickLogging, onDismiss: {
                // Anything logged there can have broken a fast or changed what
                // the reminders should mute.
                fastingModel.refresh()
                Task { await notificationModel.reconcileNotifications() }
            }) {
                QuickLogView(
                    db: model.db,
                    hydrationModel: hydrationModel,
                    nutritionModel: nutritionModel,
                    trainingModel: trainingModel,
                    trackingModel: trackingModel,
                    fastingModel: fastingModel
                )
            }
            .onChange(of: tabs.selected) { _, tab in
                if tab == .today { trackingModel.refresh() }
            }
            // The database is opened synchronously in LaboratoryModel.open(),
            // so `model.db` is ready before this branch first renders. Keeping
            // configuration here preserves the app's one shared connection.
            .onAppear {
                readinessModel.configure(db: model.db)
                hydrationModel.configure(db: model.db)
                nutritionModel.configure(db: model.db)
                trainingModel.configure(db: model.db)
                programModel.configure(db: model.db)
                healthModel.configure(db: model.db)
                trackingModel.configure(db: model.db)
                // The fast and the reminders are derived from prayer times, so
                // a change there (a new city, a method, an offset, travel)
                // re-derives both at once rather than at the next foreground.
                prayerModel.onPrayerTimesChanged = { [fastingModel, notificationModel] in
                    fastingModel.ensureToday()
                    Task { await notificationModel.reconcileNotifications() }
                }
                fastingModel.onStateChanged = { [notificationModel] in
                    Task { await notificationModel.reconcileNotifications() }
                }
                prayerModel.configure(db: model.db)
                fastingModel.configure(db: model.db)
                notificationModel.configure(db: model.db)
            }
            .background(AlmanacPalette.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var selectedDestination: some View {
        switch tabs.selected {
        case .today:
            ReadinessDashboardView(
                model: readinessModel,
                trainingModel: trainingModel,
                hydrationModel: hydrationModel,
                nutritionModel: nutritionModel,
                trackingModel: trackingModel
            )
        case .trends:
            // Deliberately *not* wrapped in the coordinator's stack. Trends brings
            // its own `NavigationStack` and pushes its own links inside it, and
            // nesting a second one inside the first is a back button that pops
            // the wrong stack. It is also the only tab with nothing outside to
            // reach it — a cross-tab link names a feature, and Trends is a
            // feature only the bar links to. If a route ever needs to push
            // *into* Trends, that is the change where Trends adopts the
            // coordinator's path, not a wrapper added here.
            TrendsView(db: model.db)
        case .modules:
            // `appShell` only renders when the store opened, and `db` is
            // assigned just before it, so this unwrap cannot fail in practice.
            // The `else` is there because "cannot fail in practice" is not the
            // same as "cannot fail", and a menu that silently vanishes is worse
            // than one that says why.
            if let db = model.db {
                ModulesView(
                    db: db,
                labModel: model,
                hydrationModel: hydrationModel,
                nutritionModel: nutritionModel,
                trainingModel: trainingModel,
                programModel: programModel,
                healthModel: healthModel,
                readinessModel: readinessModel,
                trackingModel: trackingModel,
                prayerModel: prayerModel,
                fastingModel: fastingModel,
                    notificationModel: notificationModel
                )
            } else {
                ContentUnavailableView("Modules unavailable",
                                       systemImage: AlmanacIcon.modules,
                                       description: Text("Almanac’s database is not open. Restart the app to try again."))
            }
        }
    }
}


private struct AlmanacNavigationBar: View {
    @Binding var selection: AppTab
    let quickLog: () -> Void
    /// The quick-log action's own column. The bar has three destinations and
    /// one action, so the action gets a fixed column and the three tabs share
    /// what is left. Today and Trends sit in one half-width group and Modules
    /// in the other, which is what puts the action on the bar's true
    /// centreline: two equal halves with a fixed column between them.
    private static let quickLogColumn: CGFloat = 68

    /// A destination's icon well, the gap under it, and the one caption line
    /// below that. These three are the tab row's vertical geometry, and both
    /// the destination buttons and the quick-log action are placed from them,
    /// so the action's centreline is derived rather than eyeballed.
    private static let iconWell: CGFloat = 28
    private static let iconGap: CGFloat = 3
    private static let captionLine: CGFloat = 15

    /// How far the quick-log action is lifted to sit on the tab icons' line.
    /// A destination column is `iconWell + iconGap + captionLine` tall and is
    /// centred in the row, which leaves its icon well sitting high in that
    /// column; the action is full height, so it is raised by half of
    /// everything below the icon well to share that line rather than hang low
    /// against its neighbours.
    private static let iconLineLift: CGFloat = (iconGap + captionLine) / 2

    var body: some View {
        HStack(spacing: 0) {
            // Built from `AppTab.barGroup` rather than written out. The bar's
            // layout arithmetic — two equal halves with a fixed column between
            // them — is what puts the quick-log action on the true centreline,
            // and a hand-written `HStack` of three buttons is a second place
            // for that arithmetic to live.
            HStack(spacing: 0) {
                ForEach(AppTab.allCases.filter { $0.barGroup == .leadingHalf }) { tab in
                    destinationButton(tab)
                }
            }
            .frame(maxWidth: .infinity)

            quickLogButton

            HStack(spacing: 0) {
                ForEach(AppTab.allCases.filter { $0.barGroup == .trailingHalf }) { tab in
                    destinationButton(tab)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 66)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(AlmanacPalette.surface)
        .overlay(alignment: .top) {
            AlmanacRule()
        }
        // The bar now sits in the layout flow, so the surface is extended past
        // the safe area to keep the home indicator on the bar's own colour.
        .background(AlmanacPalette.surface.ignoresSafeArea(edges: .bottom))
        .accessibilityElement(children: .contain)
    }

    /// The quick-log action, in the bar's own flow rather than floated above
    /// it. It used to be an overlay offset upward out of the bar, which put
    /// the top of a 52pt target over the scrolling content underneath — a tap
    /// there went to quick log instead of the row that owned it — and
    /// overlapped the right edge of the Trends button, because a
    /// fixed-width spacer between three `.frame(maxWidth: .infinity)`
    /// buttons cannot centre anything. In the flow the column is 68pt, so no
    /// destination can sit under it. The shadow replaces the overlap as the
    /// thing that lifts the action off the bar.
    private var quickLogButton: some View {
        Button(action: quickLog) {
            Image(systemName: AlmanacIcon.quickAdd)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AlmanacPalette.onAccent)
                .frame(width: 52, height: 52)
                .background(AlmanacPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: AlmanacPalette.accent.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .frame(width: Self.quickLogColumn)
        .alignmentGuide(VerticalAlignment.center) { dim in
            dim.height / 2 + Self.iconLineLift
        }
        .accessibilityLabel("Quick log")
        .accessibilityHint("Choose water, food, training, or a body measurement")
        .accessibilityIdentifier("quick-log")
    }

    private func destinationButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: Self.iconGap) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                    .frame(width: 36, height: Self.iconWell)
                    .background(selection == tab ? AlmanacPalette.surfaceMuted : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(tab.title)
                    .font(AlmanacTypography.font(.caption))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            .foregroundStyle(selection == tab ? AlmanacPalette.accent : AlmanacPalette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
        // The bar is hand-built rather than a `TabView`, which means it does not
        // inherit the system's handle on its own items — and a custom bar with
        // no identifier is ambiguous to every test the moment a screen is
        // pushed. "Modules" then names two buttons at once: this tab and the
        // navigation bar's back button, which is labelled with the screen it
        // came from. That is not a test-only problem; it is the same collision a
        // screen reader user hits, so the identifier is part of the bar rather
        // than a testing convenience bolted on.
        .accessibilityIdentifier(Self.identifier(for: tab))
    }

    static func identifier(for tab: AppTab) -> String { "tab-\(tab.rawValue)" }
}

/// All access to this connection stays on the main actor. The core owns SQL,
/// migrations and revisions; views only submit explicit editing requests.
@MainActor
final class LaboratoryModel: ObservableObject {
    @Published private(set) var store: LabStore?
    @Published private(set) var catalog: LabCatalogStore?
    /// Exposed so other models (`HydrationModel`) can share this connection
    /// instead of opening a second one to the same SQLite file.
    @Published private(set) var db: Database?
    @Published private(set) var generation = 0
    @Published private(set) var startupError: String?
    /// Where imports are recorded. Exposed so the import screen records
    /// through the same handle rather than building a second store over the
    /// same file — and it is optional only because `db` is: it exists exactly
    /// when the database does.
    @Published private(set) var importJobs: LabImportJobStore?

    init() { open() }

    func open() {
        do {
            // The database lives in the App Group container so the widgets can
            // open the same file; `AppGroupDatabase` adopts a pre-App-Group
            // install's Application Support copy on first launch.
            try AppGroupDatabase.adoptLegacyData()
            let db = try AppGroupDatabase.open()
            let catalog = LabCatalogStore(db: db)
            try LabCatalogSeed.seed(into: catalog)
            let exercises = ExerciseCatalogStore(db: db)
            try WorkoutGuideSeed.seed(into: exercises)
            // Both content rules are checked here as well as in the test suite:
            // shipping an uncredited source, or an exercise with no
            // demonstration graphic, must not reach a user's device.
            try AttributionAudit.assertAttributed(AttributionCatalog.bundledSourceIds)
            try ExerciseGraphicAudit.assertEveryExerciseHasGraphic(try exercises.all())
            self.catalog = catalog
            self.db = db
            let store = LabStore(db: db)
            self.store = store
            self.importJobs = LabImportJobStore(db: db)
            #if DEBUG
            try LabReportFixture.seedIfNeeded(into: store)
            // The only way anything is ever planted here is a launch argument
            // naming it; `fromLaunchArguments` returns nil for every ordinary
            // launch, and `VitalsSeedPlanTests` pins that. The `#if DEBUG` is a
            // second gate, not the first.
            //
            // It does **not** keep `VitalsSeedPlan` out of a Release binary —
            // checked: the type and the argument string are both present there,
            // because AlmanacCore is compiled whole into the app. What the gate
            // removes is the only call site, so a Release build cannot reach
            // `apply` at all. Reachability, not absence, is the claim.
            //
            // It runs here rather than in a view because a UI test relaunches the
            // app and then drives it: the readings have to be in place before the
            // first screen reads them. See `VitalsSeedPlan` for why the editor's
            // own date picker could not be driven instead.
            if let plan = VitalsSeedPlan.fromLaunchArguments(ProcessInfo.processInfo.arguments) {
                try plan.apply(into: VitalsRecordStore(db: db))
            }
            #endif
            startupError = nil
        } catch {
            // Never reset or replace a database after a failed migration/open.
            startupError = String(describing: error)
        }
    }

    func changed() { generation += 1 }

    /// Pull-based reconciliation: works out how past imports went and links the
    /// rows the catalog can now resolve.
    ///
    /// Called on foreground alongside the other `ensure…` passes, and **not**
    /// from the import button. Whether a row matched is a property of the file
    /// *and the catalog*, and the catalog gains aliases long after any given
    /// import — so deciding it at the import would freeze the wrong answer into
    /// the record. One query when there is nothing to do, and only the stale
    /// jobs are examined after that, which is what keeps this off the critical
    /// path (see the performance note in `docs/handoff-2026-09-30.md` §8).
    ///
    /// Returns how many jobs it closed, so a caller can tell "nothing to do"
    /// from "ran and found nothing".
    @discardableResult
    func reconcileImportJobs() -> Int {
        guard let db else { return 0 }
        do {
            let closed = try LabImportJobReconciler(db: db).reconcile()
            if closed > 0 { changed() }
            return closed
        } catch {
            // A stale count is the cost of missing this call, not a reason to
            // put an alert in front of someone about their own laboratory data.
            return 0
        }
    }
}

struct EditorFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func optionalText(_ text: String) -> String? { text.isEmpty ? nil : text }
func dateLabel(_ date: PartialDateTime) -> String {
    date.isKnown ? date.text : "Date unknown"
}
func readable(_ raw: String) -> String { raw.replacingOccurrences(of: "_", with: " ").capitalized }

extension View {
    /// One error surface for every editor. The alert used to be titled "Could
    /// not complete the action" for everything — a bad number, a duplicate
    /// measurement, a failed import — which is the most default string in the
    /// app and told the reader nothing. The title is the specific failure the
    /// store raised, so it names what happened; the body stays the store's
    /// own wording, which already says how to fix it.
    func editorError(_ message: Binding<String?>) -> some View {
        alert(errorTitle(message.wrappedValue), isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }

    private func errorTitle(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "Something went wrong" }
        // A message that already begins with what went wrong is its own title.
        let sentence = message.split(separator: "\n").first.map(String.init) ?? message
        if let first = sentence.split(separator: ".").first, first.count > 12 {
            return String(first).trimmingCharacters(in: .whitespaces)
        }
        return sentence
    }
}

/// Text and precision remain explicit; no DatePicker invents a missing date.
@MainActor
struct PartialDateFields: View {
    @Binding var text: String
    @Binding var precision: TimePrecision
    var body: some View {
        Picker("Precision", selection: $precision) {
            ForEach(TimePrecision.allCases, id: \.self) { Text(readable($0.rawValue)).tag($0) }
        }
        if precision == .unknown {
            Text("Date unknown").foregroundStyle(.secondary)
        } else {
            TextField(example, text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Enter only what is known. Add Z or +03:00 to a time only if the source states an offset.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var example: String {
        switch precision {
        case .unknown: return "Unknown"
        case .year: return "2026"
        case .month: return "2026-09"
        case .day: return "2026-09-08"
        case .hour: return "2026-09-08T10"
        case .minute: return "2026-09-08T10:30"
        case .instant: return "2026-09-08T10:30:00+03:00"
        }
    }
}

func editedDate(text: String, precision: TimePrecision, original: PartialDateTime = .unknown) throws -> PartialDateTime {
    if precision == .unknown { return .unknown }
    if text == original.text && precision == original.precision { return original }
    guard let date = PartialDateTime(storedText: text, precision: precision, zone: original.zone), date.span != nil else {
        throw EditorFailure(message: "Enter a valid date matching the selected precision, or choose Unknown.")
    }
    return date
}
