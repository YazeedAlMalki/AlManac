# Almanac — Project Status, 2026-09-16

Live-checked against the repo on `yamal` (git log, migrations, test files) plus BRD v1.5 (the approved spec — `docs/architecture` + memory), not just prior status docs. Where a claim is doc-derived rather than freshly verified, it's marked.

---

## Leading with the answer

**Rough overall completion against BRD v1.5's own 12-slice build order: ~35–40%.** That's a weighted eyeball across slices, not a metric — see the table below for what's actually behind it.

**What's actually solid:** Foundation (100%), Laboratory (~85%), Hydration (~90%), and the Slice 2 data layer — sleep/readiness/circadian engines, all five wellness stores, HealthKit bridges (~90% of the *backend*, 0% wired into the app). 297 tests, all green, nothing uncommitted.

**What's genuinely at zero:** Training/Exercise, Fasting, Digestion/Urination, Body Composition, Insights/Correlations, and every screen except Laboratory + Hydration + Settings. No Apple-platform verification has ever happened in this project's history — that's what the iMac session is for.

**Three things sitting idle that aren't a decision, just unsent:** the SFDA licence enquiry, two exercise-provenance emails, and the Compendium MET-license email — all outstanding since 2026-09-02, all blocking real downstream work (Gulf food data, exercise photo shippability, exercise calorie burn).

**One doc actively wrong:** `docs/architecture/spec-reconciliation.md` still says the four schema collisions are "not decided." They were decided and shipped in commit `c83e88c` yesterday. Nobody's touched the doc since.

---

## 1. Progress by BRD v1.5 build order (§12) — the exhaustive list

BRD v1.5 (approved, 2026-08-05) defines the build order in 12 risk-first vertical slices. This is the authoritative sequence — using it instead of an invented one.

