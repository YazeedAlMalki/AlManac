import Foundation

/// Applies spec §7.2's assignment rule: on a religious fast day, any entry whose
/// timestamp falls in `Maghrib(D) ≤ t < Fajr(D+1)` carries D's
/// `night_nutrition_window` id in its `nutrition_window_id` column.
///
/// ## Why this writes two other modules' tables
///
/// `nutrition_window_id` lives on `nutrition_log` and `hydration_log`, and it
/// exists *only* to serve this rule — §5.11's column has no other reader. Fasting
/// is also the module that owns the rule and is above both of them in the
/// dependency direction (`FastingAwareNutritionLog`'s doc comment spells that out:
/// "Fasting depends on Nutrition, never the reverse"). So Fasting writes the
/// column, in one place, rather than each store growing a setter that only this
/// one caller would ever invoke. The alternative — a
/// `setNutritionWindow(id:_:)` on each store — would put a fasting concept in two
/// foundational modules to preserve an arrow nothing is actually pointing along.
///
/// ## Why it is not in `NutritionLogStore` either
///
/// The suhoor case is the whole point, and it is invisible from Nutrition's side.
/// A 03:50 entry on calendar day D+1 belongs to *D's* window; matching it needs
/// the window table, which is Fasting's. So the code that knows the answer cannot
/// live in the store that holds the answer's storage.
///
/// ## The predicate is on the instant, never on a date string
///
/// Comparing `logicalDay` to the window's `date` column is the bug this type
/// exists to prevent: a 03:50 suhoor entry has `logicalDay` = D+1 (the global
/// 04:00 boundary is never altered, per §7.2) and belongs to D. Timestamp
/// containment gets it right with no special case, because 03:50 on D+1 really
/// does sit between `Maghrib(D)` and `Fajr(D+1)`.
public struct NightNutritionWindowAssigner: @unchecked Sendable {
    private let db: Database
    private let windows: NutritionWindowStore

    public init(db: Database) {
        self.db = db
        self.windows = NutritionWindowStore(db: db)
    }

    // MARK: - Resolution

    /// The window containing `timestamp`, or nil when the entry falls outside
    /// every one — the ordinary case on an ordinary day.
    ///
    /// Prefers the narrowest match when windows overlap, which is what
    /// `NutritionWindowStore.window(containing:)`'s `ORDER BY startTimestamp
    /// DESC` gives: a night window (Maghrib→Fajr, ~8h) inside a
    /// `standardLogicalDay` (24h) is the specific one. No standard-day window is
    /// ever created today, so the tie-break is currently unreachable — it is
    /// written because the ordering the store already commits to should not
    /// change meaning silently when that case gains a creation rule.
    public func windowID(containing timestamp: Date) throws -> Int64? {
        try windows.window(containing: timestamp)?.id
    }

    // MARK: - Assignment

    /// Assigns a nutrition entry to whichever window contains `eatenAt`.
    ///
    /// **Always writes**, including when the resolution is nil, so that editing
    /// an entry's time from 03:30 (inside the window) to 05:00 (outside it)
    /// clears the assignment rather than leaving a stale id. A conditional
    /// `UPDATE ... WHERE nutrition_window_id IS NULL` would be the cheaper
    /// statement and the wrong one: it makes the column a record of the first
    /// resolution instead of the current one.
    ///
    /// Returns the resolved id, or nil when the entry is not in a window (or no
    /// longer is).
    @discardableResult
    public func assign(nutritionLogID: String, eatenAt: Date) throws -> Int64? {
        try assign(rowID: nutritionLogID, at: eatenAt, in: "nutrition_log")
    }

    /// As `assign(nutritionLogID:eatenAt:)`, for a hydration entry.
    @discardableResult
    public func assign(hydrationLogID: String, loggedAt: Date) throws -> Int64? {
        try assign(rowID: hydrationLogID, at: loggedAt, in: "hydration_log")
    }

