# Almanac — BRD v1.6 (Executive & Core Models)

**Product:** Almanac (body-monitor app)  
**Version:** 1.6 | **Date:** 2026-09-25 | **Owner:** Yazeed | **Status:** Approved  
**Changelog:** v1.6 — §6.16 Monthly Achievement Calendar replaced by Activity Rings Calendar; dependent references (§6.17, §6.18, §5.4, §10, §12 Slice 10, A1, A3) updated. Diet Profile dependency open.

## Executive Summary

Native iOS app unifying body signals: nutrition, hydration, caffeine, fasting, sleep, digestion, urination, vitals, training load, mood, body composition → **one readiness assessment per daily cycle**, timed to primary sleep/waking (not fixed clock).

**Core differentiator:** integration. Correlates all inputs (caffeine timing → sleep quality → readiness) instead of five disconnected apps. **HealthKit is exchange layer**, local DB essential for app-specific records, relationships, offline, sync metadata, derived analytics.

**Primary user:** Yazeed (multi-sport: bodybuilding, endurance, fencing; rotating shifts).  
**Future:** Commercialization possible post-v1. v1 decisions must not block, but not pay costs early.

## Vision & Goals

**Vision:** One trustworthy readiness number per daily cycle — backed by complete, private, well-provenanced record.

**Goals (v1):**
1. Replace all separate tracking tools with one app.
2. Sustain daily logging via deep HealthKit sync + near-zero-friction entry.
3. One readiness assessment per daily cycle (provisional after sleep, final after mood/soreness), explicit confidence & calibration.
4. Smart contextual notifications respecting fasting, religious fasts, shift schedule.
5. 100% on-device data — no accounts, servers, recurring costs.

**Non-goals:** Multi-user, monetization, Android/web, social, cloud sync, AI coach, Arabic UI (deferred).

## Target Users

| Phase | User | Notes |
|---|---|---|
| v1 | Yazeed | Multi-sport; rotating shifts; non-conventional sleep timing. |
| Future | Body monitors | After Pre-App Store Hardening: security, privacy, clinician review, Arabic, female features. |

## Core Cross-Cutting Models (Section 4)

### 4.1 Time & Day Model — Never Conflate

- **Calendar date:** civil date of timestamp
- **Logical day:** 04:00 → 04:00 local; default grouping for summaries
- **Religious dry-fast session:** Fajr → Maghrib on fast day
- **Night nutrition window:** Maghrib → next Fajr on religious-fast days (suhoor at 3:50 AM retains timestamp, belongs to preceding Maghrib window)
- **Sleep episodes:** span any boundary
- **Readiness cycle (circadian day):** primary waking → next primary waking (basis for readiness, not clock)

**Rules:**
- Every record retains original timestamp & timezone offset.
- Logical day available for summaries, not sole basis for sleep/readiness/shifts/fasting/workouts.
- Deterministic rules linking all concepts required in Technical Spec.
- Travel/timezone: timestamps remain correct; future prayer times recalculate; logical-day grouping deterministic.

### 4.2 Day Type

Every day: **Normal / Intermittent Fast / Religious Fast**.
- Set in advance, changed on day, or app-suggested (IF uses uncertainty wording; religious pre-set with manual override).
- Drives notification precedence, hydration, nutrition windows, readiness interpretation.

### 4.3 Circadian / Shift Context (independent from Day Type)

Each cycle carries **Circadian Context:** stable day/evening/night, transition earlier/later, first post-night-shift, recovery, irregular.
- Day Type + Circadian Context are orthogonal. Day can be *Religious Fast + Night Shift*, *IF + Rest Day*, *Normal + Transition*.
- Conventional-schedule users can ignore/disable.

### 4.4 Record Provenance & Data Ownership

Every record carries provenance: **imported from HealthKit** (source app/device preserved), **manually entered**, **app-generated**, or **derived**. Four classes handled separately in sync/backup/restore. Food records preserve: source DB, version, user-modification flag, prep state, measurement basis.

## Platform & Technical Constraints

- **Platform:** native iOS (iPhone), Swift/SwiftUI.
- **Storage:** 100% on-device (SQLite). No backend/accounts/server costs.
- **Notifications:** local only; contextual rules computed at app-open/log.
- **Language:** English UI, i18n-ready for Arabic.
- **Units:** metric (kg, ml, cm, km).
- **Prayer times:** on-device, no server.
- **Build:** Mac + Xcode. $99/yr Apple Developer account for sustained use.
- **Method:** Claude Code (BRD → Tech Spec → build).

## Success Criteria (v1)

1. **Daily use:** Core loop (readiness + mood/soreness, hydration, meal/fast, workout) on ≥27 of 30 days.
2. **HealthKit:** Large majority of eligible records imported without manual action; zero duplicates; graceful with missing permissions.
3. **Readiness:** ≥80% positive feedback ratings on post-calibration rated days.
4. **Notifications:** No meal reminder during confirmed fast; no water during dry fast; individually controllable.
5. **Backup/restore:** Archive validation, checksums, transactional restore, no duplicate HealthKit records post-restore.
6. **Offline:** Functionally useful offline.
7. **Shift work:** Readiness/sleep/notifications follow primary sleep cycle (not fixed morning), transition days identified, calibration never resets.

