import SwiftUI
import AlmanacCore

@MainActor
struct HydrationDashboardView: View {
    @ObservedObject var model: HydrationModel
    private let embedded: Bool
    @State private var logging = false
    @State private var error: String?

    init(model: HydrationModel, embedded: Bool = false) {
        self.model = model
        self.embedded = embedded
    }

    /// The settings-row daily goal; the app default is 2000 mL when the row
    /// has never stored one (the goal now lives in `hydration_settings`, not
    /// `@AppStorage`).
    private var dailyGoal: Double { model.hydrationSettings?.dailyGoalMilliliters ?? 2000 }

    var body: some View {
        dashboard.almanacNavigationHost(embedded)
    }

    private var dashboard: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(model.todayTotal.value)) mL").font(.largeTitle.bold())
                    Text("of \(Int(dailyGoal)) mL goal")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: min(model.todayTotal.value / max(dailyGoal, 1), 1))
                        .tint(AlmanacPalette.accent)
                }.padding(.vertical, 4)
            }
            Section("Today") {
                if model.todaysEntries.isEmpty {
                    Text("Nothing logged yet today.").foregroundStyle(.secondary)
                }
                ForEach(model.todaysEntries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(Int(entry.amount.value)) mL")
                            if let note = entry.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(timeLabel(entry.loggedAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Hydration")
        .toolbar { Button("Log water", systemImage: "plus") { logging = true } }
        .sheet(isPresented: $logging) { HydrationLoggingView(model: model) }
        .task { model.refresh() }
        .editorError($error)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            do { try model.delete(id: model.todaysEntries[index].id) }
            catch { self.error = String(describing: error) }
        }
    }

    private func timeLabel(_ date: PartialDateTime) -> String {
        guard date.isKnown else { return "" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let instant = parser.date(from: date.text) else { return date.text }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: instant)
    }
}
