import Foundation

/// Which synced source wins when two of them disagree about the same fact.
///
/// Asked for by the owner on 2026-09-26, in answer to the question this repo
/// had flagged as blocking any Whoop/Fitbit work: *"a decision about which
/// source wins when Whoop and HealthKit disagree about sleep — user gets to
/// pick when setting up their profile and can change it later from settings."*
///
/// The decision is the owner's to make, per-domain, because there is no
/// defensible default. HealthKit and a dedicated wearable will not agree about
/// sleep staging — they use different sensors and different epoch definitions —
/// and a blanket "prefer the specialist" or "prefer the phone" is wrong for at
/// least one domain. So the preference is stored per domain and the user can
/// change it whenever a source turns out to be wrong for them.
///
/// ## What this is and is not
///
/// This is the **conflict-resolution layer**, and it is deliberately usable
/// before any second source exists. Today `healthkit` and `manual` are the only
/// `source` values in the database, so this preference currently has nothing to
/// arbitrate — which is exactly why it can be built and tested now, and why
/// building it is not the same as claiming Whoop support exists. It does not.
///
/// What it does do is make the rule explicit and inspectable instead of
/// implicit: when a second bridge lands, it reads this and the arbitration is
/// a lookup rather than a fresh product argument.
///
/// `preferred` is nil-able per domain so a newly added domain is *undecided*
/// rather than silently defaulting to one side. An undecided domain is
/// reported as such, which is the honest state for a question the user has not
/// been asked yet.
public enum SyncDomain: String, Sendable, Hashable, CaseIterable, Codable {
    case sleep
    case heartRate
    case hrv
    case steps
    case energy
    case bodyComposition
    case workouts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .heartRate: return "Heart rate"
        case .hrv: return "Heart rate variability"
        case .steps: return "Steps"
        case .energy: return "Energy"
        case .bodyComposition: return "Body composition"
        case .workouts: return "Workouts"
        }
    }
}

/// One source that can supply a domain's data. Kept as a raw string rather than
/// an enum so adding a provider is a data change, not a migration — which
/// matters because the second provider does not exist yet and its identity
/// (`"whoop"`, `"fitbit"`, …) is not something to hard-code in a closed enum.
public struct SyncSource: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    /// Apple's HealthKit. Always available — it is the platform, and the three
    /// shipped bridges all write `source = "healthkit"`.
    public static let healthKit = SyncSource(id: "healthkit", title: "Apple Health")
    /// A row the user typed in. Never arbitrated *against* a synced source by
    /// this preference: a manual entry is a deliberate claim, not a reading, and
    /// silently discarding it because a watch disagreed would lose data the
    /// user entered on purpose.
    public static let manual = SyncSource(id: "manual", title: "Entered by hand")

    public static let builtIn: [SyncSource] = [.healthKit, .manual]
}

/// Per-domain source preference, persisted in `sync_source_preference`.
///
/// `domain` is the primary key: exactly one winning source per domain, which is
/// the whole shape of the decision. Re-picking overwrites, so "change it later"
/// is an update rather than a second row.
public struct SyncSourcePreferenceStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: clock.now)
    }

    /// The source that wins for `domain`, or nil when the user has not been
    /// asked yet. Nil is a real answer — it means "undecided" — and callers
    /// must not read it as a default.
    public func preferredSource(for domain: SyncDomain) throws -> SyncSource? {
        guard let raw = try db.query(
            "SELECT sourceId FROM sync_source_preference WHERE domain = ?;", [.text(domain.rawValue)]
        ).first?.string("sourceId") else { return nil }
        return SyncSource(id: raw, title: title(forSourceId: raw))
    }

    /// Every domain's preference, including the undecided ones, so the settings
    /// screen can show the whole picture rather than only what has been set.
    public func allPreferences() throws -> [SyncDomain: SyncSource] {
        var out: [SyncDomain: SyncSource] = [:]
        for row in try db.query("SELECT domain, sourceId FROM sync_source_preference;") {
            guard let domainRaw = row.string("domain"),
                  let domain = SyncDomain(rawValue: domainRaw),
                  let sourceRaw = row.string("sourceId") else { continue }
            out[domain] = SyncSource(id: sourceRaw, title: title(forSourceId: sourceRaw))
        }
        return out
    }

    public func setPreferredSource(_ source: SyncSource, for domain: SyncDomain) throws {
        try db.run("""
        INSERT INTO sync_source_preference (domain, sourceId, updatedAt)
        VALUES (?, ?, ?)
        ON CONFLICT(domain) DO UPDATE SET
            sourceId  = excluded.sourceId,
            updatedAt = excluded.updatedAt;
        """, [.text(domain.rawValue), .text(source.id), .text(nowText)])
    }

    /// Clears a decision, returning the domain to "undecided". Offered because
    /// a preference set before a second source existed may not be what the user
    /// wants once it does.
    public func clearPreference(for domain: SyncDomain) throws {
        try db.run("DELETE FROM sync_source_preference WHERE domain = ?;", [.text(domain.rawValue)])
    }

    private func title(forSourceId id: String) -> String {
        SyncSource.builtIn.first { $0.id == id }?.title ?? id
    }
}