| # | Slice | Status | % | Notes |
|---|---|---|---|---|
| 1 | Foundation | ✅ Done | **100%** | Database, MigrationRunner, TimeModel (04:00 boundary), Clock, SourceIdentifier, LicenceGroup, SyncAnchorStore, BackupService |
| 2 | Core daily (profile, HealthKit sleep/vitals, mood/soreness check-in, readiness, dashboard) | 🟡 Partial | **~45%** | See breakdown below |
| 3 | Hydration & caffeine | 🟢 Near-done | **~90%** | Full module, drink catalog, two-way HealthKit water sync, reminders, dashboard+logging UI. `caffeine_log` just landed (Task #11) — context computation built, not yet exercised against real shift_schedule data |
| 4 | Training (programs, sessions, RPE/load, HealthKit workout merge) | 🔴 Not started (code) | **~15%** | 0% schema/code. But: exercise data lake fully collected (12,134 artifacts, 7 sources) and prescription model v0.1 fully designed (12 types, mapped across 2,040 exercises) |
| 5 | Nutrition (quick entry, saved meals, food search, macros) | 🟡 Partial | **~55%** | Data backend 100% (8,354 foods, 49,036 values, USDA/CIQUAL/CoFID/AFCD, QA-passed). **UI: 0%** — no nutrition screens exist in `Native/Almanac` at all |
| 6 | Fasting (Day Type, IF, religious fasting, prayer-time engine) | 🔴 Not started | **0%** | No fasting/prayer code found anywhere in the repo |
| 7 | Body & wellness (weight, composition, measurements, photos, labs, supplements, injuries) | 🟡 Partial | **~35%** | Labs ~85% (14 tables + iOS UI, gaps below). Injuries 100% (Slice 2). Weight/composition/measurements/photos/supplements: **0%**, confirmed by search — no matching code anywhere |
| 8 | Regional food-data (licensing, Gulf/Saudi dishes) | 🔴 Blocked | **~40%** | Pipeline + `NutritionDishEditor` tool exist; **0 dishes authored**. Blocked on Yazeed supplying reference material, and on the SFDA enquiry (unsent) |
| 9 | Digestion & urination | 🔴 Not started | **0%** | Requires clinician review before ship regardless; genuinely zero code |
| 10 | Insights (trends, correlations, achievement calendar) | 🔴 Not started | **0%** | — |
| 11 | Advanced notifications (contextual rules, suppression matrix) | 🟡 Minimal | **~15%** | Only hydration's fixed-time reminders exist. No suppression matrix, no contextual rules engine |
| 12 | Migration & completion (export/restore, migration testing, widgets, App Intents) | 🟡 Partial | **~30%** | `BackupService` online-snapshot exists; `restore` still throws by design. No migration testing, widgets, or App Intents |

### Slice 2 breakdown (the one everyone's about to work on)

| Item | Status |
|---|---|
| Schema (14 tables, migration 014) | ✅ Done |
| SleepClassifier, ReadinessEngine, CircadianContextEngine | ✅ Done, tested |
| Five stores (Profile, Mood, Soreness, Injury, Vitals) | ✅ Done |
| Readiness-cycle **linking** (attach existing logs to a cycle, §8.4) | ✅ Done |
| Readiness-cycle **creation** (trigger a new cycle when a sleep episode lands) | ❌ Not built — this is the actual gap, distinct from linking |
| HealthKit sleep/vitals bridges (core logic) | ✅ Done, tested |
| HealthKit bridges wired into the iOS app / `HealthSyncService` | ❌ Not started — only the `.water` domain is wired today |
| Dashboard UI (readiness display, provisional vs. final state) | ❌ Not started |
| Mood/soreness check-in UI | ❌ Not started |
| Daily guidance feedback (👍/👎, per BRD §6.9) | ❌ Not started |

### Laboratory gaps (the ~15% not yet done)

Catalog coverage tracked-not-claimed per `laboratory-catalog-coverage-v0.1.md`: differential percentages, full electrolyte panel (Cl, HCO₃, Ca, Mg, phosphate), extended thyroid (fT3, TPO antibodies), homocysteine, urinalysis analytes, and any verified LOINC codes (licensing unresolved). Apple-platform verification of the Laboratory + Hydration screens has never happened.

---

## 2. Codebase health snapshot (verified live, 2026-09-16)

| Check | Result |
|---|---|
| Working tree | Clean, nothing uncommitted |
| Latest commit | `c83e88c` on `master`, in sync with `github/master` |
| Migrations | 001–015, sequential, no gaps |
| Test count | **297 total** — 258 XCTest-style + 39 Swift Testing (`@Test` macro) |
| Test framework | **Split across two frameworks.** Everything through Slice-2-adjacent work (nutrition, lab, hydration) uses XCTest; the five new Slice 2 stores + HealthKit bridges + drink/caffeine stores use Swift Testing. Not yet a problem, but it's two conventions in one codebase |
| CI | GitHub Actions exists, added on `claude/ponytail-anxf91`. Runs Linux Swift build/test — **not confirmed to touch `Native/` (iOS target) at all**, since that needs a macOS runner |
| Apple-platform verification | **Never done, anywhere, in this project's history.** Only `swiftc -frontend -parse` on Linux. No Simulator launch, no Xcode build, no interactive check — this is exactly what the iMac session exists to close |

---

## 3. Next goals — what, how, when, where

Two parallel tracks, per the split already in place: **iMac (Xcode)** handles native/HealthKit verification; **yamal** handles everything else.

### Track A — iMac (Xcode, macOS Ventura, native verification)

| What | How | When | Personal / AI-delegatable |
|---|---|---|---|
| Verify 297 tests pass on Swift 6.3.3/Xcode toolchain | `swift test` from repo root | First thing, before touching UI | AI-delegatable |
| Run the 12-item interactive acceptance checklist in `Native/README.md` | Build + Simulator launch, manual walkthrough | After tests pass | **Personal** — needs a human tapping through the Simulator |
| Wire `HealthKitProvider` to consume the new sleep/vitals bridges (currently water-only) | Extend the existing HealthKit adapter pattern; map HK types per spec §6/App. C | This session | AI-delegatable, but needs Xcode to compile/verify |
| Build readiness-cycle creation (the identified gap — trigger on new primary sleep episode) | Call `SleepClassifier.determine()` → create `ReadinessCycle` row → call `ReadinessCycleLinkingService` | This session | AI-delegatable |
| First-ever Apple SDK compile + Simulator run of the whole app | Open `.xcodeproj`, select scheme, Run | Immediately | **Personal** — this literally cannot happen anywhere but here |

### Track B — yamal (everything else)

Given the BRD build order, Slice 3 (Hydration) is already ~90% done — so the next *unstarted* slice is **Slice 4: Training/Exercise**. That's the highest-leverage next build, not a UI pass on Slice 2 (which is blocked on the iMac wiring anyway).

| What | How | When | Personal / AI-delegatable |
|---|---|---|---|
| Update `docs/architecture/spec-reconciliation.md` | Turn the four "not decided" items into "decided, see commit `c83e88c`" | Now — it's actively wrong | AI-delegatable |
| Build Slice 4 schema: `exercise_*` tables from the prescription model (12 types × 10 containers) | New migration 016+, following the spec-verbatim convention Slice 2 used | This week | AI-delegatable |
| Wire the 21 CC0 wger exercises as seed data (unblocks a minimal exercise library without waiting on the MET/licensing question) | Load into `exercise_catalog`, tag license group per row per `prescription-model-v0.1.md` §6 | After schema lands | AI-delegatable |
| Send the three outstanding provenance/licence emails (SFDA, Compendium authors, yuhonas/wrkout) | Draft + send | **Overdue since 2026-09-02** | **Personal** — these are external emails, not something to keep deferring |
| Read the JSHS article's licence statement (Herrmann et al., 2024) — may unblock MET values on attribution alone | Check DOAJ listing / article page | This week | AI-delegatable |
| Nutrition UI (quick entry, food search, saved meals) — zero screens exist | New SwiftUI views against the already-complete `AlmanacCore.Nutrition` backend | After Slice 4 schema, or in parallel if bandwidth allows | AI-delegatable, but final screens need the iMac to render/verify |

---

## 4. What should be revised, reconsidered, or added

Presented as options, not recommendations — these are calls for Yazeed.

### Revise

| Issue | Option A | Option B |
|---|---|---|
| Two test frameworks (XCTest + Swift Testing) in one codebase | Standardize all future tests on Swift Testing (it's the newer default going forward) and leave the 258 XCTest tests as-is | Migrate the 258 XCTest tests to Swift Testing for consistency (real effort, no functional benefit) |
| Migration naming split (001–013 snake_case vs. 014–015 spec camelCase) | Execute the "spec verbatim, renumber" decision now, while it's still free (no durable database exists yet) | Defer further — cost only grows once a durable database exists, but nothing forces the decision today |
| Two similarly-named spec files (`almanac-tech-spec-v1.0.md` original vs. `almanac-technical-spec-v1.0.md` reconstruction) | Delete or clearly archive the reconstruction now that the original is confirmed recovered — it's a standing confusion risk | Leave both, rely on `technical-spec-v1.0.md`'s pointer doc to disambiguate |

### Reconsider

| Question | Consideration |
|---|---|
| Should the BRD's slice order (1→12) be followed strictly from here? | Slices 3 (Hydration) and parts of 7 (Labs) are already ahead of Slice 2's completion — the project has been building opportunistically per whatever branch had momentum, not strictly in order. That's produced real value (Labs is unusually deep) but also left Slice 2's *UI* behind its *data layer*. Worth deciding whether to close Slice 2 fully before starting Slice 4, or keep building wherever there's momentum |
| Is `quality_reps` (skill/drill training — the type fencing needs) worth v1 scope? | It has zero source content in the exercise data lake and the highest authoring cost of any prescription type (open question from `prescription-model-v0.1.md` §8) |
| Is Arabic UI truly deferred to v2, or does the Laboratory catalog's Arabic-readiness (aliases, localizable entries) argue for pulling it forward? | BRD v1.5 explicitly defers it; the codebase already carries the infrastructure for it in Laboratory alone |

### Add

| Gap | Why it might matter |
|---|---|
| No design doc exists yet for Body Composition or Digestion/Urination (BRD §6.6, §6.3) | Both are in v1 scope per the BRD but have zero requirements documents, unlike Nutrition/Laboratory/Exercise which all got a dedicated pre-build design pass |
| No macOS/Xcode CI runner | Given "Apple-platform verification has never happened," a CI job that at least confirms the Xcode project builds (not full test execution) would catch regressions before they reach a hands-on iMac session |
| A short per-session status note convention while two machines work in parallel | The 2026-09-15 three-branch reconciliation (see `branch-merge-decision-2026-09-15.md`) happened because parallel agent work had no shared visibility. The iMac/yamal split is deliberate this time, but a one-line "what I touched" note per session (even just in this project's docs) would catch drift early instead of at merge time |

---

## 5. Prospects — where this could go from here

- **Shortest path to a usable daily loop:** Slice 2's data layer + engines are done and tested. The single biggest unlock isn't new design — it's wiring HealthKit sleep/vitals into the app and building the readiness dashboard. That's a scoped, mechanical task (Track A above), and it's the difference between "impressive backend" and "an app Yazeed opens every morning."
- **Laboratory is already a differentiator, not just a checkbox.** 61 analytes, 5 panels, five-dimension value model, full revision chains, Arabic-alias matching — this is more sophisticated than most v1 personal-tracking apps ship, let alone a solo-built one. Worth deciding whether it's worth surfacing as a headline feature once there's a UI pass, rather than treating it as "done, move on."
- **Training doesn't have to wait on the MET/calorie problem.** The 21 unconditionally-shippable wger CC0 exercises plus the prescription model's twelve types are enough to ship a minimal, honest exercise log (no calorie burn shown) well before the Compendium licensing question resolves. Sequencing it that way turns a legal blocker into a "coming later" feature rather than a hard stop on the whole slice.
- **The Arabic-readiness already built into Laboratory is optionality, not obligation.** Nothing forces pulling Arabic forward, but it's worth knowing that one module already carries the infrastructure — if a Riyadh-market angle ever becomes attractive, it isn't starting from zero.

---

## 6. Suggested skills

- `mattpocock-skills:tdd` — Slice 4 (Training) schema/store work should follow the same red-green-refactor pattern Slice 2 used
- `mattpocock-skills:domain-modeling` — only if Body Composition or Digestion design surfaces a genuinely new concept; don't reopen Slice 2 or Laboratory's settled models
- `engineering:documentation` — for the spec-reconciliation.md update and any new Body Composition/Digestion requirements doc
- `data:validate-data` — before seeding the 21 wger exercises or any exercise data, given the project's own history of licence-field survival bugs (nutrition's `Tr`/`N` token issue)
- `engineering:architecture` — if the HealthKit multi-domain wiring (sleep + vitals + water, three domains through one `HealthSyncService`) raises a design question Task #10's bridges didn't already answer

---

## References

**In repo (`yamal`, `$HOME/mnt/almanac/almanac` locally, or your normal path on the iMac):**
- `docs/architecture/spec-reconciliation.md` — needs the update flagged above
- `docs/architecture/health-data-foundation.md` — shared architecture, v0.2
- `docs/features/laboratory.md` (project doc: `almanac/laboratory-requirements-v0.2.md`)
- Commit history: `7cf2abc`, `2123990`, `f18710a`, `c83e88c` (this week's Slice 2 + HealthKit + collision work)
- `Native/README.md` — the 12-item acceptance checklist for Track A

**Project docs consulted:** `almanac/tasks-9-10-11-completion-2026-09-16.md`, `almanac/schema-collision-decision-2026-09-16.md`, `almanac/repo-reality-check-2026-09-15.md`, `almanac/branch-merge-decision-2026-09-15.md`, `almanac/laboratory-requirements-v0.2.md`, `almanac/laboratory-catalog-coverage-v0.1.md`, `almanac/exercise-data-collection-report-2026-09-02.md`, `almanac/prescription-model-v0.1.md`, `almanac/health-data-foundation-v0.2.md`

**BRD v1.5** (memory-stored, approved 2026-08-05): executive/core-models, HealthKit integration, functional modules (§6.1–6.21), build order/risks/acceptance tests — this is the authoritative source for the 12-slice structure above.
