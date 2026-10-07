import SwiftUI
import WidgetKit
import AlmanacCore

/// The fast that matters right now: today's religious fast when today is one,
/// otherwise the intermittent fast with start/end controls.
///
/// Like the water widget this reads (and the intents write) the shared
/// database, never a widget-local copy. It only reads: the religious phase is
/// computed from the prayer cache and the session by `ReligiousFastDay.phase`,
/// the same function the app's screen uses, so a widget whose app has not run
/// since Maghrib still says the fast is complete. Counters are `Text` timers,
/// which the system keeps live between timeline entries; the timeline itself
/// only needs an entry at each phase change (Fajr, Maghrib).
struct FastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlmanacFastingWidget", provider: FastingProvider()) { entry in
            FastingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Fasting")
        .description("Today's fast: suhoor, iftar, or your intermittent fast.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FastingEntry: WidgetKit.TimelineEntry {
    enum State {
        case religious(ReligiousFastPhase)
        /// An intermittent fast running since the date, or none.
        case intermittent(startedAt: Date?)
        case failed
    }

    let date: Date
    let state: State

    static let placeholder = FastingEntry(date: Date(), state: .intermittent(startedAt: nil))
}

struct FastingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(load(at: Date()).first ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<FastingEntry>) -> Void) {
        let now = Date()
        let entries = load(at: now)
        // Reload after the last phase change, or in half an hour — a Health
        // import or a log from another device can change the picture.
        let refresh = max((entries.last?.date ?? now), now).addingTimeInterval(30 * 60)
        completion(WidgetKit.Timeline(entries: entries, policy: .after(refresh)))
    }

    /// One entry now, plus one at each of today's phase changes still to come,
    /// so suhoor flips to fasting at Fajr and fasting to complete at Maghrib
    /// without waiting for a reload.
    func load(at now: Date) -> [FastingEntry] {
        do {
            let db = try AppGroupDatabase.open()
            let today = try FastingCoordinator(db: db, timeZone: .current).today(at: now)
            if today.status.isFastDay, today.fajr != nil {
                var instants = [now]
                for boundary in [today.fajr, today.maghrib].compactMap({ $0 }) where boundary > now {
                    instants.append(boundary)
                }
                return instants.map { FastingEntry(date: $0, state: .religious(today.phase(at: $0))) }
            }
            let startedAt = try FastingSessionStore(db: db).activeIntermittentSession()?.startTimestamp
            return [FastingEntry(date: now, state: .intermittent(startedAt: startedAt))]
        } catch {
            return [FastingEntry(date: now, state: .failed)]
        }
    }
}

struct FastingWidgetView: View {
    let entry: FastingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Fasting", systemImage: "moon.stars.fill")
                .font(.caption).foregroundStyle(.indigo)

            switch entry.state {
            case .failed:
                Spacer()
                Text("Open Almanac to see fasting")
                    .font(.caption).foregroundStyle(.secondary)
            case .religious(let phase):
                religious(phase)
            case .intermittent(let startedAt):
                intermittent(startedAt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func religious(_ phase: ReligiousFastPhase) -> some View {
        switch phase {
        case .beforeFajr(let fajr, _):
            Text("Suhoor").font(.title3).fontWeight(.semibold)
            Text("Fajr \(fajr.formatted(date: .omitted, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            Text(fajr, style: .timer).font(.callout).monospacedDigit()
        case .fasting(_, let maghrib):
            Text("Iftar in").font(.caption).foregroundStyle(.secondary)
            Text(maghrib, style: .timer).font(.title3).fontWeight(.semibold).monospacedDigit()
            Text("Maghrib \(maghrib.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        case .broken(let at, _):
            Text("Fast broken").font(.title3).fontWeight(.semibold)
            Text("at \(at.formatted(date: .omitted, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        case .kept:
            Text("Fast complete").font(.title3).fontWeight(.semibold)
            Text("Kept from Fajr to Maghrib").font(.caption).foregroundStyle(.secondary)
        case .notAFastDay, .prayerTimesUnavailable:
            Text("Open Almanac to set your location")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func intermittent(_ startedAt: Date?) -> some View {
        if let started = startedAt {
            Text(started, style: .timer)
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
}