## Next Steps

**Yazeed:** Final approval v1.5; name confirmed (Almanac); Apple Developer account when daily use starts.  
**Claude:** Technical Spec ready; build via Slice 1 (Foundation) per Section 12.

---

# Section 5: HealthKit Integration

## 5.1 Role

HealthKit is health-data exchange layer. Local DB exists for: app-specific records, cross-module relationships, fast dashboard, offline, sync metadata, derived analytics, data HealthKit doesn't model. Local DB doesn't replace HealthKit.

## 5.2 Imported HealthKit Data (HealthKit-authoritative)

For data from Apple Watch, iPhone, or other health apps: **HealthKit is authoritative**. App imports where available & authorized:
- Sleep duration & stages
- Resting heart rate, HRV, heart-rate samples
- Steps, active energy
- Apple Watch workouts
- Weight, body-fat %, lean body mass

App maintains synchronized local representation for dashboards/calculations, reconciles with HealthKit, preserves source provenance.

**Missing data is unknown, never zero.** If query returns no accessible data, app must NOT claim permission denied. **Required UI wording:** *"No accessible sleep data was found. Check that sleep was recorded and review Health access in Settings."*

## 5.3 Data Created Inside Almanac

- Stored **locally first**, always.
- Where HealthKit supports suitable type & user grants write permission, app also writes to HealthKit. Examples: water, supported nutrition, weight, body-fat %, workouts.
- Local entry **never lost** if HealthKit write fails; failed writes remain **pending & retryable**, visible sync status until reaching HealthKit.
- Reliable sync & duplicate prevention are product requirements; query types, anchors, background APIs, retry algorithms are Technical Spec matters.

## 5.4 Local-Only Data (Application-Owned)

Unless HealthKit model deliberately adopted later:
- Readiness scores, input snapshots, feedback
- Mood/energy, muscle soreness, injury notes
- Stool/urination observations
- Fasting sessions, religious-fast schedules
- Shift schedules & circadian context
- Training programs, workouts, exercises, set-level details, deload definitions
- Activity ring settings (e.g. digestion-ring toggle), notification rules
- Progress photos, custom body measurements
- Supplement plans & adherence, correlation outputs, app settings

**Lab results remain local-only in v1** — manually entered lab values not represented as clinical HealthKit records.

## 5.5 Synchronization Contract (Product Requirements)

- Incremental sync — never repeatedly import complete history.
- Foreground reconciliation on every app activation.
- Background sync where iOS/HealthKit permit; **no promise** of instant/continuous.
- Preserve HealthKit source application & source device.
- Stable linkage between app-owned entries & HealthKit samples.
- Detect & handle HealthKit deletions.
- **Idempotent sync:** repeating never creates duplicates.
- Reconciliation after reinstall/phone migration.
- Separate handling: imported, manually entered, app-generated, derived records.
- Clear sync status when app-created item not yet in HealthKit.
- Graceful operation with missing/partial permissions.
- **Contextual permission requests** — requested when feature first used, not all at launch.

## 5.6 Conflict Resolution (Product-Level Precedence)

1. Record imported from another HealthKit source remains governed by HealthKit.
2. Almanac never overwrites third-party HealthKit record only because user changes Almanac annotation.
3. Almanac-created record remains linked to its HealthKit record.
4. Editing app-created record updates linked HealthKit representation where authorized.
5. Deleting app-created record deletes linked HealthKit sample where authorized.
6. If HealthKit-imported record deleted in HealthKit, local representation no longer active.
7. Conflicting third-party samples: preserve provenance, apply explicit source-selection rule for summaries, never destroy data.
8. Restoring backup never blindly recreates cached HealthKit data or duplicates samples.
9. HealthKit permissions must be granted again after migration/reinstall.

**Precise source-priority algorithm defined in Technical Spec; BRD requires one exist.**

---

# Section 6: Functional Modules (v1)

## 6.1 Nutrition
- Log meals: food database search, saved meals (one-tap re-log), quick entry (raw calories/macros).
- Tracked: calories + macros + fiber, sodium, sugar (fiber → digestion correlations).
- **Entry carries real timestamp & meal type.** Type user-selectable, may be suggested from waking cycle (not clock time alone).
- Food DB strategy (three questions, each verified in Tech Spec):
  1. **Technical availability:** myfood24 API/integration; SFDA food-composition publications/resources exist.
  2. **Legal availability:** access ≠ extraction/modification/offline-caching/redistribution rights.
  3. **Commercial terms:** separate from personal-use; relevant at commercialization.
