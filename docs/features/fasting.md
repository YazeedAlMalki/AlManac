# Fasting — Slice 6 design, v1

**Status (2026-10-06): complete, and reachable from the running app.** Every
rule below was built and unit-tested by 2026-09-29; almost none of it ran on a
phone. Section 0 is what was wrong and what is now true. The sections after it
are the original design record, corrected where they had gone stale.

## 0. Completed 2026-10-06 — what was broken, what is now true

**Religious fasting never ran.** Nothing in the app ever created a
`religious_fast_schedule` row, so `isFastDay` was false on every date: no
Ramadan, no session, no night window, no suhoor or iftar reminder, no Ramadan
readiness baseline. `ReligiousFastScheduleStore.ensureRamadanSchedules` now
creates this Hijri year's Ramadan (if it has not ended) and next year's on every
refresh, inheriting the user's last on/off choice. Mondays and Thursdays and the
White Days are toggles on the Fasting screen. Any date can be marked or unmarked
by hand (`setManualFastDay`, logged on a `"manual"` schedule row; the newest
correction wins, and `"clear"` hands the date back to the calendar). Eid
al-Fitr, Eid al-Adha and the days of Tashreeq are never a voluntary fast day.

**A religious session is now derived, not accumulated.**
`ReligiousFastingService.ensureDay` computes the session from the schedule, the
day's Fajr and Maghrib, the first intake of any kind at or after Fajr
(`FastingIntakeLog`), and the time — and writes that. Before Fajr there is no
session; from Fajr it is open; at the first intake it ends there; at Maghrib,
unbroken, it ends at Maghrib. Because it is recomputed, it is right however the
facts changed: a drink from the widget, a meal moved in an editor, a deleted
entry, water imported from Apple Health, prayer times recalculated after travel,
a day un-marked. `FastingCoordinator.refresh` runs it for yesterday and today on
launch, on every foreground, after Health sync and on the Fasting screen.

Three defects that derivation removes:

- **Suhoor invalidated the day's fast.** The session was created at any hour, so
  one opened at 04:10 for a 04:50 Fajr; §11.1's backdating rule then saw a meal
  "before the session's start" and invalidated it, and suhoor water "ended" it
  with a negative duration. §11.1's tree no longer touches religious sessions,
  `recordIntake` ignores anything before the start, and no session exists before
  Fajr. Sessions an older build damaged are repaired on the next refresh.
- **Opened first after Maghrib, a fast stayed open** until the next refresh, and
  the iftar drink then "broke" it. It is now recorded as kept, at Maghrib.
- **The calendar date, not the logical day.** Riyadh's Fajr is 03:35 in June,
  before the 04:00 boundary, so the fast was looked for under the previous day.

**Logging never reached the rules.** `FastingAwareNutritionLog` and
`FastingAwareHydrationLog` existed and nothing called them; a logged lunch never
ended a fast. Every write path now goes through them — food logging and delete,
water and catalog drinks and delete, both Activity Rings editors and their
deletes, and the widget's water button — and they carry the night-window
assignment too, so no call site applies a rule by hand. Deleting the entry that
ended a fast gives the fast back (intermittent: through the same restore an edit
uses; religious: by re-derivation). A drink with calories now ends an
intermittent fast (§11.1: "any calorie-containing entry").

**Intermittent fasting:** the screen looked the fast up by today's logical day,
so one started at 20:00 vanished at 04:00 while still running and "Start" was
offered over it (and failed on the one-active index). It now shows the active
session whatever day it began, with a live timer and the protocol's target.
§11.1's suggestion ("No calories have been logged for N hours. Are you currently
fasting?") is on the screen: Yes starts an `if_confirmed_suggestion` session
from the last food log, No suppresses it for four hours; never on a religious
fast day, never with nothing logged. An intermittent fast still running at Fajr
on a fast day ends at Fajr so the religious one can open.

**The read side of §7.2 exists.** The Fasting screen shows the night window —
last night's during the day, tonight's after Maghrib — with what was eaten and
drunk in it, and the coming fast days with their reasons and Hijri dates.

**The widget** shows suhoor, the iftar countdown, broken or kept on a fast day,
from the same `ReligiousFastDay.phase` the screen uses; its End button ends only
an intermittent fast.

