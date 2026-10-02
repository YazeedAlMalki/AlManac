# Handoff — Training Program Feature, 2026-10-01

This is a **product-decisions handoff**, not a status/git-state handoff like
`handoff-2026-09-30.md`. It defines a new feature (the program layer above
Slice 4's templates — PPL-style splits, exercise rotation, equipment
availability, progressive overload) that has **not been started yet**.
Read it before touching Training/Slice 4 code so new work doesn't conflict
with the decisions below.

---

## What this feature is

A **training program** is the structure above a single session. It tells the app "I follow PPL" (or any other split). Each day, the user selects which part of their program to do (Push / Pull / Legs), and the app generates the exercise list for that day — rotating through exercise variations across sessions. The user can run multiple programs simultaneously (e.g. PPL + a mobility program).

Day selection is always manual — no automatic scheduling.

---

## Decisions

### 1. Equipment variants
- Tracked separately by default (dumbbell fly and cable fly are distinct entries).
- Can be displayed together in the same graph — toggled via a radio button directly on the graph ("Separate" | "Combined").
- Small-print note shown under the graph in combined mode: equipment variants may not be directly comparable.

### 2. Exercise generation — rotation
- A program day (e.g. Push) holds a pool of exercises that rotate across sessions.
- Each time the user does a Push day, the app generates that session's exercise list from the pool in rotation order.
- Rotation advances on **completed sessions, not calendar time.** Users may be athletes (professional or amateur) with irregular schedules — skipping a day is normal. If the user doesn't train for a week, the next Push day they pick up is still the next item in the rotation, not advanced or reset by the gap.

### 3. Exercise availability — two mechanisms, reason is separate from mechanism
Two athlete archetypes drive this (home gym vs. commercial gym), but the mechanism doesn't care about the archetype — only about how long the unavailability lasts:

| Mechanism | Trigger (reason is informational, not the deciding factor) | Effect on rotation |
|---|---|---|
| **Permanent pool removal** | Equipment not owned at the user's gym, a variation the user dislikes, or any condition that holds every time. | `is_active = false`. Never offered again until the user manually re-adds it. |
| **Per-session skip** | Equipment occupied today, short on time — a one-off. | **Holds its position.** The same skipped item is offered again next time that day type comes up, repeatedly, until the user explicitly, permanently removes it. |

Dislike and lack-of-equipment are **not** functionally different — both resolve to permanent removal. The skip reason is never "does the user dislike this" — it's purely "is this a one-off or does it hold every time." UI copy should ask it that way (e.g. "Skip just for today" vs. "Remove from rotation"), not frame it as a preference judgment.

**Flagged tension:** if a user's gym genuinely never has a given machine, "skip for today" would be the wrong action every single time — it'll keep re-offering something they can never do. The UI needs to make "remove permanently" at least as easy to reach as "skip for today" at the moment of skipping, so a recurring equipment gap doesn't turn into a recurring annoyance. Not a blocker, but worth designing the skip prompt with both options visible together.

### 4. Progressive overload
- Off by default.
- Enabled per-exercise in Settings.
- Progression rule is **set by the user per exercise** (not a fixed +2.5 kg rule globally) — user defines the increment and condition.

### 5. Progress graph — two small graphs per exercise
- Both graphs live inside the exercise detail view, each small and individually toggleable.
- Graph A: weight (or load) over sessions.
- Graph B: volume (sets × reps × load) over sessions.
- Equipment variant display: radio button toggle (Separate / Combined) applies to both.

### 6. Multiple active programs
- Yes — user can have multiple programs active at once (e.g. PPL + mobility routine).
- At session start, user selects which program and which day type.

---

## UX flow

```
Workout tab
  └── "Start Workout"
        └── Select program (PPL / Mobility / …)
              └── Select day type (Push / Pull / Legs)
                    └── [Prompt] "Factor in your readiness score?" Yes / No
                          └── Clipboard — active session
                                ├── Generated exercise list (rotated from pool, skipping inactive items)
                                ├── Per-exercise action: "Skip just for today" or "Remove from rotation" (shown together)
                                ├── Prescribed sets × reps × load per exercise
                                ├── Equipment variant selector per exercise
                                ├── Tap set → enter actual reps + load → mark done
                                └── Finish → session saved → graphs update
```

---

## Schema (for the AI to implement)

```
training_program
  id, name, created_at
  -- e.g. "My PPL", "Mobility"

program_day
  id, program_id, label
  -- e.g. "Push", "Pull", "Legs"

program_day_exercise_pool
  id, program_day_id, exercise_id, rotation_position, position_within_session
  is_active (bool, default true)      -- permanent removal (equipment gap, dislike, or any every-time condition)
  prescription_type
  container_type
  sets, reps, load_kg, duration_s, rest_s   -- nullable per type
  progression_enabled (bool)
  progression_increment_kg (nullable)
  progression_condition (nullable)          -- e.g. "all_reps_completed"
  notes

workout_session  (already exists — extend)
  + program_day_id (nullable)
  + rotation_index  -- which rotation pass this session was; advances only on completion, never on calendar gaps
  + readiness_adjusted (bool)

workout_session_set  (already exists — extend)
  + equipment_variant  -- "barbell" | "dumbbell" | "cable" | "machine" | null
  + prescribed_reps, prescribed_load_kg
  + was_skipped_for_session (bool)   -- true if this slot's pool item was skipped (one-off) for this session only;
                                      -- does not advance rotation_position — the same item is offered again next time
```

**Key rule:** `program_day_exercise_pool` is the prescription. `workout_session_set` is the log. The prescription never changes based on what was logged — only the user edits it, skips it for one session, or deactivates it via `is_active`.

Note: `prescription_type` and `container_type` reference the twelve-type model in
`prescription-model-v0.1.md` (if present in this repo's docs; otherwise ask Yazeed —
it originated in the Claude Project, not this repo). `quality_reps` is one of the
twelve types and is the one flagged as deferrable below.

---

## Open (not blocking build)

| Question | Option A | Option B |
|---|---|---|
| Rotation order — strict cycle or user-reorderable? | Strict cycle by `rotation_position`. | User can freely reorder in the template editor. |
| `quality_reps` (fencing drills) in v1 or deferred? | Build now. | Defer — zero source content, high authoring cost. |

**Resolved this session:** per-session skip holds its position (does not advance rotation) and is re-offered next time until the user permanently removes it — see Decision 3.

---

## Work split

**Personal (Yazeed):**
- Confirm strict-cycle vs reorderable rotation order.
- Decide `quality_reps` timing (v1 or defer).

**AI-delegatable (this is the build work):**
- Migrations for `training_program`, `program_day`, `program_day_exercise_pool`, and the two `workout_session`/`workout_session_set` extensions.
- `ProgramStore`, `ProgramDayStore`, `ProgramDayExercisePoolStore` — CRUD following existing store patterns in this repo.
- Rotation engine: given a `program_day_id` and last `rotation_index`, return the next active exercise set, excluding `is_active = false` items; a per-session skip substitutes the next pool item for display but leaves `rotation_position` untouched so the skipped item reappears next time.
- Readiness adjustment computation.
- Per-exercise progression suggestion (reads history, applies user-defined increment + condition).
- Equipment variant toggle logic on progress graphs.
- Unit tests for rotation engine (including the skip/hold-position path and irregular-schedule gaps), progression, readiness adjustment. Build and run the full suite before committing — match this repo's existing verification standard (see `handoff-2026-09-30.md` §0 for the pattern).
