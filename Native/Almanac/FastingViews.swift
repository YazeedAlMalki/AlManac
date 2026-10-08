import SwiftUI
import AlmanacCore

/// Fasting state for the app. Every read and write goes through
/// `FastingCoordinator`, which derives the religious session from the
/// calendar, the prayer cache and the intake log — so this model never decides
/// whether a fast was kept; it asks.
@MainActor
final class FastingModel: ObservableObject {
    /// Today's religious picture (calendar date, not logical day — see
    /// `FastingCoordinator`).
    @Published private(set) var religiousToday: ReligiousFastDay?
    @Published private(set) var tomorrow: ReligiousFastDay?
    @Published private(set) var upcoming: [ReligiousFastDayStatus] = []
    @Published private(set) var nightWindow: NutritionWindow?
    @Published private(set) var nightContents: [FastingIntakeLog.Intake] = []
    @Published private(set) var intermittent: FastingSession?
    @Published private(set) var activeSession: FastingSession?
    @Published private(set) var recent: [FastingSession] = []
    @Published private(set) var suggestionStart: Date?
    /// The Ramadan still to come or under way, for the line under its toggle.
    @Published private(set) var nextRamadan: (start: String, end: String, hijriYear: Int)?
    @Published private(set) var ramadanEnabled = true
    @Published private(set) var monThuEnabled = false
    @Published private(set) var whiteDaysEnabled = false
    @Published private(set) var error: String?

    /// Whether today is a religious fast day. Read by Quick Log to seed the
    /// body-composition conditions.
    var isFastDay: Bool { religiousToday?.status.isFastDay ?? false }

    /// Called after anything here changes fasting state, so the notification
    /// schedule (which mutes reminders during a fast) follows at once. Set by
    /// `AlmanacApp`.
    var onStateChanged: (() -> Void)?

    /// Which kind of fast the screen is about. The owner asked for this to be a
    /// toggle (2026-09-26) rather than the screen silently assuming religious,
    /// because the two are answered by completely different inputs: religious
    /// times come from cached prayer times, intermittent ones come from the user
    /// saying when they last ate.
    ///
    /// Defaults to `.religious` on every launch, as it always has: the UI
    /// acceptance test pins that default, and the religious state is maintained
    /// on launch whichever tab is showing.
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

    private static let suggestionDeclinedKey = "almanac.fasting.suggestionDeclinedUntil"

    private var db: Database?
    private var isConfigured = false

    func configure(db: Database?) {
        guard let db, !isConfigured else { return }
        isConfigured = true
        self.db = db
        ensureToday()
    }

    private var coordinator: FastingCoordinator? {
        db.map { FastingCoordinator(db: $0, timeZone: .current) }
    }