- Fallback: global DB + user-created regional + manually curated; no unlicensed redistribution.
- Records preserve provenance. No AI photo-calorie estimation.

## 6.2 Hydration & Caffeine
- Water logging against daily target.
- **Unified drink logging:** one entry auto-distributes (latte → hydration + caffeine + nutrition in single tap).
- Caffeine presets per drink type (editable).
- Caffeine independent variable (mg + time) to measure sleep/performance effect.
- **Analysis relative to intended sleep, not clock:** 8 AM caffeine is *late* for night-shift worker sleeping 10 AM.

## 6.3 Digestion & Urination
**Bowel movements:** count + Bristol (1–7) + color (brown range, pale, yellow, green, black, red) + symptom flags (blood, gas) + notes.

**Medical advisory (non-diagnostic, three levels):**
1. Informational observation.
2. Contact healthcare professional.
3. Seek urgent medical attention.

Escalation: amount/type of blood, black stool, persistent symptoms, bloody diarrhoea, severe pain, dizziness/weakness. Wording calm, non-diagnostic, allows harmless-context. **Requires clinician review before App Store release.**

**Urination:** count + color grade (8-level chart, picker + numeric + text + VoiceOver). Color is outcome of hydration; intake is input. Dark color despite target → raise target (suspended during religious dry fasts).

**Accessibility:** never rely on color alone; numeric grades + text + VoiceOver.

## 6.4 Sleep
**Sleep episodes**, not "last night":
- **Primary sleep episode:** most direct support for next main waking/activity (not determined by night hours; night-shift 9 AM–4 PM primary).
- **Naps, split, recovery, post-night-shift sleep.**
- Classification automatic from HealthKit + shift context; user can correct; timestamps preserved; never force-attached to calendar date begun.
- Overlapping sources: preserved with provenance; explicit source-selection rule for summaries.
- Aggregates: total within rolling period; sleep spanning 04:00; Ramadan fragmentation via episodes, not penalized.

## 6.5 Training
- **(v1) Manual builder:** programs → workout days → exercises → sets × reps × weight, time/distance (endurance), rounds/drills (fencing). In-workout logging with rest awareness.
- **(v1) Template library:** ready-made programs to copy/edit.
- **(Phase 2) AI Coach:** deferred; v1 data model remains consumable.
- **Multi-sport:** sport/type tag; reps-, time-, distance-based support.
- **Session RPE (v1):** 1–10 post-workout rating per session. Per-set deferred.
- **Session load = duration (min) × RPE** — cross-sport workload (bodybuilding volume ≈ endurance distance ≈ fencing workload).
- **Recovery:** rest days & deloads first-class objects.
- **Import & merging (confidence model):** Watch/HealthKit workouts matched to planned/manual using overlap, start-time diff, duration, sport compatibility, HR coverage.
  - High confidence → merge auto. Medium → confirm. Low → separate.
  - Merge reviewable, undoable, audit trail.
  - Late HealthKit workouts eligible for reconciliation.
  - **No double-counting** calories/duration/HR/load; overlapping use designated source, never sum.
  - One Watch workout never silently merges with multiple manual; ambiguous matches need confirmation.
  - Unmatched HealthKit workouts persist as unplanned sessions.
  - Thresholds in Technical Spec.

## 6.6 Body Composition
- Weight, body-fat %, lean, skeletal muscle, visceral-fat rating (as desired).
- Each records **source** (Apple Health, InBody, smart scale, manual) & **conditions** (fasted/non-fasted).
- **Custom circumference measurements** (owner-priority): user-definable, charted.
- **Progress photos:** periodic, same-pose comparison.
- **Lab results:** manual entry; long-interval trends; local-only v1; display-only.

## 6.7 Vitals & Activity
Resting HR, HRV, workout HR, steps, active energy — imported (HealthKit-authoritative, Section 5.2) with manual fallback.

## 6.8 Wellness Logs & Context Tags
- **Mood/energy:** 1–10 per cycle.
- **Soreness:** 1–10 + body-area. **Injuries:** dated notes; active restriction feeds readiness precedence.
- **Supplements:** plan, dose logging, adherence, reminders.
- **Context tags (optional, never mandatory):** illness, med change, travel/jet lag, stress, heat, sauna, poor Watch wear, late event, sleep interruption, competition. Available to correlations as confounders.

## 6.9 Readiness (Integration Core)

**Timing:** one per **readiness cycle** after primary sleep or main waking start. Morning for conventional; afternoon/evening for shifts. Notifications schedule relative to: end detected/planned primary sleep, expected wake, main active start, planned workout — **never fixed morning while sleeping post-shift**. If primary sleep unknown, wait for app-open or ask.

**Two states (visually distinct):**
- **Provisional:** from auto inputs after waking (sleep, RHR, HRV).
- **Final:** after mood/soreness submission.

**Inputs:** sleep duration, quality/stages, RHR, HRV, soreness, mood/energy.  
**Missing never silently zero.** Each missing reduces confidence, indicated to user.