    /// Both tables' rows re-resolved against every window that exists now.
    ///
    /// This is spec line 1942 step 6d — "Rebuild nutrition_window assignments for
    /// religious fast days" — the derived-data pass that runs after a restore.
    /// Its scope is the *existing* windows rather than "every religious fast day",
    /// because the window rows are what the restore brings back and a window
    /// cannot be re-derived without prayer times, which is
    /// `ReligiousFastingService`'s job and not this type's.
    ///
    /// **Each window is cleared before it is re-filled, and the clear is what
    /// makes a moved boundary correct.** A window whose times were recalculated
    /// (a location fix, a prayer-time update) has entries that used to be inside
    /// it and no longer are — and those are not findable by querying the rows
    /// inside its *new* span, because by definition they are not there any more.
    /// The only way to see them is to ask which rows point at this window, so
    /// that is what the clear does. Scanning the new span and assigning is not
    /// enough on its own; a NULL-only pass is worse still, since it would
    /// revisit nothing.
    @discardableResult
    public func assignUnassigned() throws -> AssignmentCounts {
        var counts = AssignmentCounts()
        for window in try windows.windows() {
            let result = try assignUnassigned(in: window)
            counts.assigned += result.assigned
            counts.cleared += result.cleared
        }
        return counts
    }

    /// `assignUnassigned()` for one window, identified by its id — the form a
    /// caller has immediately after `NutritionWindowStore.createWindow`, which
    /// already hands the id back.
    ///
    /// Scoped because the whole-history walk is proportional to every window ever
    /// recorded, and marking a day as a fast is a thing the user does often
    /// enough that it cannot cost a full scan. Same clear-then-refill order, same
    /// precision gate, same meaning as the whole-history pass.
    @discardableResult
    public func assignUnassigned(inWindow windowID: Int64) throws -> AssignmentCounts {
        guard let window = try windows.window(id: windowID) else { return AssignmentCounts() }
        return try assignUnassigned(in: window)
    }

    /// The same pass with the window already in hand, so a caller iterating
    /// windows does not read each one back.
    @discardableResult
    public func assignUnassigned(in window: NutritionWindow) throws -> AssignmentCounts {
        var counts = AssignmentCounts()
        counts.cleared += try clear(assignmentsTo: window.id)

        let bounds = DateRange(start: window.startTimestamp, end: window.endTimestamp).utcTextBounds

        // Nutrition: `logged(from:to:)` is the read that already decides placement
        // the way the timeline does, so this pass cannot disagree with what the
        // user sees about when a meal happened. Its own two-day prefilter margin
        // means a window boundary is never the reason an entry is missed.
        for placed in try NutritionLogStore(db: db).logged(from: bounds.start, to: bounds.end) {
            // Only an instant-precise value has a timestamp for §7.2's predicate
            // to be true of. "March 2019" spans the window on paper; whether the
            // meal was eaten during a fast is a different question, and
            // PartialDateTime's own header says so. So the coarse value stays
            // NULL — unassigned, not wrongly assigned.
            guard placed.occurrence.precision == .instant,
                  let instant = placed.occurrence.span?.start else { continue }
            if try assign(nutritionLogID: placed.entry.id, eatenAt: instant) == window.id {
                counts.assigned += 1
            }
        }

        // Hydration: `logged_at` is always a full instant (Migration012's header
        // says so), so there is no precision gate to apply here.
        for entry in try HydrationStore(db: db).logs(from: bounds.start, to: bounds.end) {
            guard let instant = entry.loggedAt.span?.start else { continue }
            if try assign(hydrationLogID: entry.id, loggedAt: instant) == window.id {
                counts.assigned += 1
            }
        }
        return counts
    }

    // MARK: - Private

    /// Drops every assignment naming `windowID`, and reports how many rows it
    /// touched so a caller can see that a rebuild did work even when it assigns
    /// nothing.
    private func clear(assignmentsTo windowID: Int64) throws -> Int {
        var cleared = 0
        for table in ["nutrition_log", "hydration_log"] {
            cleared += try db.run("UPDATE \(table) SET nutrition_window_id = NULL WHERE nutrition_window_id = ?;",
                                  [.integer(windowID)])
        }
        return cleared
    }

    @discardableResult
    private func assign(rowID: String, at timestamp: Date, in table: String) throws -> Int64? {
        let id = try windowID(containing: timestamp)
        // The table name is a literal at every call site above, never caller
        // input — it cannot be a parameter.
        try db.run("UPDATE \(table) SET nutrition_window_id = ? WHERE id = ?;",
                   [id.map { SQLValue.integer($0) } ?? .null, .text(rowID)])
        return id
    }

    /// What one rebuild pass changed, so a caller can log it rather than guess
    /// whether the pass had anything to do.
    public struct AssignmentCounts: Sendable, Hashable {
        /// Entries now pointing at the window the pass was walking.
        public var assigned: Int = 0
        /// Rows whose assignment was dropped, because they are in no window or
        /// no longer in the one they named.
        public var cleared: Int = 0

        public var total: Int { assigned + cleared }
    }
}
