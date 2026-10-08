import SwiftUI
import CoreLocation
import AlmanacCore

/// Prayer-time state for the app: the settings row, the cached days a screen
/// shows, and the two ways §12.2 gets coordinates — Core Location, and a city
/// picked from the bundled list.
///
/// **Location is one-shot, and only fed in automatic mode.** The screen used
/// to run `startUpdatingLocation` for as long as the app was in the
/// foreground, which costs battery for a number that changes when the user
/// travels, and it fed every fix into §12.4's travel rule — which clears a
/// manual city. So a user who picked a city because the detected location is
/// not where they want times for had it overwritten on the next foreground. A
/// chosen city now stays chosen until the user taps "Use current location".
@MainActor
final class PrayerModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var settings: PrayerSettings?
    @Published private(set) var today: CachedPrayerTimes?
    @Published private(set) var tomorrow: CachedPrayerTimes?
    @Published private(set) var isLocating = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var error: String?

    /// Called whenever the cached times change, so the fasting state and the
    /// notification schedule that are derived from them follow at once rather
    /// than at the next foreground. Set by `AlmanacApp`.
    var onPrayerTimesChanged: (() -> Void)?

    private var db: Database?
    private let locationManager = CLLocationManager()
    private var isConfigured = false
    /// True while a fix the user asked for is outstanding. That fix is applied
    /// whatever the distance and ends a manual city; a passive one is not.
    private var awaitingRequestedFix = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = locationManager.authorizationStatus
    }

    func configure(db: Database?) {
        guard let db, !isConfigured else { return }
        isConfigured = true
        self.db = db
        refresh()
        ensureCache()
    }

    // MARK: - Cache

    /// §12.3's launch trigger, and the stale-cache repair. Called on every
    /// foreground.
    func ensureCache() {
        guard let db else { return }
        do {
            let settings = try PrayerSettingsStore(db: db).settings()
            let rebuilt = try PrayerTimeEngine.ensureCache(PrayerTimeCacheStore(db: db), settings: settings,
                                                           timeZone: .current, at: Date())
            refresh()
            error = nil
            if rebuilt { onPrayerTimesChanged?() }
        } catch {
            self.error = String(localized: "Prayer times could not be calculated. \(error.localizedDescription)")
        }
    }

    func recalculate() {
        applySettingsChange { _ in }
    }

    func refresh() {
        guard let db else { return }
        do {
            settings = try PrayerSettingsStore(db: db).settings()
            let cache = PrayerTimeCacheStore(db: db)
            let now = Date()
            today = try cache.cachedDay(Self.dayKey(now))
            tomorrow = try cache.cachedDay(Self.dayKey(now.addingTimeInterval(86_400)))
        } catch {
            self.error = String(localized: "Prayer settings could not be read.")
        }
    }

    // MARK: - Settings

    func setCalculationMethod(_ method: String) {
        applySettingsChange { db in
            let current = try PrayerSettingsStore(db: db).settings()
            try PrayerSettingsStore(db: db).updateCalculationMethod(
                method,
                customFajrAngleDeg: method == "custom" ? (current.customFajrAngleDeg ?? 18) : nil,
                customIshaAngleDeg: method == "custom" ? (current.customIshaAngleDeg ?? 17) : nil)
        }
    }

    func setCustomAngles(fajr: Double, isha: Double) {
        applySettingsChange { db in
            try PrayerSettingsStore(db: db).updateCalculationMethod("custom", customFajrAngleDeg: fajr,
                                                                    customIshaAngleDeg: isha)
        }
    }

    func setAsrMethod(_ method: AsrMethod) {
        applySettingsChange { db in try PrayerSettingsStore(db: db).updateAsrMethod(method) }
    }

    func setOffset(_ name: String, minutes: Int) {
        applySettingsChange { db in
            let store = PrayerSettingsStore(db: db)
            switch name {
            case "fajr": try store.updateOffsets(fajr: minutes)
            case "dhuhr": try store.updateOffsets(dhuhr: minutes)
            case "asr": try store.updateOffsets(asr: minutes)
            case "maghrib": try store.updateOffsets(maghrib: minutes)
            case "isha": try store.updateOffsets(isha: minutes)
            default: break
            }
        }
    }

    func setAlertPrayers(_ names: Set<String>) {
        guard let db else { return }
        do {
            try PrayerSettingsStore(db: db).updateAlertPrayers(names)
            refresh()
            onPrayerTimesChanged?()
        } catch {
            self.error = String(localized: "The alert choice could not be saved.")
        }
    }

    /// Writes a setting and recalculates from today (§12.3's first trigger), so
    /// the screen, the fast and the reminders all move together.
    private func applySettingsChange(_ write: (Database) throws -> Void) {
        guard let db else { return }
        do {
            try write(db)
            try PrayerTimeEngine.applySettingsChange(settingsStore: PrayerSettingsStore(db: db),
                                                     cacheStore: PrayerTimeCacheStore(db: db),
                                                     timeZone: .current, at: Date())
            refresh()
            error = nil
            onPrayerTimesChanged?()
        } catch {
            self.error = String(localized: "Prayer times could not be recalculated. \(error.localizedDescription)")
        }
    }

    // MARK: - Location

    func chooseCity(_ city: ManualCity) {
        guard let db else { return }
        awaitingRequestedFix = false
        isLocating = false
        do {
            try PrayerTimeEngine.applyManualCity(city, at: Date(), timeZone: .current,
                                                 settingsStore: PrayerSettingsStore(db: db),
                                                 cacheStore: PrayerTimeCacheStore(db: db))
            refresh()
            error = nil
            onPrayerTimesChanged?()
        } catch {
            self.error = String(localized: "\(city.name) could not be applied. \(error.localizedDescription)")
        }
    }

    /// The user tapped "Use current location": ask for permission if it has not
    /// been asked, then take one fix and apply it as a deliberate choice.
    func requestCurrentLocation() {
        awaitingRequestedFix = true
        error = nil
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            locationManager.requestLocation()
        default:
            awaitingRequestedFix = false
            error = String(localized: "Location access is off for Almanac. Turn it on in Settings, or choose a city below.")
        }
    }

    /// A passive refresh on foreground, for travel (§12.4). Only in automatic
    /// mode, only when already authorized — never a prompt — and one fix, not a
    /// running stream.
    func refreshLocationIfAutomatic() {
        guard let settings, !settings.manualCityOverride else { return }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            break
        }
    }

    /// Kept for the app's background transition; nothing streams any more, so
    /// this only makes sure nothing does.
    func pauseLocation() {
        locationManager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.awaitingRequestedFix {
                    self.isLocating = true
                    self.locationManager.requestLocation()
                }
            case .denied, .restricted:
                if self.awaitingRequestedFix {
                    self.awaitingRequestedFix = false
                    self.isLocating = false
                    self.error = String(localized: "Location access was not allowed. Choose a city below instead.")
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor [weak self] in
            self?.applyLocation(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor [weak self] in
            guard let self else { return }
            let wasRequested = self.awaitingRequestedFix
            self.awaitingRequestedFix = false
            self.isLocating = false
            // A passive refresh that finds nothing is not news; the last known
            // coordinates stay in force (§12.2's third source).
            guard wasRequested else { return }
            self.error = code == .denied
                ? String(localized: "Location access was not allowed. Choose a city below instead.")
                : String(localized: "Your location could not be found just now. Try again, or choose a city below.")
        }
    }

    private func applyLocation(latitude: Double, longitude: Double) {
        guard let db else { return }
        let requested = awaitingRequestedFix
        awaitingRequestedFix = false
        isLocating = false
        do {
            let settingsStore = PrayerSettingsStore(db: db)
            let cacheStore = PrayerTimeCacheStore(db: db)
            if requested {
                try PrayerTimeEngine.applyRequestedLocation(latitude: latitude, longitude: longitude, at: Date(),
                                                            timeZone: .current, settingsStore: settingsStore,
                                                            cacheStore: cacheStore)
            } else {
                // A manual city may have been chosen while this fix was in flight.
                guard try !settingsStore.settings().manualCityOverride else { return }
                guard try PrayerTimeEngine.applyLocationUpdate(latitude: latitude, longitude: longitude, at: Date(),
                                                               timeZone: .current, settingsStore: settingsStore,
                                                               cacheStore: cacheStore) else { return }
            }
            refresh()
            error = nil
            onPrayerTimesChanged?()
        } catch {
            self.error = String(localized: "The new location could not be applied. \(error.localizedDescription)")
        }
    }

    // MARK: - Reading

    /// The prayer still to come, today's or tomorrow's Fajr after Isha.
    func nextPrayer(after now: Date) -> PrayerTime? {
        let candidates = (today?.times ?? []) + (tomorrow?.times ?? [])
        return candidates.first { PrayerTime.obligatoryNames.contains($0.name) && $0.timestamp > now }
    }

    var qiblaBearing: Double? {
        guard let latitude = settings?.latitude, let longitude = settings?.longitude else { return nil }
        return AdhanCalculator.qiblaBearing(latitude: latitude, longitude: longitude)
    }

    static func dayKey(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: instant)
    }
}