**Every score:** state, confidence, missing-input indication, formula version, input snapshot, timestamp.

**Calibration & baselines:**
- **Initial (21 valid days):** valid = sufficient required inputs (not calendar days). UI shows *"Calibrating — X of 21"*; may show labeled provisional estimate; never presents as fully reliable.
- **Rolling baseline after (28 valid days).**
- **Ramadan context:** own baseline (fragmented sleep, dry-fasted vitals norm). Prior Ramadan data may contribute per recency/sufficiency rules.
- **Shift-aware hierarchical:** general → shift-specific (when sufficient data) → transition adjustment → per-day confidence. Changing shifts never resets 21-day calibration; until shift-specific exists, fallback to general with reduced confidence & limited-data notice.

**Precedence:** score never overrides: planned rest, planned deload, active injury, manually selected recovery, religious-fast training constraint. Score 90 on deload day → *"Recovery strong. Continue planned deload."*

Transition guidance acknowledges schedule without diagnosing: *"Sleep timing shifted substantially. Limited comparable night-shift transition data."*

**Historical integrity:** historical outputs retain original formula, input snapshot, recommendation. Formula changes never silently rewrite; recalculated stored separately.

**Feedback timing:** 👍/👎 asks if recommendation proved appropriate (post-workout or next cycle start), not immediately after display.

## 6.10 Goals & Targets
- **Switchable goals:** Bulk/Cut/Maintain/Performance; recalculates targets (Mifflin-St Jeor + activity multiplier + goal adjustment).
- **Target versioning:** historical days retain targets in force. Snapshot preserves: goal, date, formula version, body stats, activity assumption, adjustment, generated targets, manual overrides.
- **Manual overrides** allowed, stored alongside (never erase) calculated.

## 6.11 Shift Schedule & Circadian Support

App never assumes: sleeps at night, wakes morning, readiness is fixed-morning, longest sleep = date begun, one permanent baseline fits all.

- **Shift Schedule feature:** types (day, evening, night, split, on-call, rest/off, custom). Each: start/end datetime, optional sleep window, optional wake time, recurrence pattern, notes.
- User can: plan advance, create patterns, change one occurrence, record unplanned change, **disable entirely** if irrelevant.
- No employer/external integration. Manual + recurring local scheduling standalone; calendar import may be evaluated.
- **Circadian Context** per cycle including transition states: stable day/evening/night, first transition, adjustment days, first stable post-transition.
- **Notification behavior:** bedtime, meal, hydration, supplement, readiness respect shift schedule. No bedtime during night shift, no readiness during post-shift sleep, no "breakfast" by clock alone, no daytime sleep classified nap by clock alone.
- **Fasting × shifts (independent):** IF windows may span midnight; timer runs calendar/logical-day boundaries; notifications respect both. Religious fast (Fajr→Maghrib) governed by prayer times, **never altered by shifts**; night-nutrition reminders consider working/sleeping; readiness considers both.
- **Analytics:** shift context filter/confounder. Sleep by type, caffeine relative to intended sleep, performance by shift, readiness on transition days, digestion across patterns. Day/night never compared equivalent without indicating difference.

## 6.12 Intermittent Fasting

- **Suggestion, not detection.** App doesn't assume fasting from lack of logging. Wording: *"No calories 14 hours. Are you fasting?"* (configurable threshold). Day Type changes to IF after confirmation.
- **Planned fasts:** protocol optional (16:8, 18:6, OMAD, custom), never forced.
- **Live timer:** start, elapsed, projected close; spans midnight/logical-day.
- **Breaking rules:** water & zero-calorie black coffee/tea don't break; calorie entry does, ends session with duration.
- **Backdated entries:** corrects/shortens/invalidates existing session per actual timestamp.
- **Precedence:** fast confirmed (or day typed fast) → meal reminders mute until window opens.
- **Insights:** fasting vs. sleep, readiness, training; IF-fasted training distinct from religiously-fasted.

## 6.13 Religious Fasting Mode (Ramadan, Mon/Thu, White Days)

- **Dry fast (Fajr → Maghrib):** no food/water; window from prayer times for user's location, adjusts daily. Shifts never alter.
- **Time model:** dry-fast session & night window (Maghrib → next Fajr) are first-class. Nutrition totals, hydration targets, window alerts on religious-fast days operate on night window; global logical day unchanged.
- **Ramadan mode (Hijri-aware, month):** water reminders suspended during fast; hydration target compressed to night with shift-aware cadence (working/sleeping); meal reminders → iftar/suhoor; **suhoor cutoff alert** before Fajr; IF auto-suggestion disabled; "drink now" urine guidance suspended during fast — adequacy from post-sleep color & night intake; readiness against Ramadan baseline.
- **Recurring fasts:** Mon/Thu & White Days (13–15 Hijri) recurring, same rules.
- **Calendar honesty:** app never assumes its Hijri calc accepted; user can manually correct dates/days.
- **Prayer-time engine:** on-device calculation; user-selectable method; location-based updates; **manual city fallback** when unavailable; user-adjustable offsets; timezone/travel handling; no server.
- **Fasted training:** pre-iftar classified religiously-fasted (distinct from IF with water).

