# Fasting — Slice 6 design, v1

**Status:** all of §6's build plan is done except notification suppression
(step 6, blocked on Slice 11) and the `nutritionWindowId` cross-module wiring
(step 5's second half). Intermittent fasting core (migration 022):
`fasting_session`, `FastingSessionStore`, `IFSuggestion`. Prayer-time
calculation: vendored `Adhan`, `AdhanCalculator`. Religious fasting +
prayer infrastructure (migration 024): `religious_fast_schedule` +
`ReligiousFastScheduleStore`, `prayer_settings` + `PrayerSettingsStore`,
`prayer_times_cache` + `PrayerTimeCacheStore` + `PrayerTimeEngine`,
`nutrition_window` + `NutritionWindowStore`, and `ReligiousFastingService`
tying the auto-create/auto-end flow together. 67 tests across this slice,
green. Nothing calls any of it yet — see §6's closing note. Schema and
engine logic transcribed verbatim from `../../../almanac-tech-spec-v1.0.md`
§5.21–5.22, §7.2, §11–14, Appendix B — the recovered, authoritative Technical
Spec (`docs/architecture/spec-reconciliation.md`).

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
   calendar day D+1 belonging to D's window). **Not done:** the
   `nutritionWindowId` wiring into `NutritionLogStore`/`HydrationLog` — that
   needs its own migration adding the column to each table, and touches two
   slices (Nutrition, Hydration) that don't currently know Fasting exists.
   Deliberately left as its own task rather than folded into this pass.
6. Notification suppression (Appendix B) — depends on whatever
   `NotificationScheduler` design Slice 11 (Advanced notifications) settles;
   flag as a cross-slice dependency rather than duplicating scheduling logic
   here.

**What calls any of this — nothing yet.** Every store/service above is a
pull-based, idempotent surface (`ensureDay`, `ensureCache`,
`applyLocationUpdate`) a caller is expected to invoke explicitly, the same
pattern `ReadinessModel.refresh()` uses. No UI, no app-launch wiring, and no
background scheduling exist to actually call them day to day yet — that's
Slice 2 UI's dashboard-integration territory (fasting status/prayer times on
the readiness dashboard) or a dedicated Fasting screen, neither built.
