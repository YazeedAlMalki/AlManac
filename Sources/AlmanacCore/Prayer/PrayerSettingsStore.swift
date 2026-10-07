import Foundation

/// `prayer_settings` — a singleton row (§5.22), same pattern as `profile`.
public struct PrayerSettings: Sendable, Hashable {
    public let calculationMethod: String
    public let customFajrAngleDeg: Double?
    public let customIshaAngleDeg: Double?
    public let latitude: Double?
    public let longitude: Double?
    public let city: String?
    public let country: String?
    public let manualCityOverride: Bool
    public let fajrOffsetMin: Int
    public let dhuhrOffsetMin: Int
    public let asrOffsetMin: Int
    public let maghribOffsetMin: Int
    public let ishaOffsetMin: Int
    public let timezone: String
    public let updatedAt: Date
    /// `prayer_settings.asrMethod` (Migration050): `"standard"` or `"hanafi"`.
    public let asrMethod: String
    /// `prayer_settings.alertPrayers` (Migration050), parsed: which of the five
    /// prayers raise an alert when the `prayer` notification rule is on.
    public let alertPrayers: Set<String>

    public init(calculationMethod: String, customFajrAngleDeg: Double?, customIshaAngleDeg: Double?,
                latitude: Double?, longitude: Double?, city: String?, country: String?,
                manualCityOverride: Bool, fajrOffsetMin: Int, dhuhrOffsetMin: Int, asrOffsetMin: Int,
                maghribOffsetMin: Int, ishaOffsetMin: Int, timezone: String, updatedAt: Date,
                asrMethod: String = AsrMethod.standard.rawValue,
                alertPrayers: Set<String> = Set(PrayerTime.obligatoryNames)) {
        self.calculationMethod = calculationMethod
        self.customFajrAngleDeg = customFajrAngleDeg
        self.customIshaAngleDeg = customIshaAngleDeg
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.country = country
        self.manualCityOverride = manualCityOverride
        self.fajrOffsetMin = fajrOffsetMin
        self.dhuhrOffsetMin = dhuhrOffsetMin
        self.asrOffsetMin = asrOffsetMin
        self.maghribOffsetMin = maghribOffsetMin
        self.ishaOffsetMin = ishaOffsetMin
        self.timezone = timezone
        self.updatedAt = updatedAt
        self.asrMethod = asrMethod
        self.alertPrayers = alertPrayers
    }

    /// Whether there is anywhere to calculate prayer times for. False is the
    /// normal state before a user has granted location or picked a city.
    public var hasLocation: Bool { latitude != nil && longitude != nil }

    /// The per-prayer minute offset §5.22 stores, by `prayer_times_cache`
    /// column name. Sunrise has no offset column and is never adjusted.
    public func offsetMinutes(for name: String) -> Int {
        switch name {
        case "fajr": return fajrOffsetMin
        case "dhuhr": return dhuhrOffsetMin
        case "asr": return asrOffsetMin
        case "maghrib": return maghribOffsetMin
        case "isha": return ishaOffsetMin
        default: return 0
        }
    }
}

