import SwiftUI
import AlmanacCore

@MainActor
final class FastingModel: ObservableObject {
    @Published private(set) var isFastDay = false
    @Published private(set) var session: FastingSession?
    @Published private(set) var prayerTimes: [PrayerTime] = []
    @Published private(set) var nightWindow: NutritionWindow?
    @Published private(set) var error: String?

    private var db: Database?
    private var isConfigured = false

    func configure(db: Database?) {
        guard let db, !isConfigured else { return }
        isConfigured = true
        self.db = db
        ensureToday()
    }

    func ensureToday() {
        guard let db else { return }
        do {
            let now = Date()
            let timeModel = TimeModel(timeZone: .current)
            let day = timeModel.logicalDay(now).value
            let cache = PrayerTimeCacheStore(db: db)
            let cachedToday = try cache.cachedDay(day)
            let nextDay = timeModel.day(after: timeModel.logicalDay(now))?.value
            let cachedNext = try nextDay.flatMap { try cache.cachedDay($0) }
            isFastDay = try ReligiousFastScheduleStore(db: db).isFastDay(day)
            if let cachedToday {
                _ = try ReligiousFastingService.ensureDay(
                    anchorDate: day,
                    prayerTimes: cachedToday.times,
                    scheduleStore: ReligiousFastScheduleStore(db: db),
                    sessionStore: FastingSessionStore(db: db),
                    windowStore: NutritionWindowStore(db: db),
                    nextDayFajr: cachedNext?.times.first(where: { $0.name == "fajr" })?.timestamp,
                    timezoneOffset: TimeZone.current.secondsFromGMT(for: now) / 60,
                    at: now
                )
            }
            refresh()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func refresh() {
        guard let db else { return }
        do {
            let timeModel = TimeModel(timeZone: .current)
            let day = timeModel.logicalDay(Date()).value
            let cache = PrayerTimeCacheStore(db: db)
            prayerTimes = try cache.cachedDay(day)?.times ?? []
            session = try FastingSessionStore(db: db).sessions(for: day)
                .first(where: { $0.sessionType == .religious })
            nightWindow = try NutritionWindowStore(db: db)
                .window(date: day, windowType: "night_nutrition_window")
            isFastDay = try ReligiousFastScheduleStore(db: db).isFastDay(day)
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct FastingView: View {
    @ObservedObject var model: FastingModel

    var body: some View {
        List {
            Section("Today") {
                if model.isFastDay {
                    Label("Religious fast day", systemImage: "moon.stars")
                        .foregroundStyle(.teal)
                } else {
                    Text("No religious fast is scheduled for today")
                        .foregroundStyle(.secondary)
                }

                if let session = model.session {
                    LabeledContent("Session", value: session.isInvalidated ? "Invalidated" : session.isActive ? "Active" : "Ended")
                    LabeledContent("Started", value: session.startTimestamp.formatted(date: .abbreviated, time: .shortened))
                    if let end = session.endTimestamp {
                        LabeledContent("Ended", value: end.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            Section("Prayer window") {
                if model.prayerTimes.isEmpty {
                    Text("Prayer times are not cached yet. Configure location in Prayer first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.prayerTimes, id: \.name) { time in
                        if time.name == "fajr" || time.name == "maghrib" {
                            LabeledContent(time.name.capitalized,
                                           value: time.timestamp.formatted(date: .omitted, time: .shortened))
                        }
                    }
                }
                if let window = model.nightWindow {
                    LabeledContent("Suhoor window ends",
                                   value: window.endTimestamp.formatted(date: .omitted, time: .shortened))
                }
            }

            Section {
                Button("Refresh fasting state", systemImage: "arrow.clockwise") {
                    model.ensureToday()
                }
            }

            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Fasting")
        .task { model.ensureToday() }
    }
}