    /// The whole pass: Ramadan's schedule exists, yesterday's and today's fasts
    /// are derived, then everything a screen shows is re-read. Called on every
    /// foreground, after Health sync, after prayer times change and on screen
    /// load.
    func ensureToday() {
        guard let coordinator else { return }
        do {
            try coordinator.refresh()
            error = nil
        } catch {
            self.error = "Fasting state could not be brought up to date. \(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() {
        guard let db, let coordinator else { return }
        do {
            let now = Date()
            let today = try coordinator.today(at: now)
            religiousToday = today
            tomorrow = try coordinator.shift(today.date, by: 1).map { try coordinator.day($0) }
            upcoming = try coordinator.upcoming(after: now, days: 60)
            nightWindow = try coordinator.currentNightWindow(at: now)
            nightContents = try nightWindow.map { try coordinator.contents(of: $0, at: now) } ?? []

            let schedules = ReligiousFastScheduleStore(db: db)
            ramadanEnabled = try schedules.isRamadanEnabled()
            nextRamadan = try schedules.schedules(activeOnly: false)
                .filter { $0.scheduleType == ReligiousFastScheduleStore.ramadan && ($0.endGregorianDate ?? "") >= today.date }
                .min { ($0.startGregorianDate ?? "") < ($1.startGregorianDate ?? "") }
                .flatMap { row in
                    guard let start = row.startGregorianDate, let end = row.endGregorianDate,
                          let year = row.hijriYear else { return nil }
                    return (start, end, year)
                }
            monThuEnabled = try schedules.isRecurringEnabled(ReligiousFastScheduleStore.monThu)
            whiteDaysEnabled = try schedules.isRecurringEnabled(ReligiousFastScheduleStore.whiteDays)

            let sessions = FastingSessionStore(db: db)
            activeSession = try sessions.activeSession()
            intermittent = try sessions.latestIntermittentSession()
            recent = try sessions.recentSessions(limit: 7)

            let declinedUntil = UserDefaults.standard.object(forKey: Self.suggestionDeclinedKey) as? Date
            suggestionStart = (declinedUntil ?? .distantPast) > now
                ? nil : try coordinator.intermittentSuggestionStart(at: now)
        } catch {
            self.error = "Fasting state could not be read. \(error.localizedDescription)"
        }
    }

    // MARK: - Religious choices

    /// Today, by the user's word: a fast, not a fast, or back to the calendar.
    func setToday(isFast: Bool?) {
        guard let coordinator, let date = religiousToday?.date else { return }
        perform { try coordinator.setManualFastDay(date, isFast: isFast, reason: "Set on the Fasting screen") }
    }

    func setRamadan(_ enabled: Bool) {
        guard let coordinator else { return }
        perform { try coordinator.setRamadanEnabled(enabled) }
    }

    func setRecurring(_ scheduleType: String, enabled: Bool) {
        guard let coordinator else { return }
        perform { try coordinator.setRecurringEnabled(scheduleType, enabled: enabled) }
    }

    // MARK: - Intermittent

    /// Starts an intermittent fast that began when the user last ate. This is a
    /// *backdated* start, which is the whole point of the mode: the user is
    /// telling us about a fast already in progress, not tapping "start" as it
    /// begins. No end time — that arrives when they log the meal that broke it,
    /// or when they say so.
    @discardableResult
    func startIntermittent(lastAte: Date, protocolName: String? = nil) -> Int64? {
        guard let db else { return nil }
        if let active = try? FastingSessionStore(db: db).activeSession() {
            error = active.sessionType == .religious
                ? "Today's religious fast is running. An intermittent fast can start after Maghrib."
                : "A fast is already running. End it before starting another."
            return nil
        }
        var id: Int64?
        perform {
            id = try FastingSessionStore(db: db).start(
                FastingSessionDraft(startTimestamp: lastAte, sessionType: .ifPlanned, isDryFast: false,
                                    protocolName: protocolName,
                                    timezoneOffset: TimeZone.current.secondsFromGMT(for: lastAte) / 60),
                logicalDay: TimeModel(timeZone: .current).logicalDay(lastAte).value)
        }
        return id
    }

    /// Closes the active intermittent fast at the moment the user broke it.
    ///
    /// Scoped to intermittent sessions on purpose: a religious fast ends at
    /// Maghrib or at the first intake in the log, and a tap here must not
    /// disagree with that.
    func breakFast(at timestamp: Date) {
        guard let db, let active = try? FastingSessionStore(db: db).activeIntermittentSession() else { return }
        perform { try FastingSessionStore(db: db).endScheduled(id: active.id, at: max(timestamp, active.startTimestamp)) }
    }

    /// §11.1: "Yes" starts an `if_confirmed_suggestion` session from the last
    /// food log.
    func acceptSuggestion() {
        guard let db, let start = suggestionStart else { return }
        perform {
            try FastingSessionStore(db: db).startConfirmedSuggestion(
                lastNutritionLogAt: start,
                logicalDay: TimeModel(timeZone: .current).logicalDay(start).value,
                timezoneOffset: TimeZone.current.secondsFromGMT(for: start) / 60)
        }
    }

    /// §11.1: "No" suppresses re-asking for 4 hours.
    func declineSuggestion() {
        UserDefaults.standard.set(Date().addingTimeInterval(4 * 3600), forKey: Self.suggestionDeclinedKey)
        suggestionStart = nil
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
        onStateChanged?()
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
                     ? "The fast runs from Fajr to Maghrib. Times come from your cached prayer times, and anything you eat or drink after Fajr ends it."
                     : "You say when you last ate. A logged meal or a drink with calories ends the fast; water and black coffee do not.")
            }

            switch model.mode {
            case .religious: religiousBody
            case .intermittent: intermittentBody
            }

            recentSection

            Section {
                Button("Refresh fasting state", systemImage: "arrow.clockwise") {
                    model.ensureToday()
                }
            }

