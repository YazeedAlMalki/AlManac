import SwiftUI
import AlmanacCore

private enum AppTab: Hashable {
    case today
    case training
    case hydration
    case nutrition
    case more
}

@main
@MainActor
struct AlmanacApp: App {
    @StateObject private var model = LaboratoryModel()
    @StateObject private var readinessModel = ReadinessModel()
    @StateObject private var hydrationModel = HydrationModel()
    @StateObject private var nutritionModel = NutritionModel()
    @StateObject private var trainingModel = TrainingModel()
    @StateObject private var healthModel = HealthModel()
    @StateObject private var trackingModel = TrackingCalendarModel()
    @State private var selectedTab = AppTab.today
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if model.store != nil {
                    TabView(selection: $selectedTab) {
                        ReadinessDashboardView(
                            model: readinessModel,
                            trainingModel: trainingModel,
                            trackingModel: trackingModel
                        )
                        .tag(AppTab.today)
                        .tabItem { Label("Today", systemImage: "gauge.with.dots.needle.67percent") }
                        TrainingDashboardView(model: trainingModel)
                            .tag(AppTab.training)
                            .tabItem { Label("Training", systemImage: "dumbbell") }
                        HydrationDashboardView(model: hydrationModel)
                            .tag(AppTab.hydration)
                            .tabItem { Label("Hydration", systemImage: "drop") }
                        NutritionQuickEntryView(model: nutritionModel)
                            .tag(AppTab.nutrition)
                            .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                        MoreView(
                            db: model.db,
                            labModel: model,
                            hydrationModel: hydrationModel,
                            healthModel: healthModel,
                            readinessModel: readinessModel,
                            trackingModel: trackingModel
                        )
                        .tag(AppTab.more)
                        .tabItem { Label("More", systemImage: "ellipsis.circle") }
                    }
                    .onChange(of: selectedTab) { _, tab in
                        if tab == .today { trackingModel.refresh() }
                    }
                    // The database is opened synchronously in LaboratoryModel.open(),
                    // so `model.db` is already set by the time this branch first
                    // renders. Configuring here (rather than at hydrationModel's own
                    // init) keeps both models sharing one connection instead of
                    // HydrationModel opening a second one to the same file.
                    .onAppear {
                        readinessModel.configure(db: model.db)
                        hydrationModel.configure(db: model.db)
                        nutritionModel.configure(db: model.db)
                        trainingModel.configure(db: model.db)
                        healthModel.configure(db: model.db)
                        trackingModel.configure(db: model.db)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Almanac could not open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(model.startupError ?? "Opening your records…")
                    } actions: {
                        Button("Try again") { model.open() }
                    }
                }
            }
            .tint(.teal)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Await both syncs before refreshing: sleep, vitals and water
                    // all feed the homepage, and a fire-and-forget hydration
                    // sync would leave the tracking calendar one refresh behind.
                    // Both syncs are no-ops until HealthKit is connected.
                    Task {
                        await hydrationModel.syncOnForeground()
                        await healthModel.syncNow()
                        readinessModel.refresh()
                        trackingModel.refresh()
                    }
                }
            }
        }
    }
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
            #if DEBUG
            try LabReportFixture.seedIfNeeded(into: store)
            #endif
            startupError = nil
        } catch {
            // Never reset or replace a database after a failed migration/open.
            startupError = String(describing: error)
        }
    }

    func changed() { generation += 1 }
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
    func editorError(_ message: Binding<String?>) -> some View {
        alert("Could not complete the action", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
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
