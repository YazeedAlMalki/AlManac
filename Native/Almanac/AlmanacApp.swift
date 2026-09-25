import SwiftUI
import AlmanacCore

private enum AppTab: Hashable {
    case today
    case trends
    case modules
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
    @StateObject private var prayerModel = PrayerModel()
    @StateObject private var fastingModel = FastingModel()
    @StateObject private var trackingModel = TrackingCalendarModel()
    @State private var selectedTab = AppTab.today
    @State private var quickLogging = false
    @AppStorage("almanac.appearance") private var appearanceRaw = AlmanacAppearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var appearance: AlmanacAppearance {
        AlmanacAppearance(rawValue: appearanceRaw) ?? .system
    }

    init() {
        AlmanacFontRegistration.registerBundledFonts()
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
                    prayerModel.resumeLocationIfAuthorized()
                    Task {
                        await hydrationModel.syncOnForeground()
                        await healthModel.syncNow()
                        readinessModel.refresh()
                        trackingModel.refresh()
                    }
                } else if phase == .background {
                    prayerModel.pauseLocation()
                }
            }
        }
    }

    private var appShell: some View {
        selectedDestination
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AlmanacNavigationBar(selection: $selectedTab, quickLog: { quickLogging = true })
            }
            .sheet(isPresented: $quickLogging) {
                QuickLogView(
                    db: model.db,
                    hydrationModel: hydrationModel,
                    nutritionModel: nutritionModel,
                    trainingModel: trainingModel,
                    trackingModel: trackingModel
                )
            }
            .onChange(of: selectedTab) { _, tab in
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
                healthModel.configure(db: model.db)
                trackingModel.configure(db: model.db)
                prayerModel.configure(db: model.db)
                fastingModel.configure(db: model.db)
            }
            .background(AlmanacPalette.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var selectedDestination: some View {
        switch selectedTab {
        case .today:
            ReadinessDashboardView(
                model: readinessModel,
                trainingModel: trainingModel,
                hydrationModel: hydrationModel,
                nutritionModel: nutritionModel,
                trackingModel: trackingModel
            )
        case .trends:
            TrendsView(db: model.db)
        case .modules:
            MoreView(
                db: model.db,
                labModel: model,
                hydrationModel: hydrationModel,
                nutritionModel: nutritionModel,
                trainingModel: trainingModel,
                healthModel: healthModel,
                readinessModel: readinessModel,
                trackingModel: trackingModel,
                prayerModel: prayerModel,
                fastingModel: fastingModel
            )
        }
    }
}

private struct AlmanacNavigationBar: View {
    @Binding var selection: AppTab
    let quickLog: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            destinationButton(.today, title: "Today", icon: AlmanacIcon.today)
            destinationButton(.trends, title: "Trends", icon: AlmanacIcon.trends)

            Button(action: quickLog) {
                Image(systemName: AlmanacIcon.quickAdd)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AlmanacPalette.onAccent)
                    .frame(width: 52, height: 52)
                    .background(AlmanacPalette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .shadow(color: AlmanacPalette.accent.opacity(0.22), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .offset(y: -12)
            .accessibilityLabel("Quick log")
            .accessibilityHint("Choose water, food, training, or a body measurement")
            .accessibilityIdentifier("quick-log")

            destinationButton(.modules, title: "Modules", icon: AlmanacIcon.modules)
        }
        .frame(height: 66)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(AlmanacPalette.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(AlmanacPalette.divider).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func destinationButton(_ tab: AppTab, title: String, icon: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                    .frame(width: 36, height: 28)
                    .background(selection == tab ? AlmanacPalette.surfaceMuted : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(AlmanacTypography.font(.caption))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            .foregroundStyle(selection == tab ? AlmanacPalette.accent : AlmanacPalette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
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
