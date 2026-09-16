import Foundation

/// User profile data.
public struct UserProfile: Sendable, Hashable {
    public let displayName: String
    public let dateOfBirth: String?
    public let biologicalSex: String?  // e.g., "male", "female", "other"
    public let heightCm: Double?
    public let sports: [String]  // JSON array stored as TEXT
    public let createdAt: String
    public let updatedAt: String

    public init(displayName: String, dateOfBirth: String? = nil, biologicalSex: String? = nil,
                heightCm: Double? = nil, sports: [String] = [], createdAt: String = "", updatedAt: String = "") {
        self.displayName = displayName
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
        self.heightCm = heightCm
        self.sports = sports
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Profile storage over `profile` table. Single-user profile — profile.id is always 1.
public struct ProfileStore: @unchecked Sendable {
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

    public func profile() throws -> UserProfile {
        // Fetch the singleton profile row (id=1)
        if let row = try db.query("""
        SELECT displayName, dateOfBirth, biologicalSex, heightCm, sports, createdAt, updatedAt
        FROM profile WHERE id = 1;
        """).first {
            return rowToProfile(row)
        }
        // If no profile exists, return a default one (should not happen in normal operation)
        return UserProfile(displayName: "User", createdAt: nowText, updatedAt: nowText)
    }

    // MARK: - Write

    /// Update the user's display name.
    public func updateDisplayName(_ name: String) throws {
        try db.run("""
        UPDATE profile SET displayName = ?, updatedAt = ? WHERE id = 1;
        """, [.text(name), .text(nowText)])
    }

    /// Update the user's date of birth (YYYY-MM-DD format).
    public func updateDateOfBirth(_ dob: String?) throws {
        try db.run("""
        UPDATE profile SET dateOfBirth = ?, updatedAt = ? WHERE id = 1;
        """, [dob.map { SQLValue.text($0) } ?? .null, .text(nowText)])
    }

    /// Update the user's biological sex.
    public func updateBiologicalSex(_ sex: String?) throws {
        try db.run("""
        UPDATE profile SET biologicalSex = ?, updatedAt = ? WHERE id = 1;
        """, [sex.map { SQLValue.text($0) } ?? .null, .text(nowText)])
    }

    /// Update the user's height in centimeters.
    public func updateHeight(_ cm: Double?) throws {
        try db.run("""
        UPDATE profile SET heightCm = ?, updatedAt = ? WHERE id = 1;
        """, [cm.map { SQLValue.real($0) } ?? .null, .text(nowText)])
    }

    /// Update the list of sports the user participates in (stored as JSON array).
    public func updateSports(_ sports: [String]) throws {
        let jsonData = try JSONEncoder().encode(sports)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        try db.run("""
        UPDATE profile SET sports = ?, updatedAt = ? WHERE id = 1;
        """, [.text(jsonString), .text(nowText)])
    }

    // MARK: - Private

    private func rowToProfile(_ row: Row) -> UserProfile {
        let sports = (row.string("sports") ?? "[]").decodeJSON() ?? []
        return UserProfile(
            displayName: row.string("displayName") ?? "User",
            dateOfBirth: row.string("dateOfBirth"),
            biologicalSex: row.string("biologicalSex"),
            heightCm: row.double("heightCm"),
            sports: sports,
            createdAt: row.string("createdAt") ?? "",
            updatedAt: row.string("updatedAt") ?? ""
        )
    }
}

// MARK: - JSON Helper Extension

private extension String {
    func decodeJSON<T: Decodable>() -> T? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