**Prayer times** (§12): see `docs/features/notifications.md` for the alerts, and
`Sources/AlmanacCore/Prayer/` for: the bundled city list is finally reachable
(a picker on the Prayer screen); a chosen city stays chosen — Core Location is
only fed in automatic mode, and only as a one-shot fix; a detected fix is named
after the nearest bundled city within 50 km instead of keeping the old city's
name; seven more calculation methods the vendored library already had, plus
custom angles; the Hanafi Asr (Migration050 `asrMethod`); per-prayer offsets on
screen; the Qibla bearing; and **Umm al-Qura's Ramadan Isha**, Maghrib + 120
minutes — the library leaves it to the caller, and every Ramadan Isha in the
default method was half an hour early. `ensureCache` also rebuilds a cache
computed for another place or method, which is how a settings write whose
recalculation never landed used to stay in force for a month.

**Decisions taken without the owner** are recorded in `CONTEXT.md` under
"Fasting and prayer (2026-10-06)".

## 1. Why this doc is short

The original brief for this slice posed ten open questions expecting a fresh
interview. Re-reading the recovered spec first turned out to answer nearly
all of them already, in more precision than a fresh design pass would have
produced. This doc records what's already decided (with citations), the two
real product/engineering decisions the spec left open and the owner made this
session, and what's left to actually build.

## 2. Already decided by the spec (no further design needed)

| Question from the original brief | Spec answer |
|---|---|
| IF suggestion trigger | App-side: no calorie entry for N hours (default 14, configurable) → *"No calories have been logged for [N] hours. Are you currently fasting?"* Yes → session starts retroactively from the last nutrition log's timestamp. No → suppress re-asking 4 hours. (§11.1) |
| Fast-breaking rules | Water and black coffee/tea (`caffeineMg > 0 AND calories = 0`) never break a fast; any `calories > 0` entry breaks it immediately. (§11.1) |
| Backdated meal entry | Entry timestamp before session start → invalidate the whole session (`isInvalidated = 1`). Entry timestamp inside the session → shorten it (`endTimestamp` = entry time, recalculate duration). Both logged to `correctionHistory`, both trigger dependent achievement/insight recalculation. (§11.1) |
| Day Type + meal reminder precedence | `notification_rule` rows with `suppressDuringConfirmedFast = 1` are suppressed while a fast is active; the full cross-notification suppression matrix (meal, water, bedtime, supplement, suhoor, iftar, contextual snack/hydration, against dry-fast/confirmed-IF/night-shift/post-shift-sleep) is Appendix B, already complete. |
| Ramadan readiness baseline | Uses religious-fast days only; prior years count if ≥14 usable Ramadan days exist in history; otherwise general baseline + "Ramadan context — calibrating" notice. Never resets the 21-day app-wide calibration. (§9.8) |
| Day Type switching / amendment | `day_record.dayType` (`normal|if|religious`) and `dayTypeSource` (`default|planned|user_set|suggested_confirmed`) are both mutable on the one row per calendar date — amending after the fact is just updating that row, no separate versioning table needed. (§5.3) |
| Suhoor/night-nutrition boundary | `nutrition_window` (`standard_logical_day` vs `night_nutrition_window`) spans Maghrib(D)→Fajr(D+1); a 03:50 suhoor entry belongs to day D's night window, never D+1's — the global 04:00 logical-day boundary never moves for this. (§5.11, §7.2) |
| Shift-aware religious fasting | The Fajr→Maghrib dry-fast window is fixed regardless of shift; only the night nutrition window's *notification cadence* (not its timestamps) is shift-aware. (§11.3) |
| Travel / timezone safety | >50 km movement invalidates and recalculates the 30-day prayer cache and reschedules suhoor/iftar; historical `prayer_times_cache` rows are never altered. (§12.4) |
| Calendar honesty | Every calculated religious-fast day (Ramadan/Mon-Thu/White Days) can be manually added or removed; every correction is logged in `religious_fast_schedule.manualCorrections`. (§11.2) |

## 3. Decided this session (the spec left these open)

**Ramadan/White-Days detection: auto-create, always manually correctable.**
When the calculated Islamic calendar says a day is a fast day, the app creates
the `fasting_session`/`religious_fast_schedule` rows automatically — no daily
confirmation tap — but every day can be added or removed by hand, logged in
`manualCorrections` per §11.2 above. Rejected alternative: suggest-only,
requiring confirmation every cycle — more taps for no accuracy gain once the
calendar source itself (§3.1 below) is trustworthy.

**Prayer-time calculation: vendor a proven open-source Adhan port**, rather
than hand-writing the solar-position formulas. Candidate: `batoulapps/Adhan`
(has a Swift target; MIT-licensed) vendored as source, same pattern already
used for `Sources/CSQLite`. Concrete port choice and licence-header check is a
build-time task, not a design one — flag it as the first step whenever this
slice is picked up.