/// "in 1 h 12 min", "in 4 min", "now".
func almanacCountdown(to target: Date, from now: Date) -> String {
    let minutes = Int((target.timeIntervalSince(now) / 60).rounded(.up))
    guard minutes > 0 else { return String(localized: "now") }
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return String(localized: "in \(rest) min") }
    return rest == 0 ? String(localized: "in \(hours) h") : String(localized: "in \(hours) h \(rest) min")
}

/// "13 h 30 min".
func almanacDuration(minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return String(localized: "\(rest) min") }
    return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
}

struct PrayerView: View {
    @ObservedObject var model: PrayerModel
    @ObservedObject var notificationModel: NotificationModel
    @State private var alertsEnabled = false

    var body: some View {
        List {
            timesSection
            locationSection
            if model.settings?.hasLocation == true {
                calculationSection
                adjustmentsSection
                alertsSection
            }
            Section {
                Button("Refresh prayer times", systemImage: "arrow.clockwise") {
                    model.recalculate()
                }
            }
            if let error = model.error {
                Section {
                    AlmanacProblemNote(text: error)
                }
            }
        }
        .navigationTitle("Prayer")
        .almanacModuleSurface()
        .onAppear {
            model.ensureCache()
            model.refreshLocationIfAutomatic()
            alertsEnabled = (try? notificationModel.rules().first { $0.type == .prayer }?.isEnabled) ?? false
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var timesSection: some View {
        Section {
            if let today = model.today {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let next = model.nextPrayer(after: context.date)
                    VStack(alignment: .leading, spacing: 4) {
                        if let next {
                            Text("\(PrayerTime.displayName(next.name)) \(almanacCountdown(to: next.timestamp, from: context.date))")
                                .font(AlmanacTypography.font(.sectionTitle))
                                .foregroundStyle(AlmanacPalette.accent)
                                .accessibilityIdentifier("prayer-next")
                            Text(next.timestamp.almanacFormatted(date: next.timestamp > endOfToday ? .abbreviated : .omitted,
                                                          time: .shortened))
                                .font(AlmanacTypography.font(.data).monospacedDigit())
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    ForEach(today.times, id: \.name) { time in
                        prayerRow(time, isNext: next?.name == time.name && next?.timestamp == time.timestamp)
                    }
                    if let next, next.timestamp > endOfToday {
                        prayerRow(next, isNext: true, label: String(localized: "Tomorrow's Fajr"))
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No prayer times yet", systemImage: "sun.horizon")
                } description: {
                    Text(model.settings?.hasLocation == true
                         ? "Prayer times could not be calculated for this location today."
                         : "Use your current location or choose a city to calculate prayer times.")
                }
            }
        } header: {
            Text(todayHeader)
        }
    }

    private func prayerRow(_ time: PrayerTime, isNext: Bool, label: String? = nil) -> some View {
        HStack {
            Text(label ?? PrayerTime.displayName(time.name))
                .font(AlmanacTypography.font(isNext ? .bodyMedium : .body))
                .foregroundStyle(time.name == "sunrise" ? AlmanacPalette.textSecondary : AlmanacPalette.textPrimary)
            Spacer()
            Text(time.timestamp, format: .dateTime.hour().minute())
                .font(AlmanacTypography.font(.data).monospacedDigit())
                .foregroundStyle(isNext ? AlmanacPalette.accent : AlmanacPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer-time-\(time.name)")
    }

    private var endOfToday: Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
    }

    private var todayHeader: String {
        let gregorian = Date().almanacFormatted(date: .complete, time: .omitted)
        guard let hijri = HijriDate(gregorian: PrayerModel.dayKey(Date())) else { return gregorian }
        return "\(gregorian) · \(hijri.text)"
    }

    // MARK: - Location

    @ViewBuilder
    private var locationSection: some View {
        Section {
            if let settings = model.settings, settings.hasLocation {
                LabeledContent("Location", value: locationName(settings))
                    .accessibilityIdentifier("prayer-location")
                LabeledContent("Source", value: settings.manualCityOverride
                               ? String(localized: "Chosen city") : String(localized: "Current location"))
                if let bearing = model.qiblaBearing {
                    LabeledContent("Qibla") {
                        Text("\(Int(bearing.rounded()))° from north, \(compassPoint(bearing))")
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                    }
                }
            }
            Button {
                model.requestCurrentLocation()
            } label: {
                HStack {
                    Label("Use current location", systemImage: "location")
                    if model.isLocating {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isLocating)
            .accessibilityIdentifier("prayer-use-location")
            NavigationLink {
                CityPickerView(model: model)
            } label: {
                Label("Choose a city", systemImage: "building.2")
            }
            .accessibilityIdentifier("prayer-choose-city")
        } header: {
            Text("Location")
        } footer: {
            Text("Prayer times are calculated on this device. A chosen city stays in place until you use your current location again.")
        }
    }

    private func locationName(_ settings: PrayerSettings) -> String {
        if let city = settings.city {
            return [city, settings.country].compactMap { $0 }.joined(separator: ", ")
        }
        guard let lat = settings.latitude, let lon = settings.longitude else { return String(localized: "Not set") }
        let north = String(localized: "N", comment: "North, after a latitude")
        let south = String(localized: "S", comment: "South, after a latitude")
        let east = String(localized: "E", comment: "East, after a longitude")
        let west = String(localized: "W", comment: "West, after a longitude")
        return NumberDisplay.localized(String(format: "%.2f°%@, %.2f°%@", abs(lat), lat >= 0 ? north : south,
                                                abs(lon), lon >= 0 ? east : west))
    }

    private func compassPoint(_ bearing: Double) -> String {
        let points = [String(localized: "north"), String(localized: "north-east"), String(localized: "east"),
                      String(localized: "south-east"), String(localized: "south"), String(localized: "south-west"),
                      String(localized: "west"), String(localized: "north-west")]
        return points[Int(((bearing.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8]
    }

    // MARK: - Calculation

    @ViewBuilder
    private var calculationSection: some View {
        Section {
            Picker("Method", selection: Binding(
                get: { model.settings?.calculationMethod ?? "umm_al_qura" },
                set: { model.setCalculationMethod($0) }
            )) {
                ForEach(PrayerCalculationMethod.storedVocabulary, id: \.value) { method in
                    Text(method.label).tag(method.value)
                }
            }
            .accessibilityIdentifier("prayer-method")
            if model.settings?.calculationMethod == "custom", let settings = model.settings {
                angleStepper(String(localized: "Fajr angle"), value: settings.customFajrAngleDeg ?? 18) {
                    model.setCustomAngles(fajr: $0, isha: settings.customIshaAngleDeg ?? 17)
                }
                angleStepper(String(localized: "Isha angle"), value: settings.customIshaAngleDeg ?? 17) {
                    model.setCustomAngles(fajr: settings.customFajrAngleDeg ?? 18, isha: $0)
                }
            }
            Picker("Asr", selection: Binding(
                get: { AsrMethod(rawValue: model.settings?.asrMethod ?? "standard") ?? .standard },
                set: { model.setAsrMethod($0) }
            )) {
                ForEach(AsrMethod.allCases, id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            .accessibilityIdentifier("prayer-asr")
        } header: {
            Text("Calculation")
        } footer: {
            Text("Umm al-Qura adds 30 minutes to Isha in Ramadan, as Saudi timetables do. Standard Asr is the Shafi'i, Maliki and Hanbali time; Hanafi is later, at two shadow-lengths.")
        }
    }

    private func angleStepper(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: 10...22, step: 0.5) {
            LabeledContent(title) {
                Text("\(AlmanacNumber.compact(value))°").font(AlmanacTypography.font(.data).monospacedDigit())
            }
        }
    }

    // MARK: - Adjustments

    @ViewBuilder
    private var adjustmentsSection: some View {
        Section {
            ForEach(PrayerTime.obligatoryNames, id: \.self) { name in
                let minutes = model.settings?.offsetMinutes(for: name) ?? 0
                Stepper(value: Binding(get: { minutes }, set: { model.setOffset(name, minutes: $0) }),
                        in: -30...30) {
                    LabeledContent(PrayerTime.displayName(name)) {
                        Text(minutes == 0 ? String(localized: "As calculated") : NumberDisplay.localized(String(format: String(localized: "%+d min"), minutes)))
                            .font(AlmanacTypography.font(.data).monospacedDigit())
                            .foregroundStyle(minutes == 0 ? AlmanacPalette.textSecondary : AlmanacPalette.textPrimary)
                    }
                }
                .accessibilityIdentifier("prayer-offset-\(name)")
            }
        } header: {
            Text("Adjustments")
        } footer: {
            Text("Move a prayer by a few minutes to match your mosque or local announcement. The fast follows Fajr and Maghrib as adjusted.")
        }
    }

    // MARK: - Alerts

    @ViewBuilder
    private var alertsSection: some View {
        Section {
            Toggle("Alert at prayer times", isOn: Binding(
                get: { alertsEnabled },
                set: { setAlerts($0) }
            ))
            .accessibilityIdentifier("prayer-alerts")
            if alertsEnabled {
                ForEach(PrayerTime.obligatoryNames, id: \.self) { name in
                    Toggle(PrayerTime.displayName(name), isOn: Binding(
                        get: { model.settings?.alertPrayers.contains(name) ?? true },
                        set: { on in
                            var chosen = model.settings?.alertPrayers ?? Set(PrayerTime.obligatoryNames)
                            if on { chosen.insert(name) } else { chosen.remove(name) }
                            model.setAlertPrayers(chosen)
                        }
                    ))
                    .accessibilityIdentifier("prayer-alert-\(name)")
                }
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text(notificationModel.isAuthorized || !alertsEnabled
                 ? "A notification at each chosen prayer's time. On a fast day, Maghrib's alert is the iftar reminder."
                 : "Almanac is not allowed to send notifications on this device, so nothing will arrive until you allow it.")
        }
    }

    private func setAlerts(_ enabled: Bool) {
        do {
            try notificationModel.setEnabled(enabled, for: .prayer)
            alertsEnabled = enabled
            Task {
                if enabled, !notificationModel.isAuthorized {
                    _ = try? await notificationModel.requestAuthorizationAndSchedule()
                } else {
                    await notificationModel.reconcileNotifications()
                }
            }
        } catch {
            alertsEnabled = !enabled
        }
    }
}

/// The bundled city list (§12.2's manual fallback), searchable by city or
/// country.
struct CityPickerView: View {
    @ObservedObject var model: PrayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(ManualCityCatalog.search(query), id: \.self) { city in
            Button {
                model.chooseCity(city)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Text(city.country)
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                    Spacer()
                    if model.settings?.manualCityOverride == true, model.settings?.city == city.name,
                       model.settings?.country == city.country {
                        Image(systemName: "checkmark").foregroundStyle(AlmanacPalette.accent)
                    }
                }
            }
            .accessibilityIdentifier("city-\(city.name)")
        }
        .searchable(text: $query, prompt: "City or country")
        .navigationTitle("Choose a city")
        .almanacModuleSurface()
    }
}