## 6.14 Smart Notifications

- All types individually toggleable & time-adjustable: water, meal, bedtime, readiness, supplements, suhoor/iftar (when active).
- **Contextual intelligence (rule-based, on-device):** examples: *"Lunch ~60 min away — drink 200 ml now."* *"Long gap meal-to-workout — have snack."* Rules from user's logged patterns.
- **Suppression & precedence:** no meal during confirmed fast, no water during dry fast, no bedtime during night shift, no readiness during post-shift sleep. Contradictory prevented by Day Type + Circadian Context.
- **Discretion default:** avoids exposing detailed medical/digestion; discreet default where practical. Full privacy controls arrive Pre-App Store Hardening.

## 6.15 Dashboard & Insights

- Daily home: readiness (state + confidence), targets vs. actuals, today's workout, active fast timer.
- Trends: any metric.
- **Correlation guardrails:** describe **associations, never causation** ("associated with", never "caused"). Account for: min sample size, missing data, time lag, comparable-day filtering (Day Type + Circadian Context), outliers, sufficiency, strength/direction, stability, confounder tags. **Limited/insufficient state** when thresholds unmet.

## 6.16 Activity Rings Calendar

*Supersedes the badge-based Monthly Achievement Calendar (BRD ≤ v1.5). Same concept (per-day achievement/completion tracking), reimplemented as rings.*

**Open dependency (separate spec, TBD):** **Diet Profile** — user-selected/configured diet type (keto, balanced/standard, low-carb, high-protein, custom, etc.), each with its own macro/calorie target definition. The Nutrition ring reads its targets from this profile. The profile system is out of scope here and needs its own spec pass before the Nutrition ring's target logic can be fully implemented.
**Parked (not in scope):** Daily Statements banner (Home screen, book- and user-attributed quotes). Revisit separately once statement source content is ready.

**Location:** Home screen, alongside readiness/dashboard content (§6.15).

**Purpose:** At-a-glance view of daily logging/target completion across core modules, styled as concentric activity rings (Apple Watch Activity-style), to support adherence awareness and easy backfilling of missed entries.

**Display — calendar grid:**
- Standard current-month view; defaults to current month on open.
- **Navigation:** tabs at the top to move to previous/next months (not swipe-based). Sequential month tabs only, no free date-jump.
- **Today indicator:** the current day's number carries a distinct "halo" marker, separate from and in addition to that day's ring-fill state. The halo marks only *which day is today*; today's rings can be full or empty.