**Built 2026-09-17:** `batoulapps/adhan-swift` (commit `0bc1000`, 2026-08-21)
vendored verbatim into `Sources/Adhan/` — see `Sources/Adhan/VENDORED.md` for
the exact files and re-vendoring instructions.
`Sources/AlmanacCore/Prayer/AdhanCalculator.swift` wraps it:
`AdhanCalculator.prayerTimes(latitude:longitude:date:timeZone:method:)` →
`[PrayerTime]` (`name`/`timestamp` pairs matching `prayer_times_cache`'s own
column names), with `PrayerCalculationMethod` mapping §5.22's
`calculationMethod` vocabulary (`umm_al_qura`/`mwl`/`isna`/`egypt`/`karachi`/
`custom`) onto Adhan's own `CalculationMethod`. Verified for Riyadh
(24.7136°N, 46.6753°E) on 2026-09-17 against `api.aladhan.com`'s method-4
(Umm al-Qura) output — Fajr/Sunrise/Dhuhr/Maghrib/Isha matched to the minute,
Asr within a minute. 5 tests
(`Tests/AlmanacCoreTests/AdhanCalculatorTests.swift`).

Not built: `PrayerTimeStore`/the 30-day cache, >50 km travel invalidation,
the bundled 200+-city manual-override JSON, and `PrayerSettingsStore` — all
of §12 beyond the calculation itself. `AdhanCalculator` is a pure function
today; nothing calls or persists it yet.

**Hijri calendar source:** use Foundation's built-in
`Calendar(identifier: .islamicUmmAlQura)` for Ramadan-month and White-Days
(13–15 Hijri) detection and Mon/Thu recurrence — no third-party calendar
library needed, and it matches `prayer_settings.calculationMethod`'s own
default (`umm_al_qura`). This wasn't an open question in the original brief
but falls directly out of the "no external APIs" constraint plus the
auto-detect decision above, so it's recorded here rather than left implicit.

**Progress-photo comparison UX** — not this slice's concern; recorded in
`docs/features/body-composition.md` §1 (deferred by the owner, unrelated to
fasting).

## 4. Schema — for the migration whenever this slice is picked up

Verbatim from spec §5.21–5.22 (fasting) plus §5.11 (nutrition_window, shared
with nutrition but only ever populated by this slice):

```sql
CREATE TABLE fasting_session (
    id                  INTEGER PRIMARY KEY,
    startTimestamp      TEXT NOT NULL,
    endTimestamp        TEXT,            -- null = active session
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,
    sessionType         TEXT NOT NULL,   -- if_planned | if_confirmed_suggestion | religious
    isDryFast           INTEGER NOT NULL DEFAULT 0,
    protocol            TEXT,            -- 16_8 | 18_6 | omad | custom | null
    windowHours         REAL,
    isActive            INTEGER NOT NULL DEFAULT 0,
    isInvalidated       INTEGER NOT NULL DEFAULT 0,
    finalDurationMinutes INTEGER,
    correctionHistory   TEXT NOT NULL DEFAULT '[]',
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);

CREATE TABLE religious_fast_schedule (
    id                  INTEGER PRIMARY KEY,
    scheduleType        TEXT NOT NULL,  -- ramadan | mon_thu | white_days
    hijriYear           INTEGER,
    startGregorianDate  TEXT,
    endGregorianDate    TEXT,
    isActive            INTEGER NOT NULL DEFAULT 1,
    manualCorrections   TEXT NOT NULL DEFAULT '[]',
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);

CREATE TABLE prayer_settings (
    id                      INTEGER PRIMARY KEY DEFAULT 1,
    calculationMethod       TEXT NOT NULL DEFAULT 'umm_al_qura',
    customFajrAngleDeg      REAL,
    customIshaAngleDeg      REAL,
    latitude                REAL,
    longitude               REAL,
    city                    TEXT,
    country                 TEXT,
    manualCityOverride      INTEGER NOT NULL DEFAULT 0,
    fajrOffsetMin           INTEGER NOT NULL DEFAULT 0,
    dhuhrOffsetMin          INTEGER NOT NULL DEFAULT 0,
    asrOffsetMin            INTEGER NOT NULL DEFAULT 0,
    maghribOffsetMin        INTEGER NOT NULL DEFAULT 0,
    ishaOffsetMin           INTEGER NOT NULL DEFAULT 0,
    timezone                TEXT NOT NULL DEFAULT 'Asia/Riyadh',
    updatedAt               TEXT NOT NULL
);

CREATE TABLE prayer_times_cache (
    id                  INTEGER PRIMARY KEY,
    date                TEXT NOT NULL UNIQUE,
    fajr TEXT NOT NULL, sunrise TEXT NOT NULL, dhuhr TEXT NOT NULL,
    asr TEXT NOT NULL, maghrib TEXT NOT NULL, isha TEXT NOT NULL,
    latitude REAL NOT NULL, longitude REAL NOT NULL,
    calculationMethod TEXT NOT NULL,
    isManualOverride INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL
);

CREATE TABLE nutrition_window (
    id              INTEGER PRIMARY KEY,
    date            TEXT NOT NULL,
    windowType      TEXT NOT NULL,  -- standard_logical_day | night_nutrition_window
    startTimestamp  TEXT NOT NULL,
    endTimestamp    TEXT NOT NULL,
    fajrTimestamp   TEXT,
    maghribTimestamp TEXT,
    createdAt       TEXT NOT NULL
);
```

