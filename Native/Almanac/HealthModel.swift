import SwiftUI
import AlmanacCore

/// Owns the inbound HealthKit sync for every read domain, and the Health
/// screen's view of what came back.
///
/// One shared `Database` connection like the other models, configured from
/// `AlmanacApp`. Left without a provider, every method here is a no-op — the app
/// must run normally on a device with no Health permission, and on a simulator
/// with no Health app at all.
@MainActor
final class HealthModel: ObservableObject {
    @Published private(set) var summaries: [HealthSummary] = []
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isSyncing = false
    /// Set when a domain could not be read. Shown rather than swallowed: a
    /// silently dead domain is indistinguishable from one with no data.
    @Published private(set) var problem: String?

    /// The read domains. Water is absent on purpose — `HydrationModel` owns that
    /// domain's sync *and* its write-back, and syncing it from two places would
    /// race on the same anchor.
    static let domains: [HealthDomain] =
        [.sleep, .workouts, .heartRate, .hrv, .steps, .activeEnergy, .restingEnergy,
         .bodyMass, .bodyFatPercentage, .leanBodyMass]

    private var db: Database?
    private var provider: (any HealthProvider)?
    private var sleepBridge: SleepEpisodeHealthBridge?
    private var workoutBridge: WorkoutSessionHealthBridge?
    private var vitalsBridge: VitalsRecordHealthBridge?
    private var bodyBridge: BodyCompositionMeasurementHealthBridge?

    func configure(db: Database?) {
        guard let db, self.db == nil else { return } // already configured
        self.db = db
        let zone = ZoneContext(TimeZone.current)
        let timeModel = TimeModel(timeZone: .current)
        sleepBridge = SleepEpisodeHealthBridge(db: db, timeModel: timeModel, zone: zone)
        workoutBridge = WorkoutSessionHealthBridge(db: db, timeModel: timeModel, zone: zone)
        vitalsBridge = VitalsRecordHealthBridge(db: db, timeModel: timeModel, zone: zone)
        bodyBridge = BodyCompositionMeasurementHealthBridge(db: db, timeModel: timeModel, zone: zone)
        do {
            try vitalsBridge?.reconcileLogicalDays()
            try bodyBridge?.reconcileLogicalDays()
        } catch {
            problem = "Existing health data could not be re-bucketed: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Wires the concrete iOS provider in. Separate from `configure(db:)` so the
    /// Health screen still renders whatever was synced before.
    func configure(provider: any HealthProvider) {
        self.provider = provider
    }

    /// Asks HealthKit for every read domain, plus water so the existing
    /// hydration path keeps working. One sheet, one answer.
    func connect() async throws {
        guard let provider else { return }
        try await provider.requestAuthorisation(for: Self.domains + [.water])
        await syncNow()
    }

    /// Pulls every read domain in. Each domain commits its rows and its own
    /// anchor together, and a domain that fails is skipped rather than allowed
    /// to stop the rest — it keeps its last good anchor and retries next time.
    func syncNow() async {
        guard let db, let provider else { return }
        isSyncing = true
        defer { isSyncing = false }
        problem = nil

        for domain in Self.domains {
            do {
                _ = try await HealthSyncService(db: db, provider: provider,
                                                writer: writer(for: domain),
                                                healthDomain: domain).syncOnce()
            } catch {
                problem = "\(readable(domain.rawValue)) could not be synced: \(error.localizedDescription)"
            }
        }
        lastSynced = Date()
        refresh()
    }

    private func writer(for domain: HealthDomain) -> any HealthSampleWriting {
        switch domain {
        case .sleep: return sleepBridge!
        case .workouts: return workoutBridge!
        case .bodyMass, .bodyFatPercentage, .leanBodyMass: return bodyBridge!
        default: return vitalsBridge!
        }
    }

    func refresh() {
        guard let db, let range = Self.last30Days else { return }
        summaries = (try? HealthSummaryStore(db: db).summaries(in: range)) ?? []
    }

    /// The window the screen reports on. Thirty days is long enough that a
    /// weight or resting-heart-rate trend is visible at a glance and short
    /// enough that "latest" means something recent.
    private static var last30Days: DateRange? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        return DateRange(from: formatter.string(from: start), to: formatter.string(from: end))
    }
}
