import Foundation

public enum BodyMeasurementType: String, CaseIterable, Sendable, Codable {
    case waist, chest, hips, neck, arm, thigh, calf

    public var supportsSides: Bool { self == .arm || self == .thigh }

    /// Draft M8 defaults, awaiting owner confirmation (OI-5). Warning only.
    public var plausibleRange: ClosedRange<Double> {
        switch self {
        case .waist: return 40...200
        case .chest, .hips: return 50...200
        case .neck, .calf: return 20...60
        case .arm: return 15...70
        case .thigh: return 25...100
        }
    }
}

public enum BodyMeasurementSide: String, CaseIterable, Sendable, Codable {
    case left, right
}

public enum BodyMeasurementSource: String, Sendable, Codable {
    case manual, healthkit
}

public struct BodyMeasurementDraft: Sendable {
    public var measuredAt: Date
    public var measurementType: BodyMeasurementType
    public var side: BodyMeasurementSide?
    public var valueCm: Double
    public var note: String?

    public init(measuredAt: Date, measurementType: BodyMeasurementType,
                side: BodyMeasurementSide? = nil, valueCm: Double, note: String? = nil) {
        self.measuredAt = measuredAt
        self.measurementType = measurementType
        self.side = side
        self.valueCm = valueCm
        self.note = note
    }
}

public struct BodyMeasurement: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let measuredAt: Date
    public let logicalDay: String
    public let measurementType: BodyMeasurementType
    public let side: BodyMeasurementSide?
    public let valueCm: Double
    public let source: BodyMeasurementSource
    public let sourceIdentifier: String?
    public let note: String?
    public let isEdited: Bool
}

public enum BodyMeasurementError: Error, LocalizedError {
    case invalidValue, invalidSide, unusuallySized, notManual

    public var errorDescription: String? {
        switch self {
        case .invalidValue: return "Enter a finite, positive circumference in cm."
        case .invalidSide: return "Choose a side for arm or thigh when side tracking is on; otherwise leave it unset."
        case .unusuallySized: return "That looks unusually low or high. Save anyway?"
        case .notManual: return "Only manual measurements can be corrected here."
        }
    }
}

/// DrinkEntryStore's draft/log/entry/day-query shape, with day assignment owned by TimeModel.
public struct BodyMeasurementStore: Sendable {
    let db: Database
    private let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel = TimeModel(timeZone: .current)) {
        self.db = db
        self.timeModel = timeModel
    }

    @discardableResult
    public func log(_ draft: BodyMeasurementDraft, allowUnusualValue: Bool = false) throws -> Int64 {
        try validateValue(draft.valueCm, type: draft.measurementType, allowUnusualValue: allowUnusualValue)
        let trackSides = try ProfileStore(db: db).profile().bodyMeasurementTrackSides
        let needsSide = draft.measurementType.supportsSides && trackSides
        guard needsSide == (draft.side != nil) else { throw BodyMeasurementError.invalidSide }
        return try db.transaction {
            try db.run("""
            INSERT INTO body_measurement
                (measured_at, logical_day, measurement_type, side, value_cm, source, note)
            VALUES (?, ?, ?, ?, ?, 'manual', ?);
            """, [.text(ISO8601DateFormatter().string(from: draft.measuredAt)),
                  .text(timeModel.logicalDay(draft.measuredAt).value), .text(draft.measurementType.rawValue),
                  draft.side.map { .text($0.rawValue) } ?? .null, .real(draft.valueCm),
                  draft.note.map(SQLValue.text) ?? .null])
            return try db.query("SELECT last_insert_rowid() AS id;").first!.int("id")!
        }
    }

    /// Corrections retain the original point, side and instant, including sides saved before toggle-off.
    public func edit(id: Int64, valueCm: Double, note: String?, allowUnusualValue: Bool = false) throws {
        guard let entry = try entry(id: id), entry.source == .manual else { throw BodyMeasurementError.notManual }
        try validateValue(valueCm, type: entry.measurementType, allowUnusualValue: allowUnusualValue)
        try db.run("UPDATE body_measurement SET value_cm = ?, note = ?, is_edited = 1 WHERE id = ?;",
                   [.real(valueCm), note.map(SQLValue.text) ?? .null, .integer(id)])
    }

    public func delete(id: Int64) throws {
        guard let entry = try entry(id: id), entry.source == .manual else { throw BodyMeasurementError.notManual }
        try db.run("DELETE FROM body_measurement WHERE id = ?;", [.integer(id)])
    }

    public func entry(id: Int64) throws -> BodyMeasurement? {
        try db.query("SELECT * FROM body_measurement WHERE id = ?;", [.integer(id)]).first.flatMap(rowToEntry)
    }

    public func entries(for logicalDay: String) throws -> [BodyMeasurement] {
        try db.query("SELECT * FROM body_measurement WHERE logical_day = ? ORDER BY measured_at, id;",
                     [.text(logicalDay)]).compactMap(rowToEntry)
    }

    public func entries(from: Date, to: Date) throws -> [BodyMeasurement] {
        let iso = ISO8601DateFormatter()
        return try db.query("""
            SELECT * FROM body_measurement WHERE measured_at >= ? AND measured_at < ? ORDER BY measured_at, id;
            """, [.text(iso.string(from: from)), .text(iso.string(from: to))]).compactMap(rowToEntry)
    }

    public func recentEntries(limit: Int = 100) throws -> [BodyMeasurement] {
        try db.query("SELECT * FROM body_measurement ORDER BY measured_at DESC, id DESC LIMIT ?;",
                     [.integer(Int64(max(0, limit)))]).compactMap(rowToEntry)
    }

    private func validateValue(_ value: Double, type: BodyMeasurementType, allowUnusualValue: Bool) throws {
        guard value.isFinite, value > 0 else { throw BodyMeasurementError.invalidValue }
        guard allowUnusualValue || type.plausibleRange.contains(value) else { throw BodyMeasurementError.unusuallySized }
    }

    private func rowToEntry(_ row: Row) -> BodyMeasurement? {
        guard let id = row.int("id"),
              let measuredAt = row.string("measured_at").flatMap({ ISO8601DateFormatter().date(from: $0) }),
              let day = row.string("logical_day"),
              let type = row.string("measurement_type").flatMap(BodyMeasurementType.init(rawValue:)),
              let source = row.string("source").flatMap(BodyMeasurementSource.init(rawValue:)),
              let value = row.double("value_cm") else { return nil }
        return BodyMeasurement(id: id, measuredAt: measuredAt, logicalDay: day, measurementType: type,
                               side: row.string("side").flatMap(BodyMeasurementSide.init(rawValue:)),
                               valueCm: value, source: source, sourceIdentifier: row.string("source_identifier"),
                               note: row.string("note"), isEdited: row.int("is_edited") == 1)
    }
}