`day_record.dayType`/`dayTypeSource` already exist (Migration014) — no change
needed there.

## 5. What's built (2026-09-17) vs. what's next

Built: `fasting_session` only (migration 022 — not 021's full §4 list; the
other four tables are still just design). `FastingSessionStore.start` +
`recordNutritionEntry` implement §11.1's break/invalidate/shorten decision
tree exactly (`Sources/AlmanacCore/Fasting/`), plus `IFSuggestion.shouldSuggest`
for the 14-hour trigger. A partial unique index
(`idx_fasting_session_one_active`) enforces "only one active session at a
time" at the schema level — beyond the spec's literal text, added because
the break/backdate logic assumes it.

One deliberate scope line: backdating only reconciles against the active
session or the single most-recently-started ended session — not an
arbitrary point in session history. Every example in §11.1 only needs that;
reconciling further back isn't attempted.

**2026-09-17, continued:** `IFSuggestionService` (`Sources/AlmanacCore/Fasting/`)
wires `IFSuggestion` to `NutritionLogStore`. `shouldSuggestFast(at:thresholdHours:)`
is the full trigger; `hoursSinceLastCalorieEntry(before:lookbackHours:)` is the
gap computation, exposed separately since a UI might want to show the number,
not just the boolean. 6 tests.

`ponytail:` "a calorie entry" here means *a food log entry with a stated
amount*, not a real computed kcal figure — an actual number needs
`NutritionCatalog`/`EnergyEstimate` (what `NutritionSummary` already does, at
real fixture cost: every reference food needs seeded nutrient values). A
false-positive prompt from an approximately-zero-calorie food is a minor
annoyance; the session-breaking logic (`FastingSessionStore.recordNutritionEntry`)
is the one that takes a real `calories` number, because breaking a session is
a real state change. Upgrade this if the coarse signal proves wrong in
practice.

**2026-09-17, continued:** `FastingAwareNutritionLog` (`Sources/AlmanacCore/Fasting/`)
wires `NutritionLogStore.record` to `FastingSessionStore.recordNutritionEntry`,
using the entry's *real* computed energy (`NutritionCatalog`/`EnergyEstimate`)
rather than `IFSuggestionService`'s coarser approximation — this one changes
stored fasting state (ends/shortens/invalidates a session), so it earns the
real number. Timestamp comes from the draft's own `eatenAt`, not "now" —
backdating is exactly what the break logic exists to reconcile. Kept
separate from `NutritionLogStore` itself (Nutrition doesn't know Fasting
exists, same dependency direction as `IFSuggestionService`). 4 tests,
including a real Atwater/publisher-energy fixture (no existing test seeded
one before this).

`FastingAwareNutritionLog.update` now mirrors that wiring for corrections:
it reads the held entry, recomputes energy from the edited food/amount, and
reconciles the edited occurrence. A correction that removes the calories can
restore a normally-ended or recently shortened fast; moving a previously
invalidated meal back into the session re-breaks it. The scope remains the
active session or the single most-recently-started affected session, as above.
Edit-path regression tests were added to the four create-path tests.

## 6. Build plan (religious fasting + prayer-time engine, next)

1. ~~New migration~~ — done 2026-09-17, Migration024, all four tables (§4
   above) transcribed verbatim.
