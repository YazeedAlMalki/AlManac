import SwiftUI
import AlmanacCore

@main
@MainActor
struct AlmanacApp: App {
    @StateObject private var model = LaboratoryModel()
    @StateObject private var hydrationModel = HydrationModel()
    @StateObject private var nutritionModel = NutritionModel()
    var body: some Scene {
        WindowGroup {
            Group {
                if model.store != nil {
                    TabView {
                        ReportListView(model: model)
                            .tabItem { Label("Laboratory", systemImage: "cross.case") }
                        HydrationDashboardView(model: hydrationModel)
                            .tabItem { Label("Hydration", systemImage: "drop") }
                        NutritionQuickEntryView(model: nutritionModel)
                            .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                        SettingsView(model: hydrationModel)
                            .tabItem { Label("Settings", systemImage: "gear") }
                    }
                    // The database is opened synchronously in LaboratoryModel.open(),
                    // so `model.db` is already set by the time this branch first
                    // renders. Configuring here (rather than at hydrationModel's own
                    // init) keeps both models sharing one connection instead of
                    // HydrationModel opening a second one to the same file.
                    .onAppear {
                        hydrationModel.configure(db: model.db)
                        nutritionModel.configure(db: model.db)
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
            let root = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Almanac", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let db = try Database(path: root.appendingPathComponent("almanac.sqlite").path)
            try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
            let catalog = LabCatalogStore(db: db)
            try LabCatalogSeed.seed(into: catalog)
            self.catalog = catalog
            self.db = db
            store = LabStore(db: db)
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
