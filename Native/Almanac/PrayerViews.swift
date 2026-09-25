import SwiftUI
import CoreLocation
import AlmanacCore

@MainActor
final class PrayerModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var settings: PrayerSettings?
    @Published private(set) var today: CachedPrayerTimes?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var db: Database?
    private let locationManager = CLLocationManager()
    private var isConfigured = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func configure(db: Database?) {
        guard let db, !isConfigured else { return }
        isConfigured = true
        self.db = db
        refresh()
        ensureCache()
    }

    func ensureCache() {
        guard let db else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let settings = try PrayerSettingsStore(db: db).settings()
            // The device's current zone is the location source of truth. The
            // settings row has a legacy default timezone, but it is not a
            // location observation and must not split cache day keys.
            let timeZone = TimeZone.current
            _ = try PrayerTimeEngine.ensureCache(
                PrayerTimeCacheStore(db: db),
                settings: settings,
                timeZone: timeZone,
                at: Date()
            )
            self.settings = settings
            refresh()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func recalculate() {
        guard let db else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let settingsStore = PrayerSettingsStore(db: db)
            let settings = try settingsStore.settings()
            let timeZone = TimeZone.current
            _ = try PrayerTimeEngine.recalculateCache(
                PrayerTimeCacheStore(db: db),
                settings: settings,
                timeZone: timeZone,
                startDate: Date()
            )
            self.settings = settings
            refresh()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func setCalculationMethod(_ method: String) {
        guard let db else { return }
        do {
            try PrayerSettingsStore(db: db).updateCalculationMethod(method)
            recalculate()
        } catch {
            self.error = String(describing: error)
        }
    }

    func requestLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            error = "Location access is disabled. Enable it in Settings to calculate local prayer times."
        }
    }

    func resumeLocationIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    func pauseLocation() {
        locationManager.stopUpdatingLocation()
    }

    func refresh() {
        guard let db else { return }
        do {
            let settingsStore = PrayerSettingsStore(db: db)
            let cache = PrayerTimeCacheStore(db: db)
            settings = try settingsStore.settings()
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            today = try cache.cachedDay(formatter.string(from: Date()))
        } catch {
            self.error = String(describing: error)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.resumeLocationIfAuthorized()
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
        let message = String(describing: error)
        Task { @MainActor [weak self] in
            self?.error = message
        }
    }

    private func applyLocation(latitude: Double, longitude: Double) {
        guard let db else { return }
        do {
            let changed = try PrayerTimeEngine.applyLocationUpdate(
                latitude: latitude,
                longitude: longitude,
                at: Date(),
                timeZone: .current,
                settingsStore: PrayerSettingsStore(db: db),
                cacheStore: PrayerTimeCacheStore(db: db)
            )
            if changed {
                refresh()
                ensureCache()
            }
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct PrayerView: View {
    @ObservedObject var model: PrayerModel

    private let methods = [
        ("umm_al_qura", "Umm al-Qura"),
        ("mwl", "Muslim World League"),
        ("isna", "ISNA"),
        ("egypt", "Egyptian General Authority"),
        ("karachi", "University of Islamic Sciences, Karachi")
    ]

    var body: some View {
        List {
            Section("Today") {
                if let today = model.today {
                    ForEach(today.times, id: \.name) { time in
                        HStack {
                            Text(time.name.capitalized)
                            Spacer()
                            Text(time.timestamp, format: .dateTime.hour().minute())
                                .monospacedDigit()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Prayer times unavailable",
                        systemImage: "sun.horizon",
                        description: Text("Choose a location to calculate prayer times.")
                    )
                }
            }

            Section("Location") {
                if let settings = model.settings, let city = settings.city {
                    LabeledContent("City", value: city)
                } else {
                    Text("No city selected")
                        .foregroundStyle(.secondary)
                }
                Button("Use current location", systemImage: "location") {
                    model.requestLocation()
                }
            }

            Section("Calculation") {
                Picker("Method", selection: Binding(
                    get: { model.settings?.calculationMethod ?? "umm_al_qura" },
                    set: { model.setCalculationMethod($0) }
                )) {
                    ForEach(methods, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                Button("Refresh prayer times", systemImage: "arrow.clockwise") {
                    model.recalculate()
                }
            }

            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Prayer")
        .onAppear {
            model.resumeLocationIfAuthorized()
            model.ensureCache()
        }
        .onDisappear {
            model.pauseLocation()
        }
    }
}
