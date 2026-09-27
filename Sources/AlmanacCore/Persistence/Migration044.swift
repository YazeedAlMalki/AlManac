import Foundation

/// Migration 044 — `nutrition_window_id` on `nutrition_log` and `hydration_log`.
///
/// Spec §5.11 (line 397) gives `nutrition_log.nutritionWindowId` and §7.2 gives
/// the rule it serves. Migration024's header left the column out of both
/// tables deliberately: adding a column that serves religious fasting to two
/// foundational tables is a cross-module change, and Nutrition and Hydration
/// should not gain it in the same pass that builds Fasting's own tables. This
/// is that pass, and it is a separate migration precisely so neither slice had
/// to know about the other while building.
///
/// **The spec contradicts itself here, and the contradiction is recorded rather
/// than quietly resolved.** §5.11's `nutrition_log` has the column; §5.13's
/// `hydration_log` does not. But §7.2's rule is explicit that "any NutritionLog
/// *or HydrationLog* with `Maghrib(D) ≤ timestamp < Fajr(D+1)` is assigned to
/// this window (via nutritionWindowId)". A dry fast is opened by water, and the
/// night window exists precisely to hold suhoor and iftar, so leaving
/// `hydration_log` without the column would make the rule half-implemented
/// exactly where it matters most. Both tables get it; dropping `hydration_log`
/// is one line here and one call in `NightNutritionWindowAssigner`.
///
/// **snake_case, matching its table rather than the spec.** `nutrition_log` is
/// Migration009's and `hydration_log` Migration012's, both snake_case, while the
/// spec's camelCase columns live in Migration014-onward tables. The naming split
/// is a deferred reconciliation (`docs/architecture/spec-reconciliation.md` §3)
/// and a new column is not the place to half-apply it:
/// `nutrition_window_id` reads consistently with the fourteen columns beside it.
public enum Migration044_NutritionWindowAssignment: Migration {
    public static let version = 44
    public static let name = "nutrition_window_assignment"

    public static func up(_ db: Database) throws {
        // SQLite allows ADD COLUMN with a REFERENCES clause only when the column
        // defaults to NULL — which is also §7.2's meaning for it. The column is
        // "non-null on religious fast days", so NULL is the ordinary case, not
        // an absence of one.
        try db.execute("""
        ALTER TABLE nutrition_log ADD COLUMN nutrition_window_id
            INTEGER REFERENCES nutrition_window(id);
        """)
        try db.execute("""
        ALTER TABLE hydration_log ADD COLUMN nutrition_window_id
            INTEGER REFERENCES nutrition_window(id);
        """)
        // The read shape the suhoor case needs: "everything logged in this
        // window". `logical_day` cannot answer it, which is the whole reason
        // the column exists — a 03:50 suhoor entry is on logical day D+1 and in
        // D's window.
        try db.execute("CREATE INDEX idx_nutrition_log_window ON nutrition_log (nutrition_window_id);")
        try db.execute("CREATE INDEX idx_hydration_log_window ON hydration_log (nutrition_window_id);")
    }
}
