import Foundation

/// Persists `AchievementEngine` output, one row per (day, badge). Every
/// badge gets a row — met or not — so recomputing a day (BRD §6.17: "on
/// edit/delete") is a plain upsert per badge rather than a diff against
/// whatever used to be earned.
public struct AchievementRecordStore: @unchecked Sendable {
    let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func recompute(logicalDay: String, earned: Set<AchievementBadge>) throws {
        for badge in AchievementBadge.allCases {
            try db.run("""
            INSERT OR REPLACE INTO achievement_record (logicalDay, badgeType, metThreshold)
            VALUES (?, ?, ?);
            """, [
                .text(logicalDay),
                .text(badge.rawValue),
                .integer(earned.contains(badge) ? 1 : 0)
            ])
        }
    }

    public func metBadges(for logicalDay: String) throws -> Set<AchievementBadge> {
        let rows = try db.query("""
        SELECT badgeType FROM achievement_record WHERE logicalDay = ? AND metThreshold = 1;
        """, [.text(logicalDay)])
        return Set(rows.compactMap { $0.string("badgeType").flatMap(AchievementBadge.init(rawValue:)) })
    }
}
