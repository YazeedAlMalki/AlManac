import SwiftUI
import WidgetKit
import AlmanacCore

/// Today's water total against the goal, with a one-tap +250 ml control.
///
/// Data is read straight from the shared database (`AppGroupDatabase`), the
/// same source the app's Hydration tab shows — the widget never keeps its own
/// copy of anything. The timeline is refreshed by `LogWaterIntent.perform()`
/// after each tap, so the total updates the moment the user adds water.
struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlmanacWaterWidget", provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Water")
        .description("Today's water total against your goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WaterEntry: WidgetKit.TimelineEntry {
    let date: Date
    let total: Double
    let goal: Double?
    let failed: Bool

    static let placeholder = WaterEntry(date: Date(), total: 0, goal: 2500, failed: false)
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<WaterEntry>) -> Void) {
        let entry = load()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        completion(WidgetKit.Timeline(entries: [entry], policy: .after(refresh)))
    }

    func load() -> WaterEntry {
        do {
            let db = try AppGroupDatabase.open()
            let time = TimeModel(timeZone: .current)
            let today = time.logicalDay(Date())
            guard let bounds = time.bounds(of: today) else { return .placeholder }
            let range = (start: isoDay(bounds.start), end: isoDay(bounds.end))
            let total = try HydrationStore(db: db).total(from: range.start, to: range.end)
            let goal = try HydrationSettingsStore(db: db).getOrCreate().dailyGoalMilliliters
            return WaterEntry(date: Date(), total: total.value, goal: goal, failed: false)
        } catch {
            // A widget must never show a crash screen: fall back to a neutral
            // entry that tells the user to open the app instead.
            return WaterEntry(date: Date(), total: 0, goal: nil, failed: true)
        }
    }

    private func isoDay(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

struct WaterWidgetView: View {
    let entry: WaterEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Water", systemImage: "drop.fill")
                .font(.caption).foregroundStyle(.teal)

            if entry.failed {
                Spacer()
                Text("Open Almanac to see water")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(totalText)
                    .font(.title3).fontWeight(.semibold)
                if let goal = entry.goal, goal > 0 {
                    ProgressView(value: min(entry.total / goal, 1))
                        .tint(.teal)
                    Text("of \(Int(goal)) ml goal")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button(intent: LogWaterIntent()) {
                    Label("+250 ml", systemImage: "plus")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .tint(.teal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalText: String {
        entry.total == entry.total.rounded() ? "\(Int(entry.total)) ml" : String(format: "%.0f ml", entry.total)
    }
}