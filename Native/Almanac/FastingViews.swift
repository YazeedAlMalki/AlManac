import SwiftUI
import AlmanacCore

@MainActor
final class FastingModel: ObservableObject {
    @Published private(set) var isFastDay = false
    @Published private(set) var session: FastingSession?
    @Published private(set) var prayerTimes: [PrayerTime] = []
    @Published private(set) var nightWindow: NutritionWindow?
    @Published private(set) var error: String?

    /// Which kind of fast the user is running. The owner asked for this to be a
    /// toggle (2026-09-26) rather than the screen silently assuming religious,
    /// because the two are answered by completely different inputs: religious
    /// times come from cached prayer times, intermittent ones come from the user
    /// saying when they last ate.
    ///
    /// Defaults to `.religious` because that is what the screen did before, and
    /// because `ReligiousFastingService` already runs on app launch — flipping
    /// the default would silently stop maintaining today's religious session.
    @Published var mode: FastingMode = .religious

    enum FastingMode: String, CaseIterable, Identifiable {
        case religious
        case intermittent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .religious: return "Religious"
            case .intermittent: return "Intermittent"
            }
        }
    }

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

    /// The session for the mode currently selected. Religious and intermittent
    /// are different rows, not two views of one, so switching the toggle swaps
    /// which one this screen is about rather than merging them.
    func currentSession(for day: String) -> FastingSession? {
        guard let db else { return nil }
        let wanted: FastingSessionType = mode == .religious ? .religious : .ifPlanned
        return try? FastingSessionStore(db: db).sessions(for: day)
            .first { $0.sessionType == wanted }
    }

    /// Fajr→Maghrib for today, which is the religious fasting window. Nil when
    /// prayer times are not cached — the screen says so rather than showing a
    /// fabricated window, because a wrong fast window is exactly the kind of
    /// invented precision this app refuses elsewhere.
    var religiousWindowHours: Double? {
        guard let fajr = prayerTimes.first(where: { $0.name == "fajr" })?.timestamp,
              let maghrib = prayerTimes.first(where: { $0.name == "maghrib" })?.timestamp
        else { return nil }
        return maghrib.timeIntervalSince(fajr) / 3600
    }

    /// Starts an intermittent fast that began when the user last ate. This is a
    /// *backdated* start, which is the whole point of the mode: the user is
    /// telling us about a fast already in progress, not tapping "start" as it
    /// begins. No end time — that arrives either when they log the meal that
    /// broke it, or when they say so.
    @discardableResult
    func startIntermittent(lastAte: Date, protocolName: String? = nil) -> Int64? {
        guard let db else { return nil }
        do {
            let timeModel = TimeModel(timeZone: .current)
            let day = timeModel.logicalDay(lastAte).value
            let id = try FastingSessionStore(db: db).start(
                FastingSessionDraft(startTimestamp: lastAte,
                                    sessionType: .ifPlanned,
                                    isDryFast: false,
                                    protocolName: protocolName,
                                    timezoneOffset: TimeZone.current.secondsFromGMT(for: lastAte) / 60),
                logicalDay: day)
            refresh()
            error = nil
            return id
        } catch {
            self.error = String(describing: error)
            return nil
        }
    }

    /// Closes the active intermittent fast at the moment the user broke it.
    ///
    /// Scoped to `.ifPlanned` on purpose: a religious fast has its own end
    /// rule, driven by prayer times and by which nutrition entries are
    /// calorie-bearing. Letting this button close one would let a tap here
    /// disagree with `ReligiousFastingService`'s own arithmetic.
    func breakFast(at timestamp: Date) {
        guard let db,
              let active = try? FastingSessionStore(db: db).activeSession(),
              active.sessionType == .ifPlanned else { return }
        do {
            try FastingSessionStore(db: db).endScheduled(id: active.id, at: timestamp)
            refresh()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct FastingView: View {
    @ObservedObject var model: FastingModel
    @State private var lastAte = Date().addingTimeInterval(-12 * 3600)
    @State private var protocolName: String?

    var body: some View {
        List {
            Section {
                Picker("Fasting", selection: $model.mode) {
                    ForEach(FastingModel.FastingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("fasting-mode")
            } footer: {
                Text(model.mode == .religious
                     ? "The fast runs from Fajr to Maghrib. Times come from your cached prayer times."
                     : "You say when you last ate and when you broke the fast. Nothing is inferred from prayer times.")
            }

            switch model.mode {
            case .religious: religiousBody
            case .intermittent: intermittentBody
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
        .almanacModuleSurface()
        .task { model.ensureToday() }
        .onChange(of: model.mode) { _, _ in model.refresh() }
    }

    // MARK: - Religious

    @ViewBuilder
    private var religiousBody: some View {
        Section("Today") {
            if model.isFastDay {
                Label("Religious fast day", systemImage: "moon.stars")
                    .foregroundStyle(AlmanacPalette.accent)
            } else {
                Text("No religious fast is scheduled for today")
                    .foregroundStyle(.secondary)
            }
            if let session = model.currentSession(for: todayDay) {
                LabeledContent("Session", value: session.isInvalidated ? "Invalidated" : session.isActive ? "Active" : "Ended")
                LabeledContent("Started", value: session.startTimestamp.formatted(date: .abbreviated, time: .shortened))
                if let end = session.endTimestamp {
                    LabeledContent("Ended", value: end.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }

        Section {
            if model.prayerTimes.isEmpty {
                Text("Prayer times are not cached yet. Configure location in Prayer first.")
                    .foregroundStyle(.secondary)
            } else {
                if let fajr = model.prayerTimes.first(where: { $0.name == "fajr" }),
                   let maghrib = model.prayerTimes.first(where: { $0.name == "maghrib" }) {
                    LabeledContent("Fajr", value: fajr.timestamp.formatted(date: .omitted, time: .shortened))
                    LabeledContent("Maghrib", value: maghrib.timestamp.formatted(date: .omitted, time: .shortened))
                }
                // The number the owner asked to be counted immediately. Nil
                // rather than a guess when prayer times are missing.
                if let hours = model.religiousWindowHours {
                    LabeledContent("Fasting window") {
                        Text("\(AlmanacNumber.compact(hours)) h")
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                    }
                }
            }
            if let window = model.nightWindow {
                LabeledContent("Suhoor window ends",
                               value: window.endTimestamp.formatted(date: .omitted, time: .shortened))
            }
        } header: {
            Text("Fajr to Maghrib")
        }
    }

    // MARK: - Intermittent

    @ViewBuilder
    private var intermittentBody: some View {
        let session = model.currentSession(for: todayDay)
        Section("Current fast") {
            if let session = model.currentSession(for: todayDay) {
                LabeledContent("Started", value: session.startTimestamp.formatted(date: .abbreviated, time: .shortened))
                if let end = session.endTimestamp {
                    LabeledContent("Broken", value: end.formatted(date: .abbreviated, time: .shortened))
                    if let minutes = session.finalDurationMinutes {
                        LabeledContent("Duration") {
                            Text(durationLabel(minutes))
                                .font(AlmanacTypography.font(.data).monospacedDigit())
                        }
                    }
                } else if session.isActive {
                    LabeledContent("Status", value: "In progress")
                }
            } else {
                Text("No intermittent fast recorded today.")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            if let session = model.currentSession(for: todayDay), session.isActive {
                Button("I broke the fast just now") { model.breakFast(at: Date()) }
                    .accessibilityIdentifier("break-fast-now")
            } else {
                DatePicker("I last ate at", selection: $lastAte, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("last-ate-at")
                Picker("Protocol", selection: $protocolName) {
                    Text("Not set").tag(String?.none)
                    Text("16:8").tag(String?.some("16_8"))
                    Text("18:6").tag(String?.some("18_6"))
                    Text("OMAD").tag(String?.some("omad"))
                }
                Button("Start fasting from that time") {
                    model.startIntermittent(lastAte: lastAte, protocolName: protocolName)
                }
                .accessibilityIdentifier("start-intermittent")
            }
        } header: {
            Text(session == nil ? "Start one" : "End it")
        } footer: {
            Text("Starting from a past time records a fast already in progress. The end is whatever you say it is — nothing here watches for your next meal.")
        }
    }

    private var todayDay: String {
        TimeModel(timeZone: .current).logicalDay(Date()).value
    }

    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
    }
}