**Display — per-day rings:**
- **Hydration ring:** binary; fills when the day's hydration target is hit (§6.2).
- **Training ring:** binary; fills when training was logged that day (§6.5).
- **Nutrition ring:** 3-state, evaluated per tracked value, then combined:
  - Tracked values: calories, carbs, protein, fat, fiber.
  - **No log at all → no ring shown** for that day. This is distinct from an empty/unfilled ring.
  - When logged, each of the 5 values is independently classified against that day's target (from the Diet Profile, see dependency above):
    - **Hit:** within the target's acceptable band.
    - **Off:** outside the band moderately (under- or over-target).
    - **Mess:** outside the band significantly (primarily over-target); rendered in a deliberately negative/"disgusting" color.
  - **Overall state = worst state among the 5 values** (worst-case-wins, not an average). E.g. protein "hit" + fat "mess" → ring renders "mess," driven by fat.
  - **Tap-through:** tapping the ring (or the day, consistent with the calendar's tap interaction) reveals the per-value breakdown: which value(s) drove the displayed state and each value's individual status.
  - **Still undefined (needs Diet Profile spec):** actual hit/off/mess thresholds per value (e.g. % deviation bands), and how they vary by diet type (e.g. keto carb tolerance vs. balanced).
- **Digestion ring:** separate, **toggle-controlled in Settings** (on/off), visually distinct from the three core rings. **Fill condition explicitly undecided and not gated on anything.** There is no universal daily bowel-movement target, since normal ranges vary by individual; the ring needs its own definition later and does not block this section. The §6.3 clinician-review requirement for digestion advisory content stands independently and is unaffected.
- **All-rings-closed state:** when every enabled ring is in its best state (hydration + training filled, nutrition "hit," digestion if enabled in its eventual best state), the day cell renders a distinct "golden/shiny" treatment. This is the direct replacement for the former `perfect_log` badge.
- **Accessibility (§6.20):** ring state never relies on color alone. Each state (hit/off/mess, filled/unfilled) needs a non-color indicator (fill proportion/shape/pattern, VoiceOver label naming the state).

**Day boundary:** follows the 04:00 logical-day boundary (§4.1), not midnight.

**Interaction:** tapping a day opens a view showing exactly what was and wasn't logged (per-ring breakdown, including nutrition per-value detail), with access into that day's editable log. It reuses existing per-day editing surfaces (§6.17) rather than a new edit UI.

**Data model implications (for Technical Spec):**
- Hydration/Training rings: per-day boolean, computed from existing module tables.
- Nutrition ring: per-day, per-value (5 values) three-state classification against that day's active Diet Profile target. Blocked on the Diet Profile spec; data model may be stubbed with a placeholder target source until then.
- Digestion ring: on/off toggle buildable now; fill-rule logic added once defined.
- All ring states recalculate live per §6.17. Edits/deletes are reflected in that day's ring state immediately, never cached stale.

**Data loading / performance:**
- **Local-first:** paginate from local GRDB/SQLite one month at a time, not full history. A date-indexed per-day/per-module boolean or small-enum query over several years is small and not expected to cause meaningful UI lag.
- **No backend/server dependency.** Consistent with §6.19 (offline-first, no backend, no external health-data processing).
- **Explicit revisit condition:** only if on-device testing shows measurable, perceptible calendar lag, revisit a server-backed approach as a deliberate §6.19 architecture change, with encryption at rest and in transit specified as part of that change. Triggered by measured performance, not anticipated risk.

**Build sequencing:** Home-screen feature; builds within or immediately after Slice 2. Replaces the achievement-calendar item in Slice 10 (§12). Hydration/Training rings neither block nor are blocked by Slices 3–7 (they read existing module data). **Nutrition ring blocked on the Diet Profile spec.** Final icon/ring visual treatment also depends on the custom icon sheet (open item in UI Design Reference v1.0).

## 6.17 Editing, Deletion & Correction

All user logs support: edit, delete, undo, duplicate prevention, **move to correct window**, recalculation of dependent activity rings (§6.16)/dashboards/targets/fasting/correlations. Behavior in Technical Spec. HealthKit edits/deletes follow Section 5.6.

## 6.18 Backup, Restore & Migration

- Explicit export-restore required; iCloud/CloudKit never guaranteed.
- **Export = ZIP:** all app-owned data, programs, nutrition/hydration/caffeine/fasting, body measurements, local labs, readiness history/snapshots, settings, photos, schema version, manifest, checksums, timestamp, app version.
- **Restore:** validate before applying; detect unsupported/corrupt; display summary; **transactional** with rollback; no partial, no duplicates, preserve IDs, rebuild derived, **HealthKit reconcile separately**, request permissions again, never treat cached as app-owned, never blindly rewrite imported.
- Encryption deferred Pre-App Store Hardening. **Integrity, restoration, migration testing may NOT defer.**

## 6.19 Security & Privacy — Personal-Use Phase (Now)

Required:
- iOS file-data protection.
- Keychain for keys/credentials/secrets.
- No sensitive health in filenames.
- No sensitive health in ordinary logs.
- No ads/behavioral-analytics/unnecessary remote logging.
- No CloudKit health-records; no backend; no external health processing.
- Reliable backup/restore, archive validation, data-model migration.

**Deferred to Pre-App Store Hardening (Section 8):** Face ID/device lock, app-switcher blur, notification privacy, export encryption. Progress photos/labs/digestion sensitivity doesn't make Face ID current requirement.

## 6.20 Accessibility & Internationalization Readiness

- Urine/stool: numeric grades + text + VoiceOver + contrast + Dynamic Type; no color-alone.
- English-first; **all strings externalized** for Arabic later.
- Architecture ready: RTL layout, Arabic plurals, Hijri dates, locale formatting. Arabic UI not v1.

## 6.21 App Intents & Widgets

Architecture compatible with App Intents, Shortcuts, widgets, Siri. v1 deliberately small: **one-tap water logging**, **fasting timer**, widget actions. No voice-assistant.

---

# Build Order, Risks, Data Model, Acceptance Tests

## 7. Deferred (Phase 2+)

| Feature | Reason |
|---|---|
| AI Coach | Needs months data; v1 model must remain consumable |
| Personal Records (PRs) | Owner decision |
| Per-set RPE | Owner decision (session RPE in v1) |
| Arabic UI | English first; strings externalized |
| Menstrual cycle | Commercial multi-user version |
| Cloud sync | Local-only v1 |
| Photo AI calorie | Excluded |
| Android/Web | iOS native only |
| Watch companion app | WorkoutKit evaluation first |
| Calendar import (shifts) | Technical Spec evaluation; manual/recurring standalone |

## 8. Pre-App Store Hardening (Separate; Outside v1 Build)

Before public release: Face ID/device lock, app-switcher blur, notification privacy, export encryption, privacy policy, data-use wording, App Store health declarations, accessibility audit, **clinician review of medical advisories** (wording + escalation + emergency), legal review, analytics/crash assessment, App Store Guideline compliance. **Not v1 personal-use requirements.**

## 12. Build Order (Risk-First Vertical Slices)

1. **Foundation:** core shell, data-ownership boundaries, time/logical-day model (readiness-cycle concept), migrations, provenance, HealthKit sync foundation, backup foundation.
2. **Core daily slice:** profile, HealthKit sleep/vitals, mood/soreness check-in, provisional + final readiness, dashboard, daily guidance feedback.
3. **Hydration & caffeine:** unified drink logging, manual UX, basic reminders.
4. **Training:** programs, multi-sport sessions, session RPE + load, deloads, HealthKit import & merging.
5. **Nutrition:** quick entry, saved meals, food search, macro/fiber/sodium/sugar tracking.
6. **Fasting:** Day Type, IF, religious fasting, prayer-time engine, night windows.
7. **Body & wellness:** weight, composition, measurements, photos, local labs, supplements, injuries, tags.
8. **Regional food-data:** licensing verification, import pipeline, regional foods/recipes.
9. **Digestion & urination:** logging, hydration feedback, advisory framework.
10. **Insights:** trends, correlations, data-sufficiency. (Achievement calendar superseded by Activity Rings Calendar, §6.16, which builds with/after Slice 2.)
11. **Advanced notifications:** static reminders, contextual rules, suppression, Ramadan/fasting/shift precedence.
12. **Migration & completion:** full export/restore, migration testing, widgets, App Intents v1 actions.

Shift & Circadian support built into slices 1–2 (time/readiness/sleep) & 11 (notification precedence); Shift Schedule UI lands with slice 2 or own sub-slice. Circadian correctness is slice-1/2 foundation.

**After 12:** Pre-App Store Hardening (Section 8) — never v1 build order.

## 11. Assumptions & Risks

| # | Risk / Assumption | Mitigation |
|---|---|---|
| R-HK1 | HealthKit permission ambiguity (denial indistinguishable from no data) | Neutral no-data wording; contextual requests; per-metric fallback; never claim denial |
| R-HK2 | Background-sync limits (no guaranteed background delivery) | Foreground reconciliation every activation; pending-write queue + retry; no instant-sync promise |
| R-HK3 | Duplicate/conflict reconciliation (late samples, deletions, multi-source) | Idempotent sync contract; stable linkage; deletion handling; source-selection rule; merge audit |
| R-FOOD | Food-data licensing: access ≠ redistribution/caching/modification rights | Three-question verification (Tech Spec); fallback to global + user-regional; no unlicensed redistribution |
| R-RDY | Readiness quality with missing inputs | Confidence levels; missing-input indication; valid-day calibration; never zero-substitute |
| R-RAM | Prayer-time/Hijri-calendar variation (methods, local announces) | Method selection; offsets; manual city fallback; manual date/day correction |
| R-CORR | Correlation misinterpreted as causation | Guardrails 6.15: association language, sufficiency thresholds, confounder tags, limited-data states |
| R-BAK | Backup corruption or partial restoration | Manifest + checksums; pre-apply validation; transactional restore + rollback; migration testing pre-v1 done |
| R-BG | iOS background limits on "live" notifications & fasting suggestions | Pre-scheduled local notifications from app-open/log; per-rule feasibility check |
| R-SCOPE | Large scope for first native iOS app | Risk-first vertical slices; each slice standalone; periodic modules excluded from daily bar |
| R-NOTIF | Contextual notifications annoy → disabled | Individually toggleable; conservative defaults; suppression rules |

Mitigations reduce risk; none presented as eliminated.

## 10. High-Level Data Model (BRD Level — Detail in Tech Spec)

- **Profile** (stats, sports) / **GoalTargetSnapshot** (goal, date, formula, body stats, activity, adjustment, targets, overrides).
- **DayRecord** (date, Day Type) / **CircadianContext** (per cycle; transitions) / **ReadinessCycle** (primary waking → primary waking).
- **ShiftSchedule / ShiftOccurrence / ShiftType** (patterns; per-occurrence overrides).
- **SleepEpisode** (type: primary/nap/split/recovery/post-shift; provenance; user-correction flag).
- **NutritionLog** (timestamp, meal type, nutrients ± fiber/sodium/sugar) / **FoodItem** (provenance: DB, version, user-modified, prep, measurement) / **SavedMeal** / **NutritionWindow** (night window, religious fasts).
- **DrinkEntry** → **HydrationLog** + **CaffeineLog** (mg, time, sleep context) + NutritionLog.
- **DigestionLog** (Bristol, color, flags, context, advisory level) / **UrinationLog** (color grade 1–8).
- **Program → WorkoutDay → Exercise → SetEntry** (reps/time/distance; sport; deload) / **Session** (RPE, load, provenance) / **WorkoutMergeRecord** (sources, confidence, action, undo trail).
- **BodyCompositionMeasurement** (metric, source, conditions) / **CustomMeasurement** / **ProgressPhoto** / **LabResult** (local-only).
- **VitalsRecord** (RHR, HRV, steps, energy — provenance) / HR sample linkage.
- **MoodLog / SorenessLog / InjuryNote / SupplementPlan / SupplementLog / ContextEvent** (confounder tags).
- **FastingSession** (start, end, type: IF planned/confirmed/religious; dry flag; protocol; correction history) / **ReligiousFastSchedule** (Ramadan/Mon-Thu/White Days; Hijri; manual corrections) / **PrayerSettings** (method, offsets, manual city).
- **ReadinessRecord** (state, score, confidence, missing inputs, formula, snapshot, timestamp, recommendation, precedence, feedback + time; baseline: general/shift-specific/Ramadan).
- **HealthKitLink / SyncState** (per-record linkage, provenance, pending-write, deletion tombstones).
- **ActivityRingState** (derived, per logical day: hydration/training booleans; nutrition per-value hit/off/mess vs. Diet Profile target; digestion toggle + future fill rule; computed live, not cached) / **NotificationRule** (type, enabled, timing, suppression).
- **BackupManifest** (schema version, checksums, counts, timestamps, app version).

## Appendix A — Acceptance Test Scenarios (Must Pass Before v1 Done)

### A1 — Normal Training Day (Evening Workout)
Provisional readiness after primary sleep; final after mood/soreness (visually distinct) → contextual pre-lunch water suggestion fires per pattern → one latte entry distributes to hydration + caffeine + nutrition (single log) → meal-to-workout gap triggers snack suggestion → manual workout logged + Watch records; matches high-confidence, merges (no duplicate calories/duration/load; designated source used) → session RPE submitted; session load computed → dark urine logged → target-raise suggestion → guidance feedback (👍/👎) requested post-workout (not at display) → activity rings update.

### A2 — Ramadan Day with Pre-Iftar Workout
Day pre-typed Religious Fast by Ramadan schedule (user-correctable) → dry fast Fajr→Maghrib: no meal reminders, no water reminders, no IF suggestion, no "drink now" urine guidance → pre-iftar training classified religiously-fasted → **night window opens Maghrib**; nutrition totals & hydration reminders operate on night window with shift-aware cadence → suhoor 3:50 AM keeps real timestamp, remains in Maghrib→Fajr window (never split from iftar; global 04:00 logical day unchanged) → suhoor cutoff alert before Fajr → next cycle readiness against Ramadan baseline → user manually corrects prayer offset or religious date; schedule follows.

### A3 — Unplanned IF Morning
Normal day; no calories logged → threshold reached, app asks: *"No calories 14 hours. Are you fasting?"* (no certainty) → user confirms; Day Type flips to IF; meal reminders mute → water & black coffee logged; timer continues → calorie entry at 4 PM ends fast with duration → user later backdates forgotten 11 AM snack; fasting session shortens/invalidates per actual timestamp; dependent activity rings & insights recalculate.

### A4 — Phone Migration
Export ZIP (structured data + photos + manifest + checksums) → new install → archive validates (manifest + checksums; corrupt/unsupported detected & refused) → restore summary shown → transactional restore; simulated failure rolls back no partial state → app-owned IDs preserved; no duplicates → HealthKit permissions requested again → HealthKit reconciles separately; cached not treated as app-owned, nothing blindly rewritten → no duplicate workouts/measurements post-resync → notifications reconstructed where technical.

### A5 — HealthKit Permission & Missing-Data Day
Sleep read granted; HRV unavailable; steps permission never requested → app contextually requests steps when user opens activity features → HRV shows unavailable — never zero, never false "permission denied" claim; neutral wording guides to Health settings → readiness computes reduced confidence, lists missing inputs → no correlation silently substitutes zeros.

### A6 — HealthKit Correction & Reconciliation
Third-party workout arrives hours late → still matched/merged per confidence model → user deletes imported sample in Health → local representation inactive, summaries update → Almanac-created water entry fails HealthKit write → remains local with visible pending, succeeds on retry → repeated syncs create zero duplicates.

### A7 — Travel / Timezone Change
User flies to different timezone → existing records keep original timestamps/offsets; history unchanged → future prayer times recalculate new location (or manually chosen city) → logical-day grouping deterministic → user applies manual minute offset for iqama practice, corrects religious date; schedules follow.

### A8 — Rotating Night-Shift Transition
Stable day-schedule user switches to night shifts for month: app reads planned rotation → morning readiness & bedtime reminders stop firing → after first night shift, daytime HealthKit sleep classified **primary episode** (not nap) → readiness after that primary sleep / next main waking → general baseline used, reduced confidence, limited-comparable notice → day marked transition context → 21-day app calibration does **not** restart → night-shift-specific baseline activates after sufficient days (threshold: Tech Spec) → 8 AM caffeine interpreted late relative to 10 AM intended sleep → workouts/meals/fasting/timestamps correctly associated → user corrects misclassified sleep episode → Day Type & Circadian Context remain separate → future night-shift compared primarily against comparable night-shift records.