/// Reading and updating the `prayer_settings` singleton (§5.22, §12.2).
/// Self-healing the same way `ProfileStore` is: every write ensures the
/// id=1 row exists first, since nothing seeds it at migration time.
public struct PrayerSettingsStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Read

    public func settings() throws -> PrayerSettings {
        guard let row = try db.query("""
        SELECT calculationMethod, customFajrAngleDeg, customIshaAngleDeg, latitude, longitude,
               city, country, manualCityOverride, fajrOffsetMin, dhuhrOffsetMin, asrOffsetMin,
               maghribOffsetMin, ishaOffsetMin, timezone, updatedAt, asrMethod, alertPrayers
        FROM prayer_settings WHERE id = 1;
        """).first else {
            // No row yet: the schema's own column defaults (Migration024),
            // mirrored here rather than read from a row that doesn't exist.
            return PrayerSettings(calculationMethod: "umm_al_qura", customFajrAngleDeg: nil,
                                   customIshaAngleDeg: nil, latitude: nil, longitude: nil,
                                   city: nil, country: nil, manualCityOverride: false,
                                   fajrOffsetMin: 0, dhuhrOffsetMin: 0, asrOffsetMin: 0,
                                   maghribOffsetMin: 0, ishaOffsetMin: 0, timezone: "Asia/Riyadh",
                                   updatedAt: clock.now)
        }
        return rowToSettings(row)
    }

    // MARK: - Write

    private func ensureRowExists() throws {
        try db.run("INSERT OR IGNORE INTO prayer_settings (id, updatedAt) VALUES (1, ?);", [.text(nowText)])
    }

    /// `timezone`, when given, is the zone the location keeps its clocks in —
    /// a manual city's own zone, or the device's for a detected fix. Nil leaves
    /// the stored zone alone.
    public func updateLocation(latitude: Double, longitude: Double,
                                city: String?, country: String?, manualCityOverride: Bool,
                                timezone: String? = nil) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE prayer_settings SET latitude = ?, longitude = ?, city = ?, country = ?,
                                    manualCityOverride = ?, updatedAt = ?
        WHERE id = 1;
        """, [
            .real(latitude), .real(longitude),
            city.map { SQLValue.text($0) } ?? .null,
            country.map { SQLValue.text($0) } ?? .null,
            .integer(manualCityOverride ? 1 : 0),
            .text(nowText)
        ])
        if let timezone { try updateTimezone(timezone) }
    }

    /// `"standard"` or `"hanafi"` (`AsrMethod`'s raw values). Anything else is a
    /// caller bug and is refused rather than stored, because an unreadable value
    /// would silently fall back to standard and show a Hanafi user the wrong Asr.
    public func updateAsrMethod(_ method: AsrMethod) throws {
        try ensureRowExists()
        try db.run("UPDATE prayer_settings SET asrMethod = ?, updatedAt = ? WHERE id = 1;",
                   [.text(method.rawValue), .text(nowText)])
    }

    /// Which prayers alert. Names outside the five obligatory prayers are
    /// dropped — sunrise is not a prayer and must not become an alert by a typo.
    public func updateAlertPrayers(_ names: Set<String>) throws {
        try ensureRowExists()
        let kept = PrayerTime.obligatoryNames.filter(names.contains)
        try db.run("UPDATE prayer_settings SET alertPrayers = ?, updatedAt = ? WHERE id = 1;",
                   [.text(kept.joined(separator: ",")), .text(nowText)])
    }

    public func updateCalculationMethod(_ method: String, customFajrAngleDeg: Double? = nil,
                                         customIshaAngleDeg: Double? = nil) throws {
        try ensureRowExists()
        try db.run("""
        UPDATE prayer_settings SET calculationMethod = ?, customFajrAngleDeg = ?, customIshaAngleDeg = ?, updatedAt = ?
        WHERE id = 1;
        """, [
            .text(method),
            customFajrAngleDeg.map { SQLValue.real($0) } ?? .null,
            customIshaAngleDeg.map { SQLValue.real($0) } ?? .null,
            .text(nowText)
        ])
    }

    /// Updates only the offsets passed in; any left `nil` keep their current
    /// stored value.
    public func updateOffsets(fajr: Int? = nil, dhuhr: Int? = nil, asr: Int? = nil,
                               maghrib: Int? = nil, isha: Int? = nil) throws {
        try ensureRowExists()
        let current = try settings()
        try db.run("""
        UPDATE prayer_settings SET fajrOffsetMin = ?, dhuhrOffsetMin = ?, asrOffsetMin = ?,
                                    maghribOffsetMin = ?, ishaOffsetMin = ?, updatedAt = ?
        WHERE id = 1;
        """, [
            .integer(Int64(fajr ?? current.fajrOffsetMin)),
            .integer(Int64(dhuhr ?? current.dhuhrOffsetMin)),
            .integer(Int64(asr ?? current.asrOffsetMin)),
            .integer(Int64(maghrib ?? current.maghribOffsetMin)),
            .integer(Int64(isha ?? current.ishaOffsetMin)),
            .text(nowText)
        ])
    }

    public func updateTimezone(_ timezone: String) throws {
        try ensureRowExists()
        try db.run("UPDATE prayer_settings SET timezone = ?, updatedAt = ? WHERE id = 1;",
                    [.text(timezone), .text(nowText)])
    }

    // MARK: - Private

    private func rowToSettings(_ row: Row) -> PrayerSettings {
        PrayerSettings(
            calculationMethod: row.string("calculationMethod") ?? "umm_al_qura",
            customFajrAngleDeg: row.double("customFajrAngleDeg"),
            customIshaAngleDeg: row.double("customIshaAngleDeg"),
            latitude: row.double("latitude"),
            longitude: row.double("longitude"),
            city: row.string("city"),
            country: row.string("country"),
            manualCityOverride: row.int("manualCityOverride") == 1,
            fajrOffsetMin: Int(row.int("fajrOffsetMin") ?? 0),
            dhuhrOffsetMin: Int(row.int("dhuhrOffsetMin") ?? 0),
            asrOffsetMin: Int(row.int("asrOffsetMin") ?? 0),
            maghribOffsetMin: Int(row.int("maghribOffsetMin") ?? 0),
            ishaOffsetMin: Int(row.int("ishaOffsetMin") ?? 0),
            timezone: row.string("timezone") ?? "Asia/Riyadh",
            updatedAt: row.string("updatedAt").flatMap(iso8601ToDate) ?? Date(),
            asrMethod: row.string("asrMethod") ?? AsrMethod.standard.rawValue,
            alertPrayers: Self.parseAlertPrayers(row.string("alertPrayers"))
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// An absent column (a database read before Migration050) means the
    /// migration's own default: every prayer. An empty string is a real choice
    /// — the user turned every prayer off — and stays empty.
    static func parseAlertPrayers(_ text: String?) -> Set<String> {
        guard let text else { return Set(PrayerTime.obligatoryNames) }
        return Set(text.split(separator: ",").map(String.init)
            .filter(PrayerTime.obligatoryNames.contains))
    }
}