2. ~~Vendor the Adhan port~~ — done 2026-09-17, `AdhanCalculator` (§3, §5
   above). ~~`PrayerTimeStore`/`PrayerSettingsStore`~~ — also done, as
   `PrayerSettingsStore` + `PrayerTimeCacheStore` + `PrayerTimeEngine` (§12:
   30-day cache, >50 km travel invalidation via a real haversine check, a
   per-day `isManualOverride` flag protecting a corrected day from both).
   ~~The bundled 200+-city manual-fallback JSON~~ — done 2026-09-19:
   `Sources/AlmanacCore/Prayer/Resources/manual-cities.json` (230 cities,
   §12.2's `{ name, country, lat, lon, timezone }` schema verbatim) plus
   `ManualCityCatalog` (`Sources/AlmanacCore/Prayer/ManualCityCatalog.swift`)
   for `search(_:)`/`city(named:country:)` lookups. It only resolves a name
   to coordinates — same pattern as `AdhanCalculator` being a pure function
   with no store of its own — so a caller still applies the choice through
   `PrayerSettingsStore.updateLocation(..., manualCityOverride: true)`
   itself. 12 tests, including one that every bundled timezone identifier
   actually resolves via `TimeZone(identifier:)`.
3. ~~`FastingSessionStore` + `FastingEngine`~~ — done in the intermittent-
   fasting pass above (§5).
4. ~~`ReligiousFastScheduleStore` + auto-creation/auto-end~~ — done
   2026-09-17. `ReligiousFastScheduleStore` (fast-day detection: Ramadan
   against a stored range from the new `ramadanRange(hijriYear:)` helper,
   Mon/Thu and White Days matched live via
   `Calendar(identifier: .islamicUmmAlQura)` — confirmed correct on
   Linux/Swift 6.3.3, not just assumed) plus `ReligiousFastingService`
   (composes it with `FastingSessionStore`/`NutritionWindowStore` for the
   actual auto-create-at-Fajr/auto-end-at-Maghrib flow, §11.2).
5. ~~`NutritionWindowStore`~~ — done 2026-09-17: creation + timestamp-range
   lookup (`window(containing:)`, correctly handling a 03:50 suhoor entry on
   calendar day D+1 belonging to D's window). ~~The `nutritionWindowId`
   wiring~~ — also done, 2026-09-27: see "The night window, wired" below.
6. Notification suppression (Appendix B) — depends on whatever
   `NotificationScheduler` design Slice 11 (Advanced notifications) settles;
   flag as a cross-slice dependency rather than duplicating scheduling logic
   here.

### The night window, wired (2026-09-27)

`Migration044` adds `nutrition_window_id` to `nutrition_log` **and**
`hydration_log`, and `NightNutritionWindowAssigner`
(`Sources/AlmanacCore/Fasting/NightNutritionWindowAssigner.swift`) applies §7.2's
rule. Three things about it are decisions, not mechanics:

- **snake_case, and on both tables.** The spec gives the column on
  `nutrition_log` (§5.11) and not on `hydration_log` (§5.13), while §7.2's own
  prose says "any NutritionLog *or HydrationLog*". The rule is followed and the
  contradiction recorded in `docs/architecture/spec-reconciliation.md`. Naming
  follows the two tables it sits in, not §5.11's camelCase, for the reason in
  that doc's §3.
- **Matching is by timestamp, never by logical day.** The two rules disagree
  between 04:00 and Fajr — at 04:10 Riyadh on D+1 the logical day is already
  D+1 while the fast is still running, and the window wins. At the spec's own
  03:50 example they agree, which is why that example is not the interesting
  case; the test that pins the rule down uses 04:10.
- **Coarse timestamps are left unassigned.** A `"2026-09"` value spans the
  window on paper but has no instant for `Maghrib(D) ≤ timestamp < Fajr(D+1)` to
  be true of. Unassigned is the honest column value; assigned would be a guess
  that reads as a fact.

**Wired into six write paths,** because every one of them sets the timestamp the
rule is defined against: `NutritionModel.log`, `HydrationModel.log`,
`HydrationModel.logDrink`, both Activity Rings day-detail editors
(`editLoggedAt`, and the nutrition `update` when it moves `eatenAt`), and the
widget's `LogWaterIntent`. **This is a discipline cost, not a design** — the
seventh path added later will be the one that forgets, and nothing enforces it.
`ReligiousFastingService.ensureDay` re-resolves the window it just created, which
covers the common miss (the user marks the day *after* eating iftar) but not the
edit paths. A whole-history `assignUnassigned()` is the backstop and is spec line
1942 step 6d's "Rebuild nutrition_window assignments for religious fast days";
it is **not yet called from the restore procedure**, which is not built.

**Dry-fast break rule (decided 2026-09-29).** The service used to leave this
open in a doc comment, because §11.1's rules were written for intermittent
fasting and do not say what water does to a *religious* fast. The owner's call:
**any intake ends a dry fast, water included** — a dry fast that was drunk from
is not a fast that was kept, so the session ends and records the real duration
rather than claiming a completed fast. It is `end`, not `invalidate`: the hours
before the intake were genuinely fasted, and the record should say so.

- `FastingSessionStore.recordIntake(at:)` owns the rule, as a **separate
  method** rather than a flag on `recordNutritionEntry`. `recordNutritionEntry`
  keeps §11.1 untouched — it still returns `.noOp` for `calories == 0` — so
  intermittent fasting is unaffected. A test pins that: water does not break an
  IF session.
- `FastingAwareHydrationLog` is the wrapper, same shape and same dependency
  direction as `FastingAwareNutritionLog` (Hydration must not know Fasting
  exists). It records the drink first and unconditionally: a broken fast is
  still a real thing the user drank.
- ~~Not wired into the hydration write paths yet.~~ **Wired 2026-10-06**, into
  all of them, and the religious half is now also derived from the log on every
  refresh, so a path that is missed costs one refresh rather than a wrong fast
  (§0).

**The night window is no longer lost for the day (fixed 2026-09-29).** Window
creation used to sit inside the session-*creation* branch, gated on
`nextDayFajr` being non-nil, while every later call returned earlier at the
already-exists branch. The first `ensureDay` of a day routinely runs before
tomorrow's Fajr is in the prayer cache, so it created the session with no
window — and the window was then unrecoverable for the rest of that day, leaving
every suhoor and iftar entry in it unassigned. A test had encoded this as
expected behaviour. `ensureDay` now ensures the window on *every* call,
idempotently by lookup (`nutrition_window` has no uniqueness constraint on
(date, windowType), so the lookup is what prevents duplicates).

**Two things this did not settle:**

- **`day_record.dayType` is never set to `religious`** (raised 2026-09-29, still
  open — a genuine product decision, not a bug). `ensureDay` creates the
  `fasting_session` row, but nothing types the *day*. This blocks more than it
  looks: the Appendix B suppression matrix and the §9.8 Ramadan readiness
  baseline both key off `dayType`, so Slice 11's notification scheduler and the
  readiness integration work are both only half-buildable until it is answered.
  It does **not** block the dry-fast break rule above, which is a property of
  the session rather than the day.
- `nutrition_window.windowType` is now a Swift enum (`NutritionWindowType`)
  rather than a raw `String`. Its `standardLogicalDay` case is reachable and
  never written: the spec names it as a possible value and then gives no rule
  for creating one. Inventing one would be a product decision nobody has made.
- The spec's `mealType` includes `suhoor` and `iftar` (§5.11), which is how a
  reader would expect an entry to be *marked* as suhoor. `NutritionMealType` has
  four cases and can express neither. The assignment rule does not need it — it
  is timestamp-based — but nothing in the app can currently label an entry as
  the meal the whole feature is organised around.

**What calls this, and what still doesn't.** (Corrected 2026-09-27: this
paragraph previously said "nothing yet", which had gone stale — `ensureDay` has
a production caller, and so does the night-window assigner.)

| Surface | Called by |
| --- | --- |
| `ReligiousFastingService.ensureDay` | `FastingModel.ensureToday()`, the Fasting screen's own load |
| `NightNutritionWindowAssigner` | `ReligiousFastingService.ensureDay` (retroactively) plus six write paths — see above |
| `FastingAwareHydrationLog` | `HydrationModel.log`/`logDrink`/`delete`, the Activity Rings hydration editor and delete, the widget's `LogWaterIntent` (2026-10-06) |
| `FastingAwareNutritionLog` | `NutritionModel.log`/`delete`, the Activity Rings nutrition editor and delete (2026-10-06) |
| `FastingCoordinator.refresh` | `FastingModel.ensureToday` — launch, every foreground, after Health sync, after prayer times change, the Fasting screen |
| `PrayerTimeEngine.ensureCache` | `PrayerModel.ensureCache` — launch and every foreground |

Still nothing: no shift-schedule UI. ~~No screen displays a night window's
contents~~ — the Fasting screen does, since 2026-10-06 (§0).