            if let error = model.error {
                Section {
                    AlmanacProblemNote(text: error)
                }
            }
        }
        .navigationTitle("Fasting")
        .almanacModuleSurface()
        .task { model.ensureToday() }
        // Coming back from a screen that logged something: re-read, because a
        // meal or a drink logged there may have ended a fast.
        .onAppear { model.refresh() }
        .onChange(of: model.mode) { _, _ in model.refresh() }
    }

    // MARK: - Religious

    @ViewBuilder
    private var religiousBody: some View {
        if let today = model.religiousToday {
            Section {
                statusLine(today.status)
                if today.status.isFastDay {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        phaseView(today, now: context.date)
                    }
                }
                if !today.prayerTimes.isEmpty {
                    if let fajr = today.fajr {
                        LabeledContent("Fajr", value: fajr.formatted(date: .omitted, time: .shortened))
                    }
                    if let maghrib = today.maghrib {
                        LabeledContent("Maghrib", value: maghrib.formatted(date: .omitted, time: .shortened))
                    }
                    // The number the owner asked to be counted immediately. Nil
                    // rather than a guess when prayer times are missing.
                    if let hours = today.fastLengthHours {
                        LabeledContent("Fasting window") {
                            Text("\(AlmanacNumber.compact((hours * 10).rounded() / 10)) h")
                                .font(AlmanacTypography.font(.data).monospacedDigit())
                        }
                    }
                }
                correctionButton(today.status)
            } header: {
                Text(dayHeader(today.status))
            }

            if let tomorrow = model.tomorrow, tomorrow.status.isFastDay {
                Section("Tomorrow") {
                    statusLine(tomorrow.status)
                    if let fajr = tomorrow.fajr {
                        LabeledContent("Suhoor ends at Fajr", value: fajr.formatted(date: .omitted, time: .shortened))
                    }
                }
            }

            nightWindowSection
            scheduleSection
            upcomingSection
        }
    }

    private func statusLine(_ status: ReligiousFastDayStatus) -> some View {
        Group {
            if status.isFastDay {
                Label(fastReason(status), systemImage: "moon.stars")
                    .foregroundStyle(AlmanacPalette.accent)
            } else {
                Text(status.isCorrected ? "Not a fast day — you marked it" : "No religious fast is scheduled for today")
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
        .font(AlmanacTypography.font(.bodyMedium))
        .accessibilityIdentifier("fasting-status")
    }

    private func fastReason(_ status: ReligiousFastDayStatus) -> String {
        if status.isCorrected { return "Fast day — you marked it" }
        let reasons = status.kinds.map { kind -> String in
            switch kind {
            case .ramadan: return status.hijri.map { "Ramadan, day \($0.day)" } ?? "Ramadan"
            case .monday: return "Monday fast"
            case .thursday: return "Thursday fast"
            case .whiteDay: return "White Day"
            }
        }
        return reasons.isEmpty ? "Religious fast day" : reasons.joined(separator: " · ")
    }

    @ViewBuilder
    private func phaseView(_ today: ReligiousFastDay, now: Date) -> some View {
        switch today.phase(at: now) {
        case .notAFastDay:
            EmptyView()
        case .prayerTimesUnavailable:
            VStack(alignment: .leading, spacing: 8) {
                Text("Prayer times are not cached yet, so the Fajr to Maghrib window cannot be worked out. Set your location in Prayer first.")
                    .foregroundStyle(AlmanacPalette.textSecondary)
                NavigationLink(value: AppRoute.prayer) {
                    Label("Open Prayer", systemImage: "sun.horizon")
                }
            }
        case .beforeFajr(let fajr, _):
            phaseCard(title: "Suhoor time",
                      detail: "The fast begins at Fajr, \(fajr.formatted(date: .omitted, time: .shortened)) — \(almanacCountdown(to: fajr, from: now)).",
                      fraction: nil, tone: .neutral)
        case .fasting(let fajr, let maghrib):
            let total = maghrib.timeIntervalSince(fajr)
            let done = now.timeIntervalSince(fajr)
            phaseCard(title: "Fasting — iftar \(almanacCountdown(to: maghrib, from: now))",
                      detail: "Fasted \(almanacDuration(minutes: Int(done / 60))) of \(almanacDuration(minutes: Int(total / 60))). Maghrib is at \(maghrib.formatted(date: .omitted, time: .shortened)).",
                      fraction: total > 0 ? done / total : nil, tone: .good)
        case .broken(let at, _):
            phaseCard(title: "Fast broken at \(at.formatted(date: .omitted, time: .shortened))",
                      detail: "Something was logged after Fajr. If that entry is wrong, delete or move it and the fast is restored.",
                      fraction: nil, tone: .warning)
        case .kept(let maghrib):
            let minutes = today.session?.finalDurationMinutes
                ?? today.fajr.map { Int(maghrib.timeIntervalSince($0) / 60) } ?? 0
            phaseCard(title: "Fast complete",
                      detail: "Kept from Fajr to Maghrib — \(almanacDuration(minutes: minutes)).",
                      fraction: 1, tone: .good)
        }
    }

    private func phaseCard(title: String, detail: String, fraction: Double?, tone: AlmanacStatusTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AlmanacTypography.font(.sectionTitle))
                .foregroundStyle(tone == .neutral ? AlmanacPalette.textPrimary : tone.color)
            Text(detail)
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary)
            AlmanacMeter(fraction: fraction, tone: tone)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fasting-phase")
    }

    @ViewBuilder
    private func correctionButton(_ status: ReligiousFastDayStatus) -> some View {
        if status.correction != nil {
            Button("Use the calendar for today") { model.setToday(isFast: nil) }
                .accessibilityIdentifier("fasting-clear-correction")
        } else if status.isFastDay {
            Button("I'm not fasting today", role: .destructive) { model.setToday(isFast: false) }
                .accessibilityIdentifier("fasting-not-today")
        } else {
            Button("Mark today as a fast day") { model.setToday(isFast: true) }
                .accessibilityIdentifier("fasting-mark-today")
        }
    }

    private func dayHeader(_ status: ReligiousFastDayStatus) -> String {
        let gregorian = Date().formatted(date: .abbreviated, time: .omitted)
        return status.hijri.map { "Today · \(gregorian) · \($0.text)" } ?? "Today · \(gregorian)"
    }

    @ViewBuilder
    private var nightWindowSection: some View {
        if let window = model.nightWindow {
            Section {
                if model.nightContents.isEmpty {
                    Text("Nothing logged between Maghrib and Fajr yet.")
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(model.nightContents, id: \.id) { intake in
                        HStack {
                            Image(systemName: intake.kind == .drink ? "drop" : "fork.knife")
                                .foregroundStyle(AlmanacPalette.textSecondary)
                            Text(intakeLabel(intake))
                            Spacer()
                            Text(intake.at.formatted(date: .omitted, time: .shortened))
                                .font(AlmanacTypography.font(.data).monospacedDigit())
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                    }
                }
            } header: {
                Text(window.endTimestamp <= Date() ? "Last night" : "Tonight, since Maghrib")
            } footer: {
                Text("Iftar to suhoor, \(window.startTimestamp.formatted(date: .omitted, time: .shortened)) to \(window.endTimestamp.formatted(date: .omitted, time: .shortened)). It counts as one night even past midnight.")
            }
        }
    }

    private func intakeLabel(_ intake: FastingIntakeLog.Intake) -> String {
        switch intake.kind {
        case .drink:
            let name = intake.label ?? "Water"
            return intake.amount.map { "\(name), \(Int($0)) ml" } ?? name
        case .food:
            let name = intake.label ?? "Food"
            return intake.amount.map { "\(name), \(AlmanacNumber.compact($0)) g" } ?? name
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.ramadanEnabled }, set: { model.setRamadan($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ramadan")
                    if let next = model.nextRamadan {
                        // Verbatim: a localized interpolation groups the year as "1,448".
                        Text(verbatim: "\(next.hijriYear) AH: \(displayDate(next.start, withYear: true)) to \(displayDate(next.end, withYear: true))")
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
            }
            .accessibilityIdentifier("fasting-ramadan")
            Toggle("Mondays and Thursdays", isOn: Binding(
                get: { model.monThuEnabled },
                set: { model.setRecurring(ReligiousFastScheduleStore.monThu, enabled: $0) }))
                .accessibilityIdentifier("fasting-mon-thu")
            Toggle("White Days (13th–15th)", isOn: Binding(
                get: { model.whiteDaysEnabled },
                set: { model.setRecurring(ReligiousFastScheduleStore.whiteDays, enabled: $0) }))
                .accessibilityIdentifier("fasting-white-days")
        } header: {
            Text("Fast days")
        } footer: {
            Text("Dates follow the Umm al-Qura calendar. If the moon is announced differently where you are, mark or unmark the day above. Eid and the days of Tashreeq are never fast days.")
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if !model.upcoming.isEmpty {
            Section("Coming up") {
                ForEach(model.upcoming.prefix(7), id: \.date) { status in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayDate(status.date))
                            if let hijri = status.hijri {
                                Text(hijri.text)
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                        Spacer()
                        Text(status.isCorrected ? "Marked" : status.kinds.map(\.label).joined(separator: ", "))
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
            }
        }
    }

    private func displayDate(_ key: String, withYear: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        return withYear
            ? date.formatted(.dateTime.day().month(.abbreviated).year())
            : date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    // MARK: - Intermittent

    @ViewBuilder
    private var intermittentBody: some View {
        if let start = model.suggestionStart {
            Section {
                Text("No calories have been logged for \(Int(Date().timeIntervalSince(start) / 3600)) hours. Are you currently fasting?")
                HStack {
                    Button("Yes, I'm fasting") { model.acceptSuggestion() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("fasting-suggestion-yes")
                    Button("No") { model.declineSuggestion() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("fasting-suggestion-no")
                }
            } header: {
                Text("Suggestion")
            }
        }

        let session = model.intermittent
        Section("Current fast") {
            if let session, session.isActive {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(session.startTimestamp) / 60)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(almanacDuration(minutes: max(0, elapsed)))
                            .font(AlmanacTypography.font(.sectionTitle).monospacedDigit())
                            .foregroundStyle(AlmanacPalette.accent)
                        if let target = targetHours(session.protocolName) {
                            Text("Target \(target) h · \(protocolLabel(session.protocolName))")
                                .font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                            AlmanacMeter(fraction: Double(elapsed) / Double(target * 60), tone: .good)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("fasting-if-elapsed")
                }
                LabeledContent("Started", value: session.startTimestamp.formatted(date: .abbreviated, time: .shortened))
            } else if let session, let end = session.endTimestamp,
                      Date().timeIntervalSince(end) < 24 * 3600 {
                LabeledContent("Started", value: session.startTimestamp.formatted(date: .abbreviated, time: .shortened))
                LabeledContent(session.isInvalidated ? "Invalidated" : "Broken",
                               value: end.formatted(date: .abbreviated, time: .shortened))
                if let minutes = session.finalDurationMinutes, !session.isInvalidated {
                    LabeledContent("Duration") {
                        Text(almanacDuration(minutes: minutes))
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                    }
                }
            } else {
                Text("No intermittent fast is running.")
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }

        Section {
            if let session, session.isActive {
                Button("I broke the fast just now") { model.breakFast(at: Date()) }
                    .accessibilityIdentifier("break-fast-now")
            } else if model.activeSession?.sessionType == .religious {
                Text("Today's religious fast is running. An intermittent fast can start after Maghrib.")
                    .foregroundStyle(AlmanacPalette.textSecondary)
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
            Text(session?.isActive == true ? "End it" : "Start one")
        } footer: {
            Text("Starting from a past time records a fast already in progress. Logging a meal ends it at the meal's time; so does this button.")
        }
    }

    private func targetHours(_ protocolName: String?) -> Int? {
        switch protocolName {
        case "16_8": return 16
        case "18_6": return 18
        case "omad": return 23
        default: return nil
        }
    }

    private func protocolLabel(_ protocolName: String?) -> String {
        switch protocolName {
        case "16_8": return "16:8"
        case "18_6": return "18:6"
        case "omad": return "OMAD"
        default: return "Custom"
        }
    }

    // MARK: - History

    @ViewBuilder
    private var recentSection: some View {
        let finished = model.recent.filter { !$0.isActive }
        if !finished.isEmpty {
            Section("Recent fasts") {
                ForEach(finished, id: \.id) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.sessionType == .religious ? "Religious" : "Intermittent")
                            Text(session.startTimestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                        Spacer()
                        Text(session.isInvalidated ? "Invalidated"
                             : session.finalDurationMinutes.map { almanacDuration(minutes: $0) } ?? "—")
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
            }
        }
    }
}
