import Foundation

/// The 21 wger exercises licensed CC0 (`license.id == 3` in wger's own API),
/// fetched live from `https://wger.de/api/v2/exerciseinfo/` on 2026-09-16 —
/// not the illustrative "squat, deadlift, bench press…" list the Slice 4
/// prompt sketched. That list doesn't survive contact with wger's actual
/// per-row licensing: Bench Press, Squat and Deadlift are all CC-BY-SA 4 in
/// wger's catalog, not CC0. `exercise-data-collection-report-2026-09-02.md`
/// already knew the real count was 21 ("wger cannot be classified as a
/// source — only as rows"); this is those 21 rows, by wger's own exercise
/// `id`, so a future re-sync can diff against it.
///
/// `prescriptionType` is assigned by the default rules in
/// `prescription-model-v0.1.md` §6 wherever wger's `category`/`equipment`
/// fields settle it unambiguously (`confidence: .high`). Six of the
/// twenty-one don't settle unambiguously — wger's `equipment` field mixes
/// "what the exercise is loaded with" and "what apparatus it uses", and the
/// model's rule set can't tell those apart from the field alone. Those six
/// are `confidence: .medium`, overridden from the mechanical rule with a
/// reason recorded per-row, matching §6.1's own finding that a reviewable
/// low/medium-confidence remainder is expected, not a bug. Nothing here is
/// `.low` — every override has a concrete reason, not a guess.
public enum WgerCC0Seed {
    public struct Row: Sendable {
        public let wgerId: String
        public let name: String
        public let category: String
        public let equipment: String?
        public let prescriptionType: String
        public let confidence: String
        /// Present only when prescriptionType overrides what §6's mechanical
        /// rule would have assigned from category/equipment alone.
        public let overrideReason: String?
    }

    public static let rows: [Row] = [
        // --- High confidence: §6's mechanical rule settles it cleanly ---
        Row(wgerId: "177", name: "Cycling", category: "Cardio", equipment: nil,
            prescriptionType: "duration", confidence: "high", overrideReason: nil),
        Row(wgerId: "194", name: "Dips", category: "Chest", equipment: "none (bodyweight exercise)",
            prescriptionType: "reps_bodyweight", confidence: "high", overrideReason: nil),
        Row(wgerId: "282", name: "Handstand Pushup", category: "Shoulders", equipment: "none (bodyweight exercise)",
            prescriptionType: "reps_bodyweight", confidence: "high", overrideReason: nil),
        Row(wgerId: "364", name: "Leg Curl", category: "Legs", equipment: nil,
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "369", name: "Leg Extension", category: "Legs", equipment: nil,
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "371", name: "Leg Press", category: "Legs", equipment: nil,
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "445", name: "Pause Bench", category: "Chest", equipment: "Barbell, Bench",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "490", name: "Renegade Row", category: "Back", equipment: "Dumbbell",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "495", name: "Reverse Curl", category: "Arms", equipment: "Barbell, Dumbbell",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "508", name: "Row", category: "Back", equipment: "Barbell, Dumbbell, Pull-up bar",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "570", name: "Shoulder Shrug", category: "Shoulders", equipment: "none (bodyweight exercise)",
            prescriptionType: "reps_bodyweight", confidence: "high", overrideReason: nil),
        Row(wgerId: "599", name: "Snatch", category: "Shoulders", equipment: "Barbell",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "616", name: "Squat Thrust", category: "Legs", equipment: "none (bodyweight exercise)",
            prescriptionType: "reps_bodyweight", confidence: "high", overrideReason: nil),
        Row(wgerId: "621", name: "Standing Bicep Curl", category: "Arms", equipment: "Dumbbell",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),
        Row(wgerId: "650", name: "Thruster", category: "Legs", equipment: "Barbell",
            prescriptionType: "reps_load", confidence: "high", overrideReason: nil),

        // --- Medium confidence: overridden from §6's mechanical rule ---
        Row(wgerId: "152", name: "Chin Up", category: "Back", equipment: "Pull-up bar",
            prescriptionType: "reps_bodyweight", confidence: "medium",
            overrideReason: "equipment='Pull-up bar' isn't 'body only', so the rule alone reaches reps_load; a chin-up is bodyweight calisthenics, the bar is the apparatus, not the load."),
        Row(wgerId: "297", name: "Hollow Hold", category: "Abs", equipment: "Gym mat",
            prescriptionType: "time_under_load", confidence: "medium",
            overrideReason: "no 'force' field to trigger §6's static-hold rule from equipment alone; 'hold' in the name is the same isometric case the model's own table lists (plank, wall sit)."),
        Row(wgerId: "376", name: "Leg Raise", category: "Legs", equipment: nil,
            prescriptionType: "reps_bodyweight", confidence: "medium",
            overrideReason: "equipment is empty rather than explicitly 'none (bodyweight exercise)', so the rule defaults to reps_load; a leg raise (hanging or lying) is bodyweight."),
        Row(wgerId: "718", name: "Wall Squat", category: "Legs", equipment: "none (bodyweight exercise)",
            prescriptionType: "time_under_load", confidence: "medium",
            overrideReason: "equipment='none' reaches reps_bodyweight mechanically, but a wall squat is a static hold — prescription-model-v0.1.md §2 names 'wall sit' as its own time_under_load example."),
        Row(wgerId: "722", name: "Weighted Step-ups", category: "Legs", equipment: nil,
            prescriptionType: "reps_load", confidence: "medium",
            overrideReason: "equipment is empty, but the exercise name states 'Weighted' — external load, not bodyweight."),
        Row(wgerId: "2478", name: "Glute-Ham Raise", category: "Legs", equipment: "Bench",
            prescriptionType: "reps_bodyweight", confidence: "medium",
            overrideReason: "equipment='Bench' isn't 'body only', but a glute-ham raise is bodyweight resistance against a GHD/bench apparatus, not an external load."),
    ]

    /// Inserts every row not already present (matched on (sourceId, exerciseId)),
    /// skipping ones already seeded rather than failing on the UNIQUE constraint.
    /// Returns the number of rows actually inserted.
    @discardableResult
    public static func seed(into store: ExerciseCatalogStore) throws -> Int {
        var inserted = 0
        for row in rows {
            if try store.exercise(sourceId: "wger", exerciseId: row.wgerId) != nil { continue }
            let notes = row.overrideReason.map { "Prescription type override: \($0)" }
            _ = try store.insert(ExerciseCatalogDraft(
                sourceId: "wger", exerciseId: row.wgerId, name: row.name,
                category: row.category, equipment: row.equipment,
                prescriptionType: row.prescriptionType, licenseGroup: "cc0",
                confidence: row.confidence, notes: notes
            ))
            inserted += 1
        }
        return inserted
    }
}
