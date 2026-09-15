import Foundation

/// Pushes manually-logged hydration entries to HealthKit.
///
/// The queue is `hydration_log.healthkit_synced_at IS NULL`, not a separate
/// table — see `Migration012`'s doc comment. `drainOnce()` mirrors
/// `HealthSyncService`'s discipline in reverse: the write to HealthKit
/// happens outside any SQLite transaction (it is a call to another system),
/// and a row is only ever stamped `healthkit_synced_at` after that write has
/// actually succeeded. A row is processed one at a time so a single failure
/// does not block rows that already succeeded, and a failed row simply stays
/// matched by `idx_hydration_log_pending_writeback` — that predicate is the
/// retry, with no separate bookkeeping needed.
public struct HydrationWriteback: Sendable {
    private let db: Database
    private let writer: any HealthWriter
    private let clock: any Clock

    public init(db: Database, writer: any HealthWriter, clock: any Clock = SystemClock()) {
        self.db = db
        self.writer = writer
        self.clock = clock
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Pushes every unpushed manual entry once. Returns the number of rows
    /// successfully pushed.
    @discardableResult
    public func drainOnce() async throws -> Int {
        let pending = try db.query("""
            SELECT id, amount_ml, logged_at FROM hydration_log
            WHERE source_system = 'manual' AND healthkit_synced_at IS NULL AND deleted_at IS NULL
            ORDER BY logged_at;
            """)

        var pushed = 0
        for row in pending {
            guard let id = row.string("id"), let amount = row.double("amount_ml"),
                  let loggedAtText = row.string("logged_at"),
                  let loggedAt = PartialDateTime(storedText: loggedAtText, precision: .instant, zone: .unknown),
                  let span = loggedAt.span
            else { continue }

            let sample = HealthSample(externalID: id, domain: .water, start: span.start, end: span.start,
                                       value: amount, unit: "ml")
            do {
                let externalID = try await writer.write(sample)
                try db.run("""
                    UPDATE hydration_log SET healthkit_synced_at = ?, healthkit_external_id = ?
                    WHERE id = ?;
                    """, [.text(iso(clock.now)), .text(externalID), .text(id)])
                pushed += 1
            } catch {
                // Leave healthkit_synced_at NULL; the next drainOnce() retries.
                continue
            }
        }
        return pushed
    }
}
