# Almanac: Slices 8–10, 12 Execution Handoff

**Status:** Slice 11 (notifications: trigger-time computation & contextual suppression) committed as of 2026-09-19. Slice 4 (Training/Exercise schema, stores, wger seed) verified green. All work prior is merged to `master` on yamal.

**This document:** Execution framework for Slices 8, 9, 10, 12 (regional food, digestion, insights, migration/completion). Each slice defines its own build order, dependencies, blockers, and the decision/unsent-email gaps that are *not* "go build it" but "what's the shape?"

---

## Slices at a glance

| # | Slice | BRD §6 | Current | Blocker | Next | 
|---|---|---|---|---|---|
| **8** | Regional food data (Gulf/Saudi dishes) | 6.1 | 40% (pipeline exists, 0 dishes authored) | Reference material + SFDA email (unsent since 2026-09-02) | Dish authoring specs & reference docs |
| **9** | Digestion & urination | 6.3 | Schema + stores done (2026-09-19, yamal): `bowel_movement`/`urination_record` + `DigestionStore`/`UrinationStore`. No escalation classifier, no UI. | Clinician review timeline (now blocks only wording/UI, not schema) | UI (Xcode) + clinician-approved escalation wording |
| **10** | Insights (trends, correlations, achievement calendar) | 6.15–6.16 | Engine + schema done (2026-09-19, yamal): `CorrelationEngine`/`TrendEngine`/`AchievementEngine` + `correlation_pair`/`trend_snapshot`/`achievement_record` stores, unit-tested. No real metric-query wiring, no UI. | None hard | Wire engines to real stores (readiness/sleep/steps); UI once Slice 2/4 UI lands |
| **12** | Migration & completion (export/restore, widgets, App Intents) | 6.18–6.21 | Restore cycle 1 done (2026-09-19, yamal): happy-path `restore(from:)` only, against the real raw-SQLite backup format (not ZIP, contra this doc's original §6.18 read). Version/corruption rejection, transactional rollback, HealthKit de-dup still open. No widgets/Intents. | None hard | Cycle 2+: version-mismatch rejection, corrupt-file rejection, transactional rollback |

**Status update — 2026-09-19 (yamal, same-day continuation):** Slices 9, 10, and Slice 12's restore cycle 1 were built test-first per the AI-delegatable scope each row already called out — see `almanac/docs/implementation-status.md`'s "2026-09-19" entries for full detail, including three claims in this doc that turned out stale against the actual tree (migration count is 001–031 not 001–016; the backup format is raw SQLite, not ZIP; migration mechanics were already tested before this session). Full suite after this work: 266 XCTest + 370 Swift Testing, zero failures. Slice 8 untouched — still blocked on Yazeed's SFDA email and dish reference material, not on engineering time.

---

## Slice 8: Regional Food Data (Saudi/Gulf Dishes)

**BRD reference:** §6.1 — Food database strategy: *"Fallback: global DB + user-created regional + manually curated; no unlicensed redistribution."* NutritionCatalog is already 8,354 foods (USDA/CIQUAL/CoFID/AFCD); Slice 8 adds regional depth.

### Current state
- **NutritionDishEditor** tool exists (run locally, interactive).
- **Pipeline tested:** upload JSON → validate → seed to `nutrition_dish` table → verify no dupes.
- **0 dishes authored** (production state).
- **Blocking:** Yazeed hasn't supplied reference material (recipes, ingredient lists, portion sizes for Gulf/Saudi context dishes).
- **Email status:** SFDA food-composition enquiry outstanding since 2026-09-02 (unsent from Yazeed).

### What "building" means
- Not "implement NutritionDishEditor" (already done).
- **Actually:** Gather reference materials → authoring specs → author dishes → validate → seed.

### Decisions to clarify **before authoring**

1. **Scope of regional dishes.** Start with: top 20 Gulf fast-food chains + home-cooked Ramadan dishes + everyday staples? Or narrower? Yazeed's call on depth/focus.

2. **Sourcing nutrition values.**
   - **Option A:** Obtain from chain nutrition labels (chains publish online, credible sources).
   - **Option B:** Research via existing USDA/CoFID entries for close equivalents + scale.
   - **Option C:** Request from restaurants/SFDA if SFDA reply lands.
   - **Current assumption:** Option A + B for the first 10–20 dishes; SFDA reply may shift.

3. **Licensing & provenance.**
   - Each dish row carries `licenseGroup.id` (existing `license_group` table, BRD §6.1).
   - Are chain labels public-use? Are home recipes author-owned (must be Yazeed's or cited)?
   - Current data layer *requires* explicit license per row — no "assume free."

4. **Portion size defaults.**
   - Each dish has an `initialPortion` (weight in grams).
   - Dishes are *templates*, not single-serving assumptions.
   - Example: "Machboos" 400g, user can scale via `NutritionLogStore`.

5. **Meal-type tagging.**
   - Optional, used for smart defaults (lunch suggestions, meal reminders).
   - Examples: "breakfast_traditional", "lunch_main", "ramadan_iftar", "snack".
   - Schema supports but is optional for v1.

### Path forward

**Personal action (Yazeed):**
1. Send the SFDA enquiry (overdue since 2026-09-02). Check reply status; it may unlock official nutrition data.
2. Gather reference material for 10–15 core regional dishes:
   - Dish name (Arabic + English).
   - Typical ingredients + approximate quantities.
   - Portion size (grams, typical serving).
   - Source (chain label, USDA equivalent, literature, home recipe).
   - License statement (chain permission / personal / public domain / CC).

**AI-delegatable (once reference material arrives):**
1. Convert reference material → JSON structure per `NutritionDishEditor` schema.
2. Validate each row against existing `nutrition_catalog` USDA/CIQUAL entries for plausibility (e.g., "rice 100g ≈ 130 kcal").
3. Spot-check license assertions against claimed source.
4. Run through `NutritionDishEditor` to seed to database.
5. Write a verification pass (SQL QA checks: no null required fields, all licenses consistent, no accidental duplicates of global dishes).

**Blockers to surface early:**
- SFDA reply is slow or negative → fall back to chain labels + equivalent research.
- License clarity missing on any dish → flag, don't guess.

---

## Slice 9: Digestion & Urination

**BRD reference:** §6.3 — Bowel movement logging (Bristol + color + symptoms) + medical advisory system (escalation on blood/black stool/severe symptoms). Urination color tracking.

### Current state
- **Schema:** No tables found (verified by 2026-09-16 search).
- **0% code, 0% UI.**
- **Known blocker:** *"Requires clinician review before App Store release."* (BRD explicit).

### What needs deciding **before building**

1. **Clinician review timeline.** 
   - When is the review needed? (Must precede App Store submit, but not necessarily precede Slice 9 code completion.)
   - Who reviews? (External MD / internal Yazeed network / app-review consultant?)
   - Scope: safety of escalation messages? Accuracy of Bristol definitions? Wording non-diagnostic?
   - **This is not a design question; it's a process gate.**

2. **Bristol 1–7 scale.**
   - Standard reference exists (Type 1 = separate hard lumps → Type 7 = liquid, no solid pieces).
   - Images or text descriptions, or both?
   - **Architecture question:** Picker (1-tap) vs. educational onboarding + confirmation?

3. **Color scale (urination).**
   - BRD §6.3: *"8-level chart, picker + numeric + text + VoiceOver."*
   - Scale 1 (pale) → 8 (dark brown).
   - Does this exist in the codebase yet? (Check `UrinationColorScale` enum, if any.)

4. **Symptom flags & escalation rules.**
   - BRD lists: blood (amount?), gas, pale, yellow, green, black, red.
   - Medical escalation: *"Contact healthcare professional"* vs. *"Seek urgent medical attention."*
   - Escalation rules: *"amount/type of blood, black stool, persistent symptoms, bloody diarrhoea, severe pain, dizziness/weakness."*
   - **Question:** Is this wording final, or does clinician review change it?

5. **Notes/comments field.**
   - Optional free text ("urgency/pain level", "dietary change", etc.)?
   - Indexed/searchable, or append-only?

6. **Analytics/correlation usage.**
   - Slice 10 (Insights) correlates digestion with: hydration, nutrition (fiber/sodium), meal timing, supplements, medication changes.
   - Does Slice 9 build the schema *only*, or also build correlation helpers?
   - **Answer:** Schema only for v1; Slice 10 builds the association queries.

### Path forward

**Personal action (Yazeed):**
1. Clarify clinician-review process:
   - Timeline (does it block code submission, or just App Store release)?
   - Scope (safety wording, medical accuracy, escalation logic).
   - Who & when (internal, external MD, consultant, formal ethics review?).

2. Decide on color/Bristol presentation:
   - Picker + educational images + text descriptions, or picker only?
   - Show medical advisory inline (during logging) or only in settings?

**AI-delegatable (once process gate is clear):**
1. Design Slice 9 schema: `bowel_movement` + `urination_record` tables + enums.
   - Bowel: `logicalDate`, `timeOfDay`, `bristolType`, `color`, `bloodPresent` (boolean + amount if yes), `gas`, `notes`, `urgency`, `clinician_escalation_level`.
   - Urination: `logicalDate`, `timeOfDay`, `colorGrade` (1–8), `notes`, `clinician_escalation_level`.

2. Build stores: `DigestionStore`, `UrinationStore` (queries by date range, filtering, optional correlation helpers).

3. SwiftUI screens:
   - Quick entry (tab in Wellness section).
   - Color picker (urination).
   - Bristol picker + blood flag + notes + optional escalation display.

4. **Defer to pre-App Store hardening:** Integration with Digestion UI screens + final medical wording + clinician review loop.

**Blockers to surface:**
- Clinician review is external/slow → schedule early, parallelize schema work.
- Wording changes post-review → schema is stable; only UI text changes.

---

## Slice 10: Insights (Trends, Correlations, Achievement Calendar)

**BRD reference:** §6.15–6.16 — Dashboard trends + smart correlation engine (with guardrails: "associated with, never caused") + monthly achievement calendar.

### Current state
- **Schema:** ReadinessCycleStore, basic tables. Correlation/trend tables unknown (check if any exist).
- **UI:** 0% (no trends screens, no correlation charts, no achievement calendar widget).
- **Engine:** 0% (no trend computation, no correlation guardrails logic).
- **Testing:** 0% (no metrics validation).

### Architecture decisions to clarify **first**

1. **Correlation design (critical; drives schema & engine logic).**
   - **Guardrails (non-negotiable per BRD):**
     - "Describe associations, never causation" (wording).
     - Account for: min sample size, missing data, time lag, comparable-day filtering (Day Type + Circadian Context), outliers, sufficiency, strength/direction, stability, confounder tags.
     - Display *"Limited/insufficient state"* when thresholds unmet.
   - **Question:** Approach (A) simple statistical correlation (Pearson/Spearman) + threshold gating, or (B) custom domain-aware model?
   - **Examples from BRD:** *"high load correlated with elevated RHR"*, *"sleep < 6h associated with reduced readiness (when not planned recovery)"*, *"caffeine > 2 PM weakly associated with later sleep onset"*.
   - These are meaningful domain insights, not accidents. Need guardrails + user-facing confidence.

2. **Trend scope & update frequency.**
   - Which metrics matter? (readiness, sleep duration, steps, training load, mood, body weight, HRV, ...)
   - Trend horizon? (7-day, 14-day, rolling 28-day, annual?)
   - Update on every log entry (reactive) or nightly batch (predictable)?
   - Performance: can on-device Swift code compute this, or does it need optimization?

3. **Achievement calendar.**
   - BRD §6.16: *"Month grid with auto-computed badges: steps > target, high load, fasted day, calorie/macro/hydration target met, perfect log."*
   - Which 5 badges? Configurable per user?
   - "Perfect log" = all Wellness data filled in, or all recommended entries logged?
   - Recalculates on edit/delete? (Yes, says BRD §6.17.)

4. **Confidence/sample-size floor.**
   - Readiness: *"Calibrating — X of 21"* (exists already per BRD §6.9).
   - Correlations: same pattern? E.g., *"Need 14+ days of paired data to compute this correlation."*
   - Trends: display 7-day average only after 5 entries, or require 7?

### Path forward

**Personal action (Yazeed):**
1. Decide correlation approach:
   - Option A: Pearson/Spearman + thresholds (simpler, standard stats).
   - Option B: Domain-aware model (more nuanced, bespoke).
   - **Recommendation:** Start with A; if domain richness demands B, refactor later.

2. Agree on trend/achievement metrics for v1:
   - Trends: readiness, sleep, steps, training load (minimum viable).
   - Achievements: the five badges from BRD, or subset?

3. Clarify dependency: Slice 10 requires Slices 2–4, 6–8 *UI* to be done (so there's data to correlate). Current state: Slice 2 UI not finished, Slice 4 UI not started. **Sequence question:** Build Slice 10 engine *now* (data layer ready), defer UI until after Slices 2–4 UI land? Or parallelize Slice 10 UI with training UI?

**AI-delegatable (once decisions land):**
1. Schema design for correlation/trend storage:
   - `correlation_pair` (metric_a, metric_b, r-value, p-value, sample_size, last_computed, confidence_level).
   - `trend_snapshot` (metric, period, avg, min, max, direction, last_updated).
   - `achievement_record` (logical_date, badge_type, met_threshold).

2. Correlation engine:
   - Query builder (fetch paired data for readiness ↔ sleep, readiness ↔ load, etc.).
   - Statistical compute (Pearson/Spearman).
   - Confidence gatekeeping (min sample size, p-value, display-readiness rules).
   - Unit tests (mocked data, edge cases: all same value, single entry, insufficient data).

3. Trend engine:
   - Rolling averages, directional change (↑ ↓ →).
   - Update triggers (real-time vs. batch).
   - Performance check (on-device viable?).

4. Achievement badge engine:
   - Compute per day (steps, load, fast status, calorie/macro targets, log completeness).
   - Recalculation on edit (expensive? cacheable?).

5. SwiftUI screens (defer if Slice 10 sequencing is uncertain):
   - Trends dashboard (line charts per metric).
   - Correlation view (matrix or card-based).
   - Achievement calendar (month grid with badges).

**Blockers to surface:**
- Performance: correlating 12 months of daily data on-device may be slow → profile before full build.
- Slice 2/4 UI not done → limit Slice 10 UI scope or defer it.

---

## Slice 12: Migration & Completion (Export/Restore, Widgets, App Intents)

**BRD reference:** §6.18–6.21 — Export/restore (ZIP format, transactional restore, integrity checks); widgets (one-tap water logging, fasting timer); App Intents architecture readiness.

### Current state
- **BackupService:** EXISTS (online snapshot). Restore: throws by design (not implemented).
- **Widget:** 0% (no one-tap water, no fasting timer widget).
- **App Intents:** 0% (architecture ready per BRD, no actual intents built).
- **Migration testing:** 0% (no test fixtures for schema migrations, no restore-after-upgrade flow).

### What needs deciding **before building**

1. **Export/restore mechanics — restore logic especially.**
   - BRD §6.18: *"Restore: validate before applying; detect unsupported/corrupt; display summary; transactional with rollback; no partial, no duplicates, preserve IDs, rebuild derived, HealthKit reconcile separately, request permissions again, never treat cached as app-owned, never blindly rewrite imported."*
   - **Question:** What does "reconcile separately" mean? If user exports with 50 HealthKit-synced workouts, then re-logs some of those workouts before restore, how does restore avoid duplicates?
   - **Answer:** HealthKit data is not exported (it re-syncs from HealthKit after restore). App-owned data is exported. But user-logged data + HealthKit-logged data can overlap — restore must de-duplicate by `sourceIdentifier` + timestamp.

2. **Migration testing scope.**
   - Current migrations: 001–016 (after Slice 4 lands).
   - Scenario: User on schema v015, app upgrades to v016+, first launch runs Migration016. Works? ✅ (always tested on CI).
   - Scenario: User on schema v010, app upgrades to v016, migrations 011–016 run in sequence. Tested?
   - Scenario: User exports at v015, restores to a fresh install at v016. Tested?
   - **BRD explicit:** *"Integrity, restoration, migration testing may NOT defer."*
   - **Question:** How far do migration tests need to go? (Every schema version → every other? Or just old → current?)

3. **Widget scope.**
   - BRD §6.21: *"v1 deliberately small: one-tap water logging, fasting timer widget."*
   - Water widget: tap → add 250ml to today's log, show progress bar (kal target).
   - Fasting widget: show timer if fast is active, show start-button if not, tap to start/break.
   - Are these the *only* v1 widgets, or minimum viable?

4. **App Intents scope.**
   - BRD: *"Architecture compatible with App Intents, Shortcuts, widgets, Siri. v1 deliberately small: one-tap water logging, fasting timer, widget actions. No voice-assistant."*
   - Does this mean: Intents exist for water-logging + fasting start/end, but *not* for voice ("Hey Siri, log water")?
   - Or: Architecture is in place, but Intents are deferred to v2?

5. **Pre-App Store Hardening vs. v1.**
   - Export encryption (BRD §6.19): *"Deferred to Pre-App Store Hardening."*
   - Means: v1 ships unencrypted, App Store review will request before final approval.
   - Affects restore logic? (If restore is transactional, encryption doesn't change the data-flow logic.)

### Path forward

**Personal action (Yazeed):**
1. Clarify restore de-duplication for HealthKit data:
   - Approach: compare by `sourceIdentifier` + timestamp ± window (e.g., ±5 min)?
   - Conflicts (two workouts from different sources, same time)? (Keep both, or user confirmation?)

2. Scope migration tests:
   - Minimum: test current → current (001–016 → 016 already happens in CI).
   - Enhanced: test old → current (e.g., 010 → 016 sequence).
   - Restore flow: export v015, import to fresh install at v016.
   - **Question:** Is this "must ship v1" or "nice to have pre-App Store"?

3. Finalize widget + Intents scope:
   - Widgets: water logger + fasting timer only, or more?
   - Intents: built for v1, or architecture only + defer building?

**AI-delegatable (once decisions land):**
1. Restore logic:
   - Parse ZIP, validate schema version, checksums, manifest.
   - Detect unsupported migrations (e.g., restore v999 file to v016 app).
   - Display summary (# of readiness cycles, workouts, logs, etc.).
   - Transactional apply: wrap in a transaction, rollback on error.
   - De-duplication: query existing data by `sourceIdentifier` + time, merge if overlapping.
   - HealthKit reconcile: force a re-sync after restore (user grants permission again).

2. Migration test suite:
   - Fixture: pre-built database at schema v010, v012, v015.
   - Test: run migrations sequentially, verify schema matches current.
   - Test: export at v015, restore to fresh v016 app, verify data intact.

3. Widgets (SwiftUI):
   - Water logger: current intake, daily target, +250ml button, progress arc.
   - Fasting timer: if active, countdown to break window; if not, start-fast button + (optional) protocol selector.
   - Share `Database` connection with app (no separate SQLite in widget — use shared container).

4. App Intents:
   - **Option A:** Build Intents for water-logging + fasting start/break (full v1).
   - **Option B:** Build Intent stubs (architecture, no logic) — defer to v2.
   - Recommendation: A (small scope, high user value).

**Blockers to surface:**
- Restore + HealthKit de-duplication is complex → test heavily; may need refinement post-v1 if edge cases emerge.
- Widget + app share SQLite: ensure database is closed/opened safely (no concurrent access).

---

## Build sequence recommendation

Given the current state (Slices 1–5, 11 done or nearly done; Slices 2, 7 partial; Slices 6–10, 12 not started):

1. **Slice 9 (Digestion) schema:** Unblock clinician-review process in parallel. Schema work doesn't wait.
2. **Slice 8 (Regional food) authoring:** Unblock SFDA email in parallel. Reference-material gathering is personal action; schema/seeding is AI-delegatable.
3. **Slice 10 (Insights) engine:** Correlation + trend compute can start once Slice 2 data layer is done (it is). UI depends on Slices 2–4 UI being partially done. Build engine now, defer complex UI until Slice 2 UI lands.
4. **Slice 12 (Migration/widgets):** Independent of Slices 8–10. Can parallelize with any of above.
5. **Slice 6 (Fasting) is missing from this doc** — needs its own handoff once prayer-time engine is locked (Slice 11 already uses it; Fasting schema is adjacent but separate).

### Parallel tracks
- **yamal (Linux Swift):** Slice 9 schema, Slice 10 engine, Slice 12 restore logic + migration tests. (No HealthKit, no widgets; can run full test suite.)
- **iMac (Xcode):** Slice 2 UI (readiness dashboard, mood/soreness check-in), Slice 5 UI (nutrition quick entry, food search), Slice 12 widgets + App Intents. (HealthKit bridges, iOS-only rendering.)
- **Personal (Yazeed):** SFDA email (overdue), Slice 9 clinician-review process, Slice 8 reference material gathering.

---

## How to hand off mid-build

If a session completes part of a slice:

1. **Commit to yamal** with message: *"Slice X: [what]. [Decision made / still waiting on X]."*
2. **Update `docs/implementation-status.md`** with the dated entry and completion % (if applicable).
3. **Flag blockers in code comments** if waiting on external input (e.g., `TODO: BLOCKED on Yazeed's clinician-review timeline for Slice 9 medical wording`).
4. **Session note:** One-line per change (e.g., *"Slice 9 schema design landed; Slice 10 correlation engine architecture drafted; both green on mocked data. Slice 8 awaiting SFDA response."*).

---

## Definitions & constants

- **LogicalDay:** date at 04:00 boundary (not midnight).
- **sourceIdentifier:** enum distinguishing HealthKit/Watch/manual/imported data.
- **licenseGroup:** 1–9 (see `license_group` table in schema; each dish/food requires explicit license).
- **Ramadan context:** Hijri month 9, dates vary by year/location; app computes via prayer-time engine (already built in Slice 11).
- **Circadian Context:** shift-aware state (day/evening/night/transition), used by notifications, readiness, analytics.
- **Achievement calendar:** month grid, auto-badges (steps, load, fast, nutrition, log completeness), recalculates on edit.

---

## Testing baseline

- **Current:** 297 tests (258 XCTest + 39 Swift Testing). All green as of 2026-09-19.
- **Slice 8:** Authoring is manual; validation QA (SQL checks) is AI-delegatable.
- **Slice 9:** Schema + stores. Unit tests for store queries, edge cases (null values, date boundaries). No UI testing yet.
- **Slice 10:** Engine unit tests (mocked data, correlation compute, confidence gating, edge cases: all-same, insufficient data). UI testing deferred to iMac.
- **Slice 12:** Migration fixtures + sequential-run tests. Restore + de-duplication tests. Widget/Intent tests deferred to iMac.

---

## Final checklist before handing off to next session

- [ ] All decisions from "Decisions to clarify before building" are written down (yes/no per slice).
- [ ] Personal action items (Yazeed) are clear and unambiguous (SFDA email, clinician review, reference material, sequence preference).
- [ ] Blockers are flagged: which ones block progress, which are nice-to-have, which will resolve themselves (e.g., SFDA reply).
- [ ] Schema/store design is drafted (not implemented) for Slices 8–10, 12 if not done.
- [ ] Test strategy is clear (unit tests vs. integration vs. UI, what's deferred to iMac).
- [ ] Build sequence is documented (which slice first, which can parallelize).
