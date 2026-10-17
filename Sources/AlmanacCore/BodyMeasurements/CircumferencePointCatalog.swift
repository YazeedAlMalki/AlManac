import Foundation

/// One place a tape measure goes: one of the seven built-in points, or one the
/// owner named.
///
/// The built-ins stay as they are because they carry things a free-text point
/// does not: arm and thigh can be measured per side, waist syncs with Apple
/// Health, and each has a typo guard (`plausibleRange`). Owner points are
/// `custom_measurement_definition` rows in centimetres.
public enum CircumferencePoint: Hashable, Sendable, Identifiable {
    case builtIn(BodyMeasurementType)
    case owner(id: Int64, name: String)

    public var id: String {
        switch self {
        case .builtIn(let type): return "builtin.\(type.rawValue)"
        case .owner(let id, _): return "owner.\(id)"
        }
    }

    public var name: String {
        switch self {
        case .builtIn(let type): return type.rawValue.capitalized
        case .owner(_, let name): return name
        }
    }

    public var isBuiltIn: Bool {
        if case .builtIn = self { return true }
        return false
    }
}

/// One line on a point's chart: a side of a sided point, or the whole point.
public struct CircumferenceSeries: Sendable, Hashable {
    public struct Value: Sendable, Hashable {
        public let date: Date
        public let value: Double
    }
    /// Nil for a point measured without sides.
    public let side: BodyMeasurementSide?
    /// Oldest first.
    public let values: [Value]
}

public enum CircumferencePointError: Error, Sendable, Equatable {
    case emptyName
    /// The name is already a point, built-in or owner, compared without case.
    case duplicateName
}

/// The owner's list of circumference points, and each point's history.
///
/// BRD §6.6: custom circumference measurements are owner-priority,
/// "user-definable, charted". The list is the seven built-ins the owner has not
/// hidden, then the owner's own points by name. Hiding a point takes it off the
/// list and out of the logging picker; its readings stay in the record and in
/// its series.
public struct CircumferencePointCatalog: Sendable {
    /// Owner points are stored with this unit; definitions in any other unit
    /// are custom measurements, not circumferences.
    public static let unit = "cm"

    let db: Database

    public init(db: Database) { self.db = db }

    public func points() throws -> [CircumferencePoint] {
        let hidden = try hiddenBuiltIns()
        let builtIns = BodyMeasurementType.allCases.filter { !hidden.contains($0) }.map(CircumferencePoint.builtIn)
        return builtIns + (try ownerPoints())
    }

    public func ownerPoints() throws -> [CircumferencePoint] {
        try CustomMeasurementStore(db: db).definitions()
            .filter { $0.unit == Self.unit }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { CircumferencePoint.owner(id: $0.id, name: $0.name) }
    }

    public func hiddenBuiltIns() throws -> Set<BodyMeasurementType> {
        Set(try db.query("SELECT measurement_type FROM circumference_point_hidden;")
            .compactMap { $0.string("measurement_type").flatMap(BodyMeasurementType.init(rawValue:)) })
    }

    public func setHidden(_ type: BodyMeasurementType, _ hidden: Bool) throws {
        if hidden {
            try db.run("""
            INSERT INTO circumference_point_hidden (measurement_type, hidden_at) VALUES (?, ?)
            ON CONFLICT(measurement_type) DO NOTHING;
            """, [.text(type.rawValue), .text(ISO8601DateFormatter().string(from: Date()))])
        } else {
            try db.run("DELETE FROM circumference_point_hidden WHERE measurement_type = ?;",
                       [.text(type.rawValue)])
        }
    }

    @discardableResult
    public func addPoint(name raw: String) throws -> CircumferencePoint {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CircumferencePointError.emptyName }
        let taken = BodyMeasurementType.allCases.map(\.rawValue)
            + (try CustomMeasurementStore(db: db).definitions().map(\.name))
        guard !taken.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw CircumferencePointError.duplicateName
        }
        let id = try CustomMeasurementStore(db: db).createDefinition(name: name, unit: Self.unit)
        return .owner(id: id, name: name)
    }

    /// Logs one reading. A built-in point goes through `BodyMeasurementStore`,
    /// with its side rule and typo guard; an owner point through
    /// `CustomMeasurementStore`, which only requires a positive number.
    public func log(to point: CircumferencePoint, valueCm: Double, at date: Date,
                    side: BodyMeasurementSide? = nil, note: String? = nil,
                    allowUnusualValue: Bool = false,
                    timeModel: TimeModel = TimeModel(timeZone: .current)) throws {
        switch point {
        case .builtIn(let type):
            try BodyMeasurementStore(db: db, timeModel: timeModel).log(
                BodyMeasurementDraft(measuredAt: date, measurementType: type, side: side,
                                     valueCm: valueCm, note: note),
                allowUnusualValue: allowUnusualValue)
        case .owner(let id, _):
            guard valueCm.isFinite, valueCm > 0 else { throw BodyMeasurementError.invalidValue }
            try CustomMeasurementStore(db: db).log(
                CustomMeasurementLogDraft(definitionId: id, value: valueCm, timestamp: date, notes: note,
                                          timezoneOffset: timeModel.timeZone.secondsFromGMT(for: date) / 60,
                                          timezoneIdentifier: timeModel.timeZone.identifier),
                logicalDay: timeModel.logicalDay(date).value)
        }
    }

    /// The point's readings between two instants, one series per side for a
    /// sided point (unsided readings as their own series), oldest first.
    public func series(for point: CircumferencePoint, from: Date, to: Date) throws -> [CircumferenceSeries] {
        switch point {
        case .builtIn(let type):
            let rows = try BodyMeasurementStore(db: db).entries(from: from, to: to)
                .filter { $0.measurementType == type }
                .sorted { $0.measuredAt < $1.measuredAt }
            let sides: [BodyMeasurementSide?] = [.left, .right, nil]
            return sides.compactMap { side in
                let values = rows.filter { $0.side == side }
                    .map { CircumferenceSeries.Value(date: $0.measuredAt, value: $0.valueCm) }
                return values.isEmpty ? nil : CircumferenceSeries(side: side, values: values)
            }
        case .owner(let id, _):
            let values = try CustomMeasurementStore(db: db)
                .history(definitionId: id, from: "0000-01-01", to: "9999-12-31")
                .filter { $0.timestamp >= from && $0.timestamp < to }
                .map { CircumferenceSeries.Value(date: $0.timestamp, value: $0.value) }
            return values.isEmpty ? [] : [CircumferenceSeries(side: nil, values: values)]
        }
    }
}
