import SwiftUI
import WidgetKit
import AlmanacCore

/// The active fasting session, with start/end controls.
///
/// Like the water widget this reads (and the intents write) the shared
/// database, never a widget-local copy. The elapsed time is rendered from the
/// timeline entry's snapshot date; `StartFastIntent`/`EndFastIntent` reload
/// the timeline after each tap so the widget flips state immediately.
struct FastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlmanacFastingWidget", provider: FastingProvider()) { entry in
            FastingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Fasting")
        .description("Your current fasting session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FastingEntry: WidgetKit.TimelineEntry {
    let date: Date
    let startedAt: Date?
    let failed: Bool

    static let placeholder = FastingEntry(date: Date(), startedAt: nil, failed: false)
}

struct FastingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<FastingEntry>) -> Void) {
        let entry = load()
        // A live elapsed counter needs fresher entries than the water widget;
        // five minutes keeps the countdown within a sprint of accurate.
        let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: entry.date) ?? entry.date.addingTimeInterval(300)
        completion(WidgetKit.Timeline(entries: [entry], policy: .after(refresh)))
    }

    func load() -> FastingEntry {
        do {
            let db = try AppGroupDatabase.open()
            let startedAt = try FastingSessionStore(db: db).activeSession()?.startTimestamp
            return FastingEntry(date: Date(), startedAt: startedAt, failed: false)
        } catch {
            return FastingEntry(date: Date(), startedAt: nil, failed: true)
        }
    }
}

struct FastingWidgetView: View {
    let entry: FastingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Fasting", systemImage: "moon.stars.fill")
                .font(.caption).foregroundStyle(.indigo)

            if entry.failed {
                Spacer()
                Text("Open Almanac to see fasting")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let started = entry.startedAt {
                Text(elapsed(from: started, to: entry.date))
                    .font(.title3).fontWeight(.semibold)
                    .monospacedDigit()
                Text("since \(started.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                Button(intent: EndFastIntent()) {
                    Label("End fast", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .tint(.orange)
            } else {
                Spacer()
                Text("No active fast")
                    .font(.callout).foregroundStyle(.secondary)
                Button(intent: StartFastIntent()) {
                    Label("Start fast", systemImage: "play.fill")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .tint(.indigo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(start) / 60)
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}