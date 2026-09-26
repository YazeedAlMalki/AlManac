# Almanac — Technical Specification v1.0

**Product:** Almanac (previously "Athlete Tracker")
**Spec Version:** 1.0
**Date:** 2026-08-05
**Owner:** Yazeed
**Status:** Ready for Build (Claude Code)
**Derived from:** BRD v1.5 (2026-08-05)

**Version History**
- **1.0** — Initial Technical Specification. Covers: architecture; SQLite/GRDB.swift decision; complete database schema (48 tables); HealthKit read/write permission map; incremental sync algorithm; sleep classification and readiness-cycle linking rules; readiness formula v1.0 (provisional/final, confidence, calibration, baselines, precedence); workout merge confidence model; fasting engine (IF + religious); prayer-time engine (on-device, Umm al-Qura default); circadian context engine; notification scheduling design (all types, suppression matrix); goals & targets engine; backup/restore ZIP contract; complete screen map; food-database licensing flagged as open research item.

---

## Table of Contents

1. Scope of This Document
2. Owner Decisions (Pre-Spec Interview)
3. Architecture
4. Local Database — Engine, Library & Migration
5. Complete Database Schema
6. HealthKit Integration
7. Time & Day Model — Implementation Rules
8. Sleep Classification & Readiness-Cycle Linking
9. Readiness Engine
10. Workout Merge Confidence Model
11. Fasting Engine
12. Prayer-Time Engine
13. Circadian Context Engine
14. Notification Scheduling Design
15. Goals & Targets Engine
16. Backup / Restore Contract
17. Screen Map
18. Food Database — Open Research Item
19. Accessibility Implementation Notes
20. Build Order Notes
21. Appendix A — Readiness Formula Reference Card
22. Appendix B — Notification Suppression Matrix
23. Appendix C — HealthKit Permission Map (Full Table)

---

## 1. Scope of This Document

This Technical Specification translates every requirement in BRD v1.5 into concrete, implementable decisions. It is the authoritative reference for building Almanac via Claude Code. Wherever BRD v1.5 deferred a decision to the Technical Spec ("algorithm in Technical Spec", "thresholds per Technical Spec", "Technical Spec decision"), this document provides that decision.

**What this document does NOT do:**
- Override any BRD v1.5 decision (conflicts must be raised with the owner before proceeding).
- Define visual design (colours, typography, spacing — a separate Design Reference document covers those).
- Resolve the food-database licensing question (Section 18 — open research item).
- Cover Pre-App Store Hardening items (BRD Section 8 — separate milestone).

---

## 2. Owner Decisions (Pre-Spec Interview)

The following decisions were confirmed by Yazeed before writing this spec:

| # | Topic | Decision |
|---|---|---|
| D-1 | App name | **Almanac** — confirmed. Bundle ID: `com.yazeed.almanac` |
| D-2 | Local database engine | **SQLite via GRDB.swift** (see Section 4) |
| D-3 | Primary navigation | **5-tab bar:** Home · Log · Train · Insights · Settings |
| D-4 | Log tab scope | All input modules (full list in Section 17) |
| D-5 | Insights tab scope | Trends · Correlations · Monthly Achievement Calendar |
| D-6 | Default notifications | **Conservative:** Readiness + Water + Suhoor/Iftar only ON by default |
| D-7 | Sleep episode correction | Available from **both** the Home/day view and the dedicated Sleep screen in Log |
| D-8 | Readiness display | **Number + Colour + Text description** (e.g., 🟢 78 · "Recovery is strong") |
| D-9 | Workout logging style | **Simple:** exercise → reps/weight → Done. No mandatory rest timer. |

---

## 3. Architecture

### 3.1 Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| Language | Swift 5.10+ | Native iOS; required by HealthKit and WorkoutKit |
| UI Framework | SwiftUI | Declarative, integrates cleanly with GRDB publishers |
| Local Persistence | SQLite via **GRDB.swift 6.x** | Full SQL control; excellent migration support; battle-tested; owner chose SQLite over SwiftData |
| HealthKit | HealthKit framework (iOS 17+) | Required for all health-data exchange (BRD Section 5) |
| Notifications | UserNotifications framework | Local notifications only; no push server |
| Location | Core Location | Prayer-time coordinate input; contextual use only |
| Cryptography | CryptoKit | Backup checksum (SHA-256) and future archive encryption |
| Minimum iOS | **iOS 17.0** | Required for GRDB 6 + modern SwiftUI features |
| Xcode | 16.x | Build environment |

### 3.2 Application Architecture Pattern

**MVVM + Repository + Service Layer**

```
View (SwiftUI)
    ↓ binds to
ViewModel (ObservableObject)
    ↓ calls
Repository (protocol) ← DatabaseRepository (GRDB) | MockRepository (tests)
    ↓ reads/writes
GRDB DatabaseQueue (SQLite file)

ViewModel also calls →
Service Layer:
  ReadinessEngine
  FastingEngine
  SyncService (HealthKit)
  NotificationService
  PrayerTimeEngine
  CircadianContextEngine
  BackupService
```

**Key principles:**
- All database access goes through repositories — no raw SQL in ViewModels or Views.
- Services are stateless where possible; state lives in the database.
- All repositories are protocol-typed so Claude Code can substitute mock implementations for testing without touching business logic.
- No singleton abuse — services are injected via the SwiftUI Environment.

### 3.3 Folder Structure

```
Almanac/
├── AlmanacApp.swift
├── AppEnvironment.swift          (dependency injection container)
├── Core/
│   ├── Database/
│   │   ├── DatabaseManager.swift
│   │   ├── Migrations/
│   │   │   ├── Migration_001_Initial.swift
│   │   │   └── ... (one file per migration)
│   │   └── Records/              (GRDB FetchableRecord / PersistableRecord types)
│   ├── HealthKit/
│   │   ├── HealthKitManager.swift
│   │   ├── SyncService.swift
│   │   ├── SyncAnchorStore.swift
│   │   └── PendingWriteQueue.swift
│   ├── Notifications/
│   │   ├── NotificationService.swift
│   │   └── NotificationRuleEngine.swift
│   ├── PrayerTime/
│   │   ├── PrayerTimeEngine.swift
│   │   └── SolarCalculator.swift
│   ├── Readiness/
│   │   ├── ReadinessEngine.swift
│   │   └── BaselineManager.swift
│   ├── Fasting/
│   │   └── FastingEngine.swift
│   ├── Circadian/
│   │   └── CircadianContextEngine.swift
│   └── Backup/
│       ├── BackupService.swift
│       └── RestoreService.swift
├── Repositories/
│   ├── Protocols/                (e.g., NutritionRepositoryProtocol.swift)
│   └── Implementations/          (e.g., GRDBNutritionRepository.swift)
├── Features/
│   ├── Home/
│   ├── Log/
│   │   ├── Nutrition/
│   │   ├── Hydration/
│   │   ├── Sleep/
│   │   ├── Digestion/
│   │   ├── Fasting/
│   │   ├── Mood/
│   │   ├── Injuries/
│   │   ├── ContextTags/
│   │   ├── Supplements/
│   │   └── Body/
│   ├── Train/
│   ├── Insights/
│   └── Settings/
├── Shared/
│   ├── Components/               (reusable SwiftUI views)
│   ├── Extensions/
│   ├── Utils/
│   └── Constants.swift
└── Resources/
    ├── en.lproj/Localizable.strings
    └── Assets.xcassets
```

---

## 4. Local Database — Engine, Library & Migration

### 4.1 Engine & Library

- **Engine:** SQLite (bundled with iOS — no additional binary)
- **Library:** GRDB.swift 6.x (Swift Package Manager dependency)
- **Database file location:** `Application Support/almanac.db` (protected by `NSFileProtectionComplete`)
- **WAL mode:** enabled — better read concurrency during sync
- **DatabaseQueue:** single serial queue — thread-safe by design

### 4.2 Migration Strategy

Each schema change is a numbered, append-only migration class conforming to a `Migration` protocol:

```swift
struct Migration_001_Initial: Migration {
    func migrate(_ db: Database) throws {
        // CREATE TABLE statements
    }
}
```

GRDB's `DatabaseMigrator` runs migrations in order on first launch and after updates. **Migrations never roll back** — additive changes only (add column, add table). Destructive changes require a new table + data copy + drop old pattern.

Migration versions are stored in GRDB's internal `grdb_migrations` table. The current schema version is embedded in every backup manifest (Section 16).

### 4.3 Foreign Key Enforcement

```sql
PRAGMA foreign_keys = ON;
```

Set on every new connection via GRDB's `configuration.prepareDatabase`.

---

## 5. Complete Database Schema

All tables use INTEGER primary keys (auto-increment) unless noted. Timestamps are stored as ISO 8601 strings with timezone offset (e.g., `"2026-08-05T14:30:00+03:00"`). Booleans are stored as INTEGER (0/1). JSON arrays/objects are stored as TEXT (validated at the Swift layer).

---

### 5.1 Profile

```sql
CREATE TABLE profile (
    id                  INTEGER PRIMARY KEY,
    displayName         TEXT NOT NULL DEFAULT 'Yazeed',
    dateOfBirth         TEXT,          -- YYYY-MM-DD
    biologicalSex       TEXT,          -- male | female | other | not_set
    heightCm            REAL,
    sports              TEXT NOT NULL DEFAULT '[]',  -- JSON array
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
```

### 5.2 GoalTargetSnapshot

Records the active targets for each period. A new row is inserted whenever a goal changes; rows are never updated (immutable history).

```sql
CREATE TABLE goal_target_snapshot (
    id                      INTEGER PRIMARY KEY,
    effectiveDate           TEXT NOT NULL,  -- YYYY-MM-DD, start of this target period
    goal                    TEXT NOT NULL,  -- bulk | cut | maintain | performance
    formulaVersion          TEXT NOT NULL DEFAULT '1.0',
    bodyWeightKg            REAL,
    bodyFatPct              REAL,
    activityMultiplier      REAL,
    goalCalorieAdjustment   INTEGER,        -- kcal delta for goal (e.g., +300 bulk, -500 cut)
    -- Generated targets
    calorieTarget           INTEGER,
    proteinTargetG          REAL,
    carbTargetG             REAL,
    fatTargetG              REAL,
    hydrationTargetMl       INTEGER,
    -- Manual overrides (nullable = not overridden)
    manualCalorieTarget     INTEGER,
    manualProteinTargetG    REAL,
    manualCarbTargetG       REAL,
    manualFatTargetG        REAL,
    manualHydrationTargetMl INTEGER,
    createdAt               TEXT NOT NULL
);
```

### 5.3 DayRecord

One row per calendar date. Created lazily on first log of the day.

```sql
CREATE TABLE day_record (
    id              INTEGER PRIMARY KEY,
    date            TEXT NOT NULL UNIQUE,  -- YYYY-MM-DD (calendar date)
    dayType         TEXT NOT NULL DEFAULT 'normal',  -- normal | if | religious
    dayTypeSource   TEXT NOT NULL DEFAULT 'default', -- default | planned | user_set | suggested_confirmed
    circadianContextId INTEGER REFERENCES circadian_context(id),
    createdAt       TEXT NOT NULL,
    updatedAt       TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_day_record_date ON day_record(date);
```

### 5.4 CircadianContext

One row per readiness cycle. Linked from DayRecord and ReadinessCycle.

```sql
CREATE TABLE circadian_context (
    id              INTEGER PRIMARY KEY,
    date            TEXT NOT NULL,  -- YYYY-MM-DD of the cycle's anchor day
    shiftType       TEXT,           -- day | evening | night | split | on_call | rest | custom | null (not scheduled)
    contextType     TEXT NOT NULL,  -- stable_day | stable_evening | stable_night |
                                    -- transition_earlier | transition_later |
                                    -- first_day_after_night | recovery | irregular | unknown
    transitionDayN  INTEGER,        -- 1,2,3... for transition_earlier/later context
    notes           TEXT,
    createdAt       TEXT NOT NULL
);
```

### 5.5 ShiftSchedule

```sql
CREATE TABLE shift_schedule (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL DEFAULT 'My Schedule',
    isActive    INTEGER NOT NULL DEFAULT 1,
    createdAt   TEXT NOT NULL,
    updatedAt   TEXT NOT NULL
);

CREATE TABLE shift_occurrence (
    id                      INTEGER PRIMARY KEY,
    scheduleId              INTEGER NOT NULL REFERENCES shift_schedule(id),
    date                    TEXT NOT NULL,  -- YYYY-MM-DD
    shiftType               TEXT NOT NULL,  -- day | evening | night | split | on_call | rest | custom
    shiftStartTime          TEXT,           -- HH:MM local
    shiftEndTime            TEXT,           -- HH:MM local (may be next calendar day)
    expectedSleepWindowStart TEXT,          -- HH:MM local
    expectedSleepWindowEnd   TEXT,          -- HH:MM local
    expectedWakeTime        TEXT,           -- HH:MM local
    isManualOverride        INTEGER NOT NULL DEFAULT 0,
    recurrencePatternId     INTEGER REFERENCES shift_recurrence_pattern(id),
    notes                   TEXT,
    createdAt               TEXT NOT NULL
);
CREATE INDEX idx_shift_occurrence_date ON shift_occurrence(date);

CREATE TABLE shift_recurrence_pattern (
    id              INTEGER PRIMARY KEY,
    scheduleId      INTEGER NOT NULL REFERENCES shift_schedule(id),
    patternType     TEXT NOT NULL,  -- weekly | monthly_rotation | custom
    shiftSequence   TEXT NOT NULL,  -- JSON array of shiftType per day/week
    startDate       TEXT NOT NULL,
    endDate         TEXT,
    createdAt       TEXT NOT NULL
);
```

### 5.6 SleepEpisode

```sql
CREATE TABLE sleep_episode (
    id                  INTEGER PRIMARY KEY,
    startTimestamp      TEXT NOT NULL,
    endTimestamp        TEXT NOT NULL,
    timezoneOffset      TEXT NOT NULL,  -- e.g., "+03:00"
    durationMinutes     INTEGER NOT NULL,  -- derived, stored for query performance
    episodeType         TEXT NOT NULL,  -- primary | nap | split | recovery | post_shift
    source              TEXT NOT NULL,  -- healthkit | manual | app_generated
    healthKitUUID       TEXT UNIQUE,    -- nullable for manual entries
    sourceApp           TEXT,
    sourceDevice        TEXT,
    userCorrectedType   TEXT,           -- null if not corrected
    userCorrectedAt     TEXT,
    readinessCycleId    INTEGER REFERENCES readiness_cycle(id),
    logicalDay          TEXT NOT NULL,  -- YYYY-MM-DD (04:00 boundary)
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
CREATE INDEX idx_sleep_episode_start ON sleep_episode(startTimestamp);
CREATE INDEX idx_sleep_episode_cycle ON sleep_episode(readinessCycleId);
```

### 5.7 ReadinessCycle

One row per waking cycle (primary waking → next primary waking).

```sql
CREATE TABLE readiness_cycle (
    id                      INTEGER PRIMARY KEY,
    anchorDate              TEXT NOT NULL,  -- YYYY-MM-DD of the waking day
    primaryWakeTimestamp    TEXT,           -- null until primary sleep detected/entered
    cycleStartTimestamp     TEXT,           -- = primaryWakeTimestamp of this cycle
    cycleEndTimestamp       TEXT,           -- = primaryWakeTimestamp of NEXT cycle (null if current)
    primarySleepEpisodeId   INTEGER REFERENCES sleep_episode(id),
    circadianContextId      INTEGER REFERENCES circadian_context(id),
    createdAt               TEXT NOT NULL,
    updatedAt               TEXT NOT NULL
);
CREATE INDEX idx_readiness_cycle_date ON readiness_cycle(anchorDate);
```

### 5.8 NutritionLog

```sql
CREATE TABLE nutrition_log (
    id                  INTEGER PRIMARY KEY,
    timestamp           TEXT NOT NULL,
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,       -- YYYY-MM-DD (04:00 boundary)
    nutritionWindowId   INTEGER REFERENCES nutrition_window(id),  -- non-null on religious fast days
    mealType            TEXT NOT NULL,       -- breakfast | lunch | dinner | snack |
                                             -- pre_workout | post_workout | suhoor | iftar | custom
    mealTypeSuggested   INTEGER NOT NULL DEFAULT 0,  -- 1 = app suggested, user confirmed
    -- Nutrients
    calories            REAL NOT NULL DEFAULT 0,
    proteinG            REAL NOT NULL DEFAULT 0,
    carbsG              REAL NOT NULL DEFAULT 0,
    fatG                REAL NOT NULL DEFAULT 0,
    fiberG              REAL,
    sodiumMg            REAL,
    sugarG              REAL,
    -- Source linkage
    source              TEXT NOT NULL,       -- food_db | saved_meal | quick_entry | manual | drink_entry
    foodItemId          INTEGER REFERENCES food_item(id),
    savedMealId         INTEGER REFERENCES saved_meal(id),
    drinkEntryId        INTEGER REFERENCES drink_entry(id),
    servingSize         REAL,
    servingUnit         TEXT,
    -- Provenance
    provenance          TEXT NOT NULL,       -- manual | healthkit_import | app_generated
    healthKitUUID       TEXT,
    notes               TEXT,
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
CREATE INDEX idx_nutrition_log_logical_day ON nutrition_log(logicalDay);
CREATE INDEX idx_nutrition_log_timestamp ON nutrition_log(timestamp);
```

### 5.9 FoodItem

```sql
CREATE TABLE food_item (
    id                  INTEGER PRIMARY KEY,
    name                TEXT NOT NULL,
    brand               TEXT,
    sourceDatabase      TEXT NOT NULL,  -- myfood24 | sfda | usda | open_food_facts | user_created
    sourceDatabaseVersion TEXT,
    sourceId            TEXT,           -- ID in the source database
    -- Nutrients per 100g (or per serving if measurementBasis = 'per_serving')
    caloriesPer100g     REAL,
    proteinPer100g      REAL,
    carbsPer100g        REAL,
    fatPer100g          REAL,
    fiberPer100g        REAL,
    sodiumPer100g       REAL,
    sugarPer100g        REAL,
    -- Serving info
    defaultServingG     REAL,
    servingUnit         TEXT,
    preparationState    TEXT,           -- raw | cooked | other
    measurementBasis    TEXT NOT NULL DEFAULT 'per_100g',  -- per_100g | per_serving
    -- Flags
    isUserModified      INTEGER NOT NULL DEFAULT 0,
    isUserCreated       INTEGER NOT NULL DEFAULT 0,
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
CREATE INDEX idx_food_item_name ON food_item(name);
CREATE INDEX idx_food_item_source ON food_item(sourceDatabase, sourceId);
```

### 5.10 SavedMeal

```sql
CREATE TABLE saved_meal (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    components      TEXT NOT NULL,   -- JSON: [{foodItemId, servingG, ...}]
    totalCalories   REAL NOT NULL,
    totalProteinG   REAL NOT NULL,
    totalCarbsG     REAL NOT NULL,
    totalFatG       REAL NOT NULL,
    totalFiberG     REAL,
    totalSodiumMg   REAL,
    totalSugarG     REAL,
    lastUsedAt      TEXT,
    createdAt       TEXT NOT NULL,
    updatedAt       TEXT NOT NULL
);
```

### 5.11 NutritionWindow

```sql
CREATE TABLE nutrition_window (
    id              INTEGER PRIMARY KEY,
    date            TEXT NOT NULL,          -- YYYY-MM-DD (the religious fast day)
    windowType      TEXT NOT NULL,          -- standard_logical_day | night_nutrition_window
    startTimestamp  TEXT NOT NULL,          -- Maghrib timestamp for night window
    endTimestamp    TEXT NOT NULL,          -- next Fajr timestamp for night window
    fajrTimestamp   TEXT,
    maghribTimestamp TEXT,
    createdAt       TEXT NOT NULL
);
CREATE INDEX idx_nutrition_window_date ON nutrition_window(date);
```

### 5.12 DrinkEntry

Single entry that fans out to hydration, caffeine, and nutrition.

```sql
CREATE TABLE drink_entry (
    id              INTEGER PRIMARY KEY,
    timestamp       TEXT NOT NULL,
    timezoneOffset  TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    drinkType       TEXT NOT NULL,   -- water | coffee_black | coffee_latte | arabic_coffee |
                                     -- tea_black | tea_milk | energy_drink | juice | milk | custom
    drinkName       TEXT,            -- custom drink name
    fluidVolumeMl   REAL NOT NULL DEFAULT 0,
    caffeineMg      REAL NOT NULL DEFAULT 0,
    calories        REAL NOT NULL DEFAULT 0,
    proteinG        REAL NOT NULL DEFAULT 0,
    carbsG          REAL NOT NULL DEFAULT 0,
    fatG            REAL NOT NULL DEFAULT 0,
    notes           TEXT,
    createdAt       TEXT NOT NULL,
    updatedAt       TEXT NOT NULL
);
CREATE INDEX idx_drink_entry_logical_day ON drink_entry(logicalDay);
```

### 5.13 HydrationLog

```sql
CREATE TABLE hydration_log (
    id                  INTEGER PRIMARY KEY,
    drinkEntryId        INTEGER REFERENCES drink_entry(id),  -- null for standalone manual entry
    timestamp           TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,
    volumeMl            REAL NOT NULL,
    source              TEXT NOT NULL,  -- drink_entry | manual | healthkit_import
    healthKitUUID       TEXT UNIQUE,
    pendingHealthKitWrite INTEGER NOT NULL DEFAULT 0,  -- 1 = not yet written to HK
    createdAt           TEXT NOT NULL
);
```

### 5.14 CaffeineLog

```sql
CREATE TABLE caffeine_log (
    id                          INTEGER PRIMARY KEY,
    drinkEntryId                INTEGER REFERENCES drink_entry(id),
    timestamp                   TEXT NOT NULL,
    logicalDay                  TEXT NOT NULL,
    caffeineMg                  REAL NOT NULL,
    drinkType                   TEXT NOT NULL,
    -- Computed context (recalculated on sync/shift change)
    intendedSleepTimestamp      TEXT,      -- derived from shift schedule
    hoursBeforeIntendedSleep    REAL,      -- derived
    caffeineContext             TEXT,      -- early | normal | late | very_late (relative to intended sleep)
    createdAt                   TEXT NOT NULL
);
CREATE INDEX idx_caffeine_log_timestamp ON caffeine_log(timestamp);
```

### 5.15 DigestionLog

```sql
CREATE TABLE digestion_log (
    id                  INTEGER PRIMARY KEY,
    timestamp           TEXT NOT NULL,
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,
    bristolScale        INTEGER NOT NULL CHECK(bristolScale BETWEEN 1 AND 7),
    color               TEXT NOT NULL,  -- brown | pale | yellow | green | black |
                                        -- bright_red | dark_red
    bloodPresent        INTEGER NOT NULL DEFAULT 0,
    excessGas           INTEGER NOT NULL DEFAULT 0,
    notes               TEXT,
    harmlessContextNotes TEXT,          -- foods/supplements that may explain color
    advisoryLevel       INTEGER NOT NULL DEFAULT 1 CHECK(advisoryLevel BETWEEN 1 AND 3),
    -- 1=informational, 2=see professional, 3=urgent care
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
CREATE INDEX idx_digestion_log_logical_day ON digestion_log(logicalDay);
```

**Advisory level assignment rules (implemented in DigestiveAdvisoryEngine):**

| Condition | Level |
|---|---|
| No concerning flags | 1 |
| Green or pale stool (isolated) | 1 |
| Bristol 1–2 (isolated) | 1 |
| Bristol 6–7 (isolated) | 1 |
| Blood present (bright red, small amount, with harmless context noted) | 2 |
| Blood present (bright red, no harmless context) | 2 |
| Black/tar-like stool | 2 |
| Persistent same issue (≥2 logs within 24 h) | escalate by 1 |
| Blood present + dark / significant amount | 3 |
| Blood present + dizziness/faintness/weakness (captured in notes) | 3 |
| Bloody diarrhoea (blood + Bristol 6–7) | 3 |

*Level 3 wording is flagged for clinician review in Pre-App Store Hardening (BRD Section 8).*

### 5.16 UrinationLog

```sql
CREATE TABLE urination_log (
    id              INTEGER PRIMARY KEY,
    timestamp       TEXT NOT NULL,
    timezoneOffset  TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    colorGrade      INTEGER NOT NULL CHECK(colorGrade BETWEEN 1 AND 8),
    -- 1=pale straw (optimal), 8=dark brown (severely dehydrated)
    notes           TEXT,
    createdAt       TEXT NOT NULL
);
```

**Urine color grades:**

| Grade | Description | Hydration indication |
|---|---|---|
| 1 | Pale straw / nearly clear | Over-hydrated |
| 2 | Pale yellow | Well-hydrated |
| 3 | Yellow | Good |
| 4 | Dark yellow | Adequate, drink soon |
| 5 | Amber | Under-hydrated |
| 6 | Orange | Significantly under-hydrated |
| 7 | Brown | Severely under-hydrated / see professional |
| 8 | Dark brown / other | Seek professional advice |

Feedback rule: grade ≥ 5 despite meeting hydration target → suggest target increase. **Suspended during religious dry fast.** Grade ≤ 1 → suggest slight target reduction. These thresholds are on-screen recommendations, not notifications.

### 5.17 Training Tables

```sql
CREATE TABLE program (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    sport           TEXT NOT NULL,   -- bodybuilding | endurance | fencing | mixed | custom
    description     TEXT,
    durationWeeks   INTEGER,
    isTemplate      INTEGER NOT NULL DEFAULT 0,
    isActive        INTEGER NOT NULL DEFAULT 0,
    createdAt       TEXT NOT NULL,
    updatedAt       TEXT NOT NULL
);

CREATE TABLE workout_day (
    id              INTEGER PRIMARY KEY,
    programId       INTEGER NOT NULL REFERENCES program(id) ON DELETE CASCADE,
    weekNumber      INTEGER NOT NULL,
    dayNumber       INTEGER NOT NULL,   -- 1–7
    name            TEXT NOT NULL,
    sport           TEXT NOT NULL,
    isRestDay       INTEGER NOT NULL DEFAULT 0,
    isDeloadDay     INTEGER NOT NULL DEFAULT 0,
    notes           TEXT
);

CREATE TABLE exercise (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    sport           TEXT NOT NULL,
    category        TEXT,              -- push | pull | legs | core | cardio | drill | ...
    exerciseType    TEXT NOT NULL,     -- reps | time | distance | rounds
    muscleGroups    TEXT NOT NULL DEFAULT '[]',  -- JSON array
    instructions    TEXT,
    isCustom        INTEGER NOT NULL DEFAULT 0,
    createdAt       TEXT NOT NULL,
    updatedAt       TEXT NOT NULL
);

CREATE TABLE workout_day_exercise (
    id              INTEGER PRIMARY KEY,
    workoutDayId    INTEGER NOT NULL REFERENCES workout_day(id) ON DELETE CASCADE,
    exerciseId      INTEGER NOT NULL REFERENCES exercise(id),
    orderIndex      INTEGER NOT NULL,
    targetSets      INTEGER,
    targetReps      INTEGER,
    targetWeightKg  REAL,
    targetDurationSec INTEGER,
    targetDistanceM REAL,
    targetRounds    INTEGER,
    notes           TEXT
);

CREATE TABLE session (
    id                  INTEGER PRIMARY KEY,
    timestamp           TEXT NOT NULL,        -- session start
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,
    programId           INTEGER REFERENCES program(id),
    workoutDayId        INTEGER REFERENCES workout_day(id),
    sport               TEXT NOT NULL,
    name                TEXT NOT NULL,
    durationMinutes     INTEGER,
    sessionRPE          INTEGER CHECK(sessionRPE BETWEEN 1 AND 10),
    sessionLoad         INTEGER,              -- = durationMinutes × sessionRPE (computed, stored)
    notes               TEXT,
    isPlanned           INTEGER NOT NULL DEFAULT 0,
    isCompleted         INTEGER NOT NULL DEFAULT 0,
    isFasted            INTEGER NOT NULL DEFAULT 0,
    fastType            TEXT NOT NULL DEFAULT 'none',   -- none | if | religious
    source              TEXT NOT NULL DEFAULT 'manual', -- manual | healthkit | merged
    healthKitWorkoutUUID TEXT,
    circadianContextId  INTEGER REFERENCES circadian_context(id),
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
CREATE INDEX idx_session_logical_day ON session(logicalDay);

CREATE TABLE set_entry (
    id              INTEGER PRIMARY KEY,
    sessionId       INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
    exerciseId      INTEGER NOT NULL REFERENCES exercise(id),
    exerciseName    TEXT NOT NULL,     -- denormalised for display after exercise edits
    setNumber       INTEGER NOT NULL,
    reps            INTEGER,
    weightKg        REAL,
    durationSec     INTEGER,
    distanceM       REAL,
    rounds          INTEGER,
    notes           TEXT,
    completedAt     TEXT NOT NULL
);

CREATE TABLE workout_merge_record (
    id                  INTEGER PRIMARY KEY,
    primarySessionId    INTEGER NOT NULL REFERENCES session(id),
    mergedSessionId     INTEGER REFERENCES session(id),   -- null if unmatched HK import
    healthKitWorkoutUUID TEXT,
    mergeConfidence     TEXT NOT NULL,  -- high | medium | low
    mergeScore          INTEGER NOT NULL,
    mergeFactors        TEXT NOT NULL,  -- JSON: {timeOverlap, startDiff, durationSimilarity, ...}
    mergeAction         TEXT NOT NULL,  -- auto_merged | user_confirmed | user_rejected | undone
    calorieSource       TEXT,           -- healthkit | manual | none
    heartRateSource     TEXT,           -- healthkit | none
    mergedAt            TEXT,
    undoneAt            TEXT,
    createdAt           TEXT NOT NULL
);
```

### 5.18 Body Composition Tables

```sql
CREATE TABLE body_composition_measurement (
    id              INTEGER PRIMARY KEY,
    timestamp       TEXT NOT NULL,
    timezoneOffset  TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    metric          TEXT NOT NULL,  -- weight | body_fat_pct | lean_mass_kg |
                                    -- skeletal_muscle_kg | visceral_rating
    value           REAL NOT NULL,
    unit            TEXT NOT NULL,  -- kg | pct | rating
    source          TEXT NOT NULL,  -- apple_health | inbody | smart_scale | manual
    conditions      TEXT NOT NULL DEFAULT 'unknown',  -- fasted | non_fasted | unknown
    healthKitUUID   TEXT UNIQUE,
    pendingHealthKitWrite INTEGER NOT NULL DEFAULT 0,
    createdAt       TEXT NOT NULL
);
CREATE INDEX idx_body_comp_metric ON body_composition_measurement(metric, timestamp);

CREATE TABLE custom_measurement_definition (
    id      INTEGER PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    unit    TEXT NOT NULL,
    createdAt TEXT NOT NULL
);

CREATE TABLE custom_measurement_log (
    id              INTEGER PRIMARY KEY,
    definitionId    INTEGER NOT NULL REFERENCES custom_measurement_definition(id),
    timestamp       TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    value           REAL NOT NULL,
    notes           TEXT,
    createdAt       TEXT NOT NULL
);

CREATE TABLE progress_photo (
    id          INTEGER PRIMARY KEY,
    timestamp   TEXT NOT NULL,
    logicalDay  TEXT NOT NULL,
    filename    TEXT NOT NULL UNIQUE,  -- UUID-based, no PII in filename
    pose        TEXT,                  -- front | side | back | custom
    notes       TEXT,
    createdAt   TEXT NOT NULL
);

CREATE TABLE lab_result (
    id                  INTEGER PRIMARY KEY,
    testDate            TEXT NOT NULL,  -- YYYY-MM-DD
    testName            TEXT NOT NULL,
    value               REAL NOT NULL,
    unit                TEXT NOT NULL,
    referenceRangeMin   REAL,
    referenceRangeMax   REAL,
    notes               TEXT,
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
```

### 5.19 Vitals & Activity

```sql
CREATE TABLE vitals_record (
    id              INTEGER PRIMARY KEY,
    timestamp       TEXT NOT NULL,
    timezoneOffset  TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    metric          TEXT NOT NULL,  -- rhr | hrv_sdnn | steps | active_energy_kcal
    value           REAL NOT NULL,
    unit            TEXT NOT NULL,
    source          TEXT NOT NULL,  -- healthkit | manual
    healthKitUUID   TEXT UNIQUE,
    createdAt       TEXT NOT NULL
);
CREATE INDEX idx_vitals_metric ON vitals_record(metric, timestamp);
```

### 5.20 Wellness Tables

```sql
CREATE TABLE mood_log (
    id                  INTEGER PRIMARY KEY,
    timestamp           TEXT NOT NULL,
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,
    score               INTEGER NOT NULL CHECK(score BETWEEN 1 AND 10),
    readinessCycleId    INTEGER REFERENCES readiness_cycle(id),
    notes               TEXT,
    createdAt           TEXT NOT NULL
);

CREATE TABLE soreness_log (
    id                  INTEGER PRIMARY KEY,
    timestamp           TEXT NOT NULL,
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,
    overallScore        INTEGER NOT NULL CHECK(overallScore BETWEEN 1 AND 10),
    bodyAreas           TEXT NOT NULL DEFAULT '[]',  -- JSON array of strings
    readinessCycleId    INTEGER REFERENCES readiness_cycle(id),
    notes               TEXT,
    createdAt           TEXT NOT NULL
);

CREATE TABLE injury_note (
    id              INTEGER PRIMARY KEY,
    startDate       TEXT NOT NULL,  -- YYYY-MM-DD
    endDate         TEXT,           -- null = still active
    bodyArea        TEXT NOT NULL,
    description     TEXT NOT NULL,
    isActive        INTEGER NOT NULL DEFAULT 1,
    affectsTraining INTEGER NOT NULL DEFAULT 1,
    createdAt       TEXT NOT NULL,
    updatedAt       TEXT NOT NULL
);

CREATE TABLE supplement_plan (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    doseAmount  REAL NOT NULL,
    doseUnit    TEXT NOT NULL,   -- g | mg | ml | tablet | capsule | scoop
    frequency   TEXT NOT NULL,  -- daily | twice_daily | pre_workout | custom
    timingNotes TEXT,
    isActive    INTEGER NOT NULL DEFAULT 1,
    createdAt   TEXT NOT NULL,
    updatedAt   TEXT NOT NULL
);

CREATE TABLE supplement_log (
    id              INTEGER PRIMARY KEY,
    planId          INTEGER NOT NULL REFERENCES supplement_plan(id),
    timestamp       TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    taken           INTEGER NOT NULL DEFAULT 1,
    notes           TEXT,
    createdAt       TEXT NOT NULL
);

CREATE TABLE context_event (
    id          INTEGER PRIMARY KEY,
    date        TEXT NOT NULL,  -- YYYY-MM-DD
    tags        TEXT NOT NULL DEFAULT '[]',
    -- Valid tags: illness | medication_change | travel_jet_lag |
    --             unusual_stress | heat_exposure | sauna |
    --             poor_watch_wear | late_night_event |
    --             sleep_interruption | competition_day
    notes       TEXT,
    createdAt   TEXT NOT NULL,
    updatedAt   TEXT NOT NULL
);
```

### 5.21 Fasting Tables

```sql
CREATE TABLE fasting_session (
    id                  INTEGER PRIMARY KEY,
    startTimestamp      TEXT NOT NULL,
    endTimestamp        TEXT,            -- null = active session
    timezoneOffset      TEXT NOT NULL,
    logicalDay          TEXT NOT NULL,   -- logical day session was started
    sessionType         TEXT NOT NULL,   -- if_planned | if_confirmed_suggestion | religious
    isDryFast           INTEGER NOT NULL DEFAULT 0,
    protocol            TEXT,            -- 16_8 | 18_6 | omad | custom | null
    windowHours         REAL,            -- for custom/tracking
    isActive            INTEGER NOT NULL DEFAULT 0,
    isInvalidated       INTEGER NOT NULL DEFAULT 0,  -- set by backdated entry
    finalDurationMinutes INTEGER,        -- set on end
    correctionHistory   TEXT NOT NULL DEFAULT '[]',  -- JSON audit trail
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);

CREATE TABLE religious_fast_schedule (
    id                  INTEGER PRIMARY KEY,
    scheduleType        TEXT NOT NULL,  -- ramadan | mon_thu | white_days
    -- For Ramadan: hijriYear, startGregorian, endGregorian
    hijriYear           INTEGER,
    startGregorianDate  TEXT,           -- YYYY-MM-DD
    endGregorianDate    TEXT,           -- YYYY-MM-DD
    isActive            INTEGER NOT NULL DEFAULT 1,
    manualCorrections   TEXT NOT NULL DEFAULT '[]',
    -- JSON: [{date: "YYYY-MM-DD", action: "add_fast" | "remove_fast", reason: "..."}]
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
```

### 5.22 Prayer Settings & Times

```sql
CREATE TABLE prayer_settings (
    id                      INTEGER PRIMARY KEY DEFAULT 1,
    -- Ensures only one row
    calculationMethod       TEXT NOT NULL DEFAULT 'umm_al_qura',
    -- umm_al_qura | mwl | isna | egypt | karachi | custom
    customFajrAngleDeg      REAL,
    customIshaAngleDeg      REAL,
    latitude                REAL,
    longitude               REAL,
    city                    TEXT,
    country                 TEXT,
    manualCityOverride      INTEGER NOT NULL DEFAULT 0,
    -- Per-prayer minute offsets
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
    date                TEXT NOT NULL UNIQUE,  -- YYYY-MM-DD
    fajr                TEXT NOT NULL,          -- full ISO 8601 timestamp
    sunrise             TEXT NOT NULL,
    dhuhr               TEXT NOT NULL,
    asr                 TEXT NOT NULL,
    maghrib             TEXT NOT NULL,
    isha                TEXT NOT NULL,
    latitude            REAL NOT NULL,
    longitude           REAL NOT NULL,
    calculationMethod   TEXT NOT NULL,
    isManualOverride    INTEGER NOT NULL DEFAULT 0,
    createdAt           TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_prayer_cache_date ON prayer_times_cache(date);
```

### 5.23 Readiness Tables

```sql
CREATE TABLE readiness_record (
    id                  INTEGER PRIMARY KEY,
    readinessCycleId    INTEGER NOT NULL REFERENCES readiness_cycle(id),
    anchorDate          TEXT NOT NULL,      -- YYYY-MM-DD
    state               TEXT NOT NULL,      -- provisional | final
    score               INTEGER,            -- 0–100; null if insufficient data
    colorGrade          TEXT,               -- green | yellow | red | none
    textDescription     TEXT,
    confidence          TEXT NOT NULL,      -- high | medium | low | very_low | insufficient
    missingInputs       TEXT NOT NULL DEFAULT '[]',
    -- JSON array: ["sleep","hrv","rhr","mood","soreness"]
    formulaVersion      TEXT NOT NULL DEFAULT '1.0',
    inputSnapshot       TEXT NOT NULL,      -- JSON: all raw input values used
    calculationTimestamp TEXT NOT NULL,
    recommendation      TEXT,
    precedenceApplied   TEXT NOT NULL DEFAULT '[]',
    -- JSON array: ["injury_restriction","rest_day","deload","religious_fast_context"]
    feedbackValue       TEXT,               -- thumbs_up | thumbs_down | null
    feedbackTimestamp   TEXT,
    baselineContext     TEXT NOT NULL DEFAULT 'general',
    -- general | shift_specific | ramadan | calibration
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);

CREATE TABLE readiness_baseline (
    id                  INTEGER PRIMARY KEY,
    baselineType        TEXT NOT NULL,      -- general | shift_specific | ramadan
    shiftType           TEXT,               -- null unless shift_specific
    validDayCount       INTEGER NOT NULL,
    rollingWindowDays   INTEGER NOT NULL,   -- 28 for general/shift, configurable for ramadan
    -- Baseline averages
    avgSleepDurationMin REAL,
    avgRHR              REAL,
    avgHRV              REAL,
    avgSoreness         REAL,
    avgMood             REAL,
    -- Period
    windowStartDate     TEXT NOT NULL,
    windowEndDate       TEXT NOT NULL,
    formulaVersion      TEXT NOT NULL DEFAULT '1.0',
    updatedAt           TEXT NOT NULL
);
```

### 5.24 HealthKit Sync Tables

```sql
CREATE TABLE healthkit_link (
    id                  INTEGER PRIMARY KEY,
    localEntityType     TEXT NOT NULL,   -- session | nutrition_log | hydration_log |
                                         -- body_composition | vitals | sleep_episode
    localEntityId       INTEGER NOT NULL,
    healthKitUUID       TEXT NOT NULL UNIQUE,
    syncState           TEXT NOT NULL,   -- synced | pending_write | pending_delete |
                                         -- failed | deleted_in_hk
    lastSyncAttempt     TEXT,
    failureReason       TEXT,
    sourceApp           TEXT,
    sourceDevice        TEXT,
    createdAt           TEXT NOT NULL,
    updatedAt           TEXT NOT NULL
);
CREATE INDEX idx_hk_link_entity ON healthkit_link(localEntityType, localEntityId);
CREATE INDEX idx_hk_link_state ON healthkit_link(syncState);

CREATE TABLE sync_anchor (
    id                  INTEGER PRIMARY KEY,
    sampleType          TEXT NOT NULL UNIQUE,  -- HK type identifier string
    anchorData          TEXT,                  -- base64-encoded HKQueryAnchor data
    lastSyncTimestamp   TEXT,
    updatedAt           TEXT NOT NULL
);
```

### 5.25 Achievements & Notifications

```sql
CREATE TABLE achievement_definition (
    id              INTEGER PRIMARY KEY,
    type            TEXT NOT NULL UNIQUE,
    -- steps_target | session_load_high | fasted_day | calorie_target_met |
    -- hydration_target_met | macro_target_met | perfect_log_day
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    icon            TEXT NOT NULL,       -- SF Symbol name
    metric          TEXT NOT NULL,
    threshold       REAL NOT NULL,
    isEnabled       INTEGER NOT NULL DEFAULT 1,
    createdAt       TEXT NOT NULL
);

CREATE TABLE day_achievement (
    id                      INTEGER PRIMARY KEY,
    date                    TEXT NOT NULL,   -- YYYY-MM-DD
    achievementDefinitionId INTEGER NOT NULL REFERENCES achievement_definition(id),
    value                   REAL NOT NULL,   -- the actual metric value on this day
    earnedAt                TEXT NOT NULL,
    needsRecalculation      INTEGER NOT NULL DEFAULT 0,
    UNIQUE(date, achievementDefinitionId)
);
CREATE INDEX idx_day_achievement_date ON day_achievement(date);

CREATE TABLE notification_rule (
    id                          INTEGER PRIMARY KEY,
    type                        TEXT NOT NULL UNIQUE,
    -- water | meal | bedtime | readiness | supplement | suhoor | iftar | contextual_snack |
    -- contextual_hydration
    isEnabled                   INTEGER NOT NULL DEFAULT 0,
    scheduledTimeHHMM           TEXT,       -- HH:MM for fixed-time notifications
    intervalMinutes             INTEGER,    -- for interval-based notifications
    suppressDuringConfirmedFast INTEGER NOT NULL DEFAULT 0,
    suppressDuringDryFast       INTEGER NOT NULL DEFAULT 0,
    suppressDuringNightShift    INTEGER NOT NULL DEFAULT 0,
    suppressDuringPostShiftSleep INTEGER NOT NULL DEFAULT 0,
    createdAt                   TEXT NOT NULL,
    updatedAt                   TEXT NOT NULL
);
```

**Default notification_rule rows (inserted in Migration_001):**

| type | isEnabled | suppressDuringDryFast | suppressDuringConfirmedFast |
|---|---|---|---|
| readiness | 1 | 0 | 0 |
| water | 1 | 1 | 0 |
| suhoor | 1 | 0 | 0 |
| iftar | 1 | 0 | 0 |
| meal | 0 | 0 | 1 |
| bedtime | 0 | 0 | 0 |
| supplement | 0 | 0 | 0 |
| contextual_snack | 0 | 0 | 1 |
| contextual_hydration | 0 | 1 | 0 |

---

## 6. HealthKit Integration

### 6.1 Permission Map

Permissions are requested **contextually** — when the user first accesses the relevant feature — not all at launch.

See **Appendix C** for the full table. Summary:

**READ (app observes, HealthKit authoritative):**
- `sleepAnalysis` → SleepEpisode
- `restingHeartRate` → VitalsRecord (rhr)
- `heartRateVariabilitySDNN` → VitalsRecord (hrv)
- `heartRate` → workout HR samples
- `stepCount` → VitalsRecord (steps)
- `activeEnergyBurned` → VitalsRecord (active_energy)
- `bodyMass` → BodyCompositionMeasurement (weight)
- `bodyFatPercentage` → BodyCompositionMeasurement (body_fat_pct)
- `leanBodyMass` → BodyCompositionMeasurement (lean_mass)
- `workoutType` → Session (healthkit import)
- Dietary types (energy, protein, carbs, fat, fiber, sodium, sugar, water) → read for import

**WRITE (app creates, pushes to HK):**
- `dietaryWater` ← HydrationLog
- `bodyMass` ← BodyCompositionMeasurement (weight)
- `bodyFatPercentage` ← BodyCompositionMeasurement (body_fat_pct)
- `leanBodyMass` ← BodyCompositionMeasurement (lean_mass)
- `workoutType` ← Session (app-recorded workouts)
- Dietary types ← NutritionLog (when source is within Almanac)

**NOT written to HealthKit (local-only):**
- Sleep episodes (read-only — HK authoritative)
- RHR, HRV, Steps, Active Energy (read-only — Watch authoritative)
- Readiness scores, mood, soreness, digestion, urination, fasting sessions, religious schedules, shift schedules, lab results, training program structures, injuries, supplements, context events

### 6.2 Incremental Sync Algorithm

The sync uses `HKAnchoredObjectQuery` for each data type. Anchors are persisted in `sync_anchor` table.

```
SYNC PROCEDURE (runs on every app foreground + background delivery):

For each data type T in [sleep, rhr, hrv, steps, active_energy, weight, body_fat,
                          lean_mass, workouts, dietary_types]:

  1. Load anchor A for type T from sync_anchor table.
  2. Execute HKAnchoredObjectQuery(type: T, predicate: nil, anchor: A, limit: HKObjectQueryNoLimit).
  3. For each NEW sample S in results:
       a. Check healthkit_link for S.uuid → if exists and syncState = 'synced': SKIP (idempotent).
       b. Map S to local record type.
       c. INSERT or UPDATE local record.
       d. Upsert healthkit_link (localEntityType, localEntityId, healthKitUUID, syncState='synced',
          sourceApp, sourceDevice).
  4. For each DELETED sample UUID in results:
       a. Find healthkit_link by healthKitUUID.
       b. Set syncState = 'deleted_in_hk'.
       c. Mark associated local record as inactive (do not hard-delete — preserve history).
  5. Update sync_anchor with new anchor from query result.
  6. Trigger derived-data recalculation where needed (sleep episodes → readiness cycle).

PENDING WRITE RETRY (runs after successful sync + on explicit retry):

  For each healthkit_link WHERE syncState IN ('pending_write', 'failed'):
    1. Reconstruct HKSample from local record.
    2. Call HKHealthStore.save(sample).
    3. On success: set syncState = 'synced'.
    4. On failure: increment retry count; set failureReason; show sync status badge.
    5. Maximum 5 automatic retries; after that, show persistent sync error to user.

MISSING DATA RULE:
  If a HKAnchoredObjectQuery returns 0 results AND no permission denial is detected:
    → Show: "No accessible [data type] data found. Check that [data source] was recorded
       and review Health access in Settings."
  NEVER claim permission was denied; NEVER treat missing data as zero.
```

### 6.3 Background Delivery

Register `HKObserverQuery` for all read types. iOS delivers a background notification when new data is available. The app runs the Sync Procedure in a background task (`BGProcessingTask` or `BGAppRefreshTask`). **No promise of instant or continuous background sync** — foreground sync on every activation is the primary path.

### 6.4 Workout Import & Merging

See Section 10 (Workout Merge Confidence Model).

### 6.5 Post-Restore Reconciliation

After a backup restore:
1. **Do not** replay cached HealthKit data back into HealthKit.
2. **Do not** treat imported HealthKit records as app-owned.
3. Clear all `sync_anchor` rows → forces full re-sync of HealthKit data.
4. Set all `healthkit_link` rows where `localEntityType` is a HealthKit-authoritative type to `syncState = 'pending_reconcile'`.
5. Prompt user to re-grant HealthKit permissions.
6. Run full Sync Procedure on next foreground.

---

## 7. Time & Day Model — Implementation Rules

### 7.1 Logical Day Calculation

```swift
func logicalDay(for timestamp: Date, timezone: TimeZone) -> DateComponents {
    // Logical day boundary: 04:00 local time
    let cutoff: TimeInterval = 4 * 3600  // 4 AM in seconds
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timezone
    let localComponents = cal.dateComponents([.year,.month,.day,.hour,.minute], from: timestamp)
    let localHour = localComponents.hour ?? 0
    let localMinute = localComponents.minute ?? 0
    let localSeconds = localHour * 3600 + localMinute * 60
    if localSeconds < cutoff {
        // Before 04:00 → belongs to the PREVIOUS calendar date's logical day
        let dayBefore = cal.date(byAdding: .day, value: -1, to: timestamp)!
        return cal.dateComponents([.year,.month,.day], from: dayBefore)
    } else {
        return cal.dateComponents([.year,.month,.day], from: timestamp)
    }
}
```

**Rule:** Records are NEVER re-timestamped. `logicalDay` is a derived, stored attribute updated once on insert. The original timestamp is always preserved.

### 7.2 Night Nutrition Window (Religious Fast Days)

On a religious fast day (dayType = 'religious'):

```
NightNutritionWindow.startTimestamp = Maghrib(D)
NightNutritionWindow.endTimestamp   = Fajr(D+1)
```

Any NutritionLog or HydrationLog with:
```
Maghrib(D) ≤ timestamp < Fajr(D+1)
```
is assigned to this window (via `nutritionWindowId`). This includes suhoor entries at e.g. 03:50 on calendar day D+1 — they remain in D's night window, NOT in D+1's window. The global 04:00 logical-day boundary is never altered.

**Implementation:** NutritionWindow rows are created automatically when a day is marked as Religious Fast and prayer times are available.

### 7.3 Readiness Cycle Boundaries

A Readiness Cycle = from one primary waking event to the next.

```
ReadinessCycle.cycleStartTimestamp = end of primary sleep episode (= primary wake time)
ReadinessCycle.cycleEndTimestamp   = start of NEXT primary sleep episode's end (the next wake)
```

Records associated with a cycle: all logs between `cycleStartTimestamp` and `cycleEndTimestamp`, **regardless of logical-day or calendar-date boundaries**.

### 7.4 Timezone Handling

- Every record stores the **timezone offset at the time of logging** (e.g., "+03:00").
- On travel: existing records are unchanged. Future prayer times and shift notifications recalculate for the new location.
- For queries spanning historical records: convert each record's timestamp to a consistent base (UTC) before comparing.

---

## 8. Sleep Classification & Readiness-Cycle Linking

### 8.1 Episode Detection from HealthKit

HealthKit delivers `HKCategorySample` records with `HKCategoryValueSleepAnalysis`:
- `inBed`, `asleepCore`, `asleepDeep`, `asleepREM`, `awake`

**Grouping rule:** Consecutive samples (any stage) with a gap ≤ 30 minutes between them are merged into a single `SleepEpisode`. Gap > 30 minutes → two separate episodes.

### 8.2 Primary Sleep Determination

Evaluated once per calendar day (or on-demand after shift change or manual correction). Priority order:

1. **User correction:** if the user has manually set `userCorrectedType = 'primary'` on an episode → that episode is primary. Honour unconditionally.

2. **Shift-aware algorithm (shift schedule is active and today's shift is known):**
   a. Load `expectedSleepWindowStart` and `expectedWakeTime` from `shift_occurrence` for today.
   b. Among all episodes on this logical day: find the episode whose end time is closest to `expectedWakeTime` AND whose duration is ≥ 2 hours.
   c. If found → primary.

3. **General algorithm (no shift data or step 2 found no candidate):**
   a. Among all episodes in a rolling 26-hour window centred on 04:00 local time today: select the episode with the **longest duration** that is ≥ 2 hours.
   b. If no episode ≥ 2 hours exists: select the longest episode regardless of duration.

4. **No episodes detected:**
   a. Check for manual sleep entry (source = 'manual').
   b. If none: `primarySleepEpisodeId = null`; readiness is triggered by app-open with a prompt asking the user to confirm or enter their sleep.

**Post-shift rule:** An episode that immediately follows the end of a night shift (episode start within 90 minutes of shift end time) is classified as `post_shift` rather than `nap`, and elevated to `primary` if it is the longest episode that day.

### 8.3 Episode Type Assignment

After primary is determined:
- The selected primary episode → `episodeType = 'primary'`
- All other episodes in the same day:
  - Duration ≥ 2 hours AND after a night shift → `post_shift`
  - Duration ≥ 90 minutes → `split` (candidate for user review)
  - Duration < 90 minutes → `nap`
- User-assigned recovery episodes: `recovery`

### 8.4 Readiness Cycle Linking

After primary sleep is determined for a cycle:

```
ReadinessCycle:
  anchorDate           = logical day of the wake time
  primaryWakeTimestamp = episode.endTimestamp
  primarySleepEpisodeId = episode.id
  cycleStartTimestamp  = episode.endTimestamp
  cycleEndTimestamp    = next cycle's cycleStartTimestamp (null if current cycle)
```

Link all logs created between `cycleStartTimestamp` and `cycleEndTimestamp`:
- `mood_log.readinessCycleId` = this cycle
- `soreness_log.readinessCycleId` = this cycle

### 8.5 Overlapping Multi-Source Samples

When HealthKit returns sleep samples from multiple apps (e.g., Apple Watch + AutoSleep):

**Source priority for summaries:**
1. Apple Watch native (sourceApp contains "com.apple.health" or device is Apple Watch)
2. Most recent third-party app with the longest continuous coverage
3. Manual entry

All samples are preserved with provenance. Only the designated source contributes to the episode used for readiness. Overlapping samples do **not** sum their durations.

---

## 9. Readiness Engine

### 9.1 Formula v1.0

**Five inputs, each normalised to 0–100, then weighted:**

| Input | Weight (Provisional) | Weight (Final) | Missing: |
|---|---|---|---|
| Sleep Duration Score | 33% | 30% | Reduce confidence, redistribute |
| Sleep Quality Score | 22% | 20% | Default to 50 (neutral), flag as missing |
| RHR Score | 22% | 20% | Exclude, redistribute |
| HRV Score | 23% | 20% | Exclude, redistribute |
| Mood + Soreness Score | 0% | 10% | N/A for provisional |

**Provisional readiness** = weighted sum of inputs 1–4 only, scaled so max = 90 (representing 90% confidence pending mood/soreness). The UI shows "+" or an indicator that final score will adjust after check-in.

**Final readiness** = all 5 inputs included.

**Redistribution on missing input:** If an input is missing, its weight is distributed proportionally among present inputs. If sleep duration AND quality AND RHR AND HRV are all missing → score = null, state = "Insufficient Data".

### 9.2 Input Scoring Functions

**Sleep Duration Score:**

| Duration | Score |
|---|---|
| < 4 hours | 10 |
| 4–5 hours | 30 |
| 5–6 hours | 55 |
| 6–7 hours | 75 |
| 7–9 hours | 100 |
| 9–10 hours | 90 |
| > 10 hours | 75 |

*Ramadan context modifier: fragmented sleep is expected. If dayType = 'religious' and total sleep across all episodes ≥ 5 hours: apply +10 bonus to duration score (cap at 100).*

**Sleep Quality Score (from HealthKit sleep stages):**

If stage data available:
```
qualityScore = (deepPct × 1.4 + remPct × 1.1 + corePct × 0.7) / 1.0 × 100
```
Capped at 100. If no stage data → score = 50, flagged as missing.

**RHR Score (vs personal baseline):**

```
delta = currentRHR - baselineRHR
if delta ≤ -2:   score = 100   // better than baseline
if delta ≤  0:   score = 95
if delta ≤  2:   score = 85
if delta ≤  4:   score = 65
if delta ≤  6:   score = 40
if delta >  6:   score = 15
```

**HRV Score (vs personal baseline):**

```
pctDiff = (currentHRV - baselineHRV) / baselineHRV × 100
if pctDiff ≥ +15%:   score = 100
if pctDiff ≥  +5%:   score = 90
if pctDiff ≥  -5%:   score = 75
if pctDiff ≥ -15%:   score = 50
if pctDiff ≥ -25%:   score = 30
if pctDiff <  -25%:  score = 10
```

**Mood + Soreness Score:**

```
moodNormalised     = moodScore / 10.0 × 100
sorenessNormalised = (10 - sorenessScore) / 10.0 × 100
                     // inverted: low soreness = high score
moodSorenessScore = (moodNormalised + sorenessNormalised) / 2
```

### 9.3 Colour Coding

| Score | Colour | Grade |
|---|---|---|
| 70–100 | 🟢 Green | green |
| 40–69 | 🟡 Yellow | yellow |
| 0–39 | 🔴 Red | red |
| null | ⚪ None | none |

### 9.4 Text Descriptions

| Score | Base Text |
|---|---|
| 85–100 | "Recovery is excellent — ready for maximum effort" |
| 70–84 | "Recovery is good — ready for a strong session" |
| 55–69 | "Moderate recovery — train at reduced intensity" |
| 40–54 | "Recovery is below baseline — consider a light session" |
| 25–39 | "Recovery is poor — prioritise rest today" |
| 0–24 | "Recovery is very low — rest is the best training decision" |

**Context suffixes (appended to base text):**

| Condition | Suffix |
|---|---|
| Religious fast day | "· Fasted training context noted" |
| Shift transition | "· Limited comparable shift data" |
| Deload week | "· Planned deload — continue reduced load" |
| Rest day | "· Planned rest day" |
| Active injury | "· Active injury: [bodyArea]" |
| Calibration | "· Score is preliminary (calibrating: X/21)" |

### 9.5 Confidence Levels

| Missing inputs | Confidence |
|---|---|
| 0 | High |
| 1 | Medium |
| 2 | Low |
| 3+ | Very Low |
| Unable to compute | Insufficient |

### 9.6 Recommendation Precedence

Applied in this strict order (first match wins):

1. **Active injury** (isActive = 1 AND affectsTraining = 1) → prepend injury note to recommendation; do not suppress score.
2. **Manually selected recovery day** (user set via UI) → "Recovery day: rest as planned."
3. **Planned rest day** (workoutDay.isRestDay = 1) → "Rest day as planned."
4. **Planned deload** (workoutDay.isDeloadDay = 1) → "Deload week: continue reduced load."
5. **Religious fast training** (dayType = 'religious' AND session planned pre-iftar) → note religiously-fasted context.
6. **Score-based recommendation** (Section 9.4 text + suffix).

**Example:** Score 90 + deload week → *"Recovery is excellent — ready for maximum effort. · Planned deload — continue reduced load."* — Never "Train hard."

### 9.7 Calibration

**Phase:** First 21 valid days from first use.

**Valid day definition:** A day where AT LEAST ONE of the following is present:
- Sleep data (HealthKit or manual entry)
- Both RHR and HRV readings

A day where none of these are available does NOT count toward the 21 days.

**UI during calibration:** Show `"Calibrating — Day X of 21 valid days"` where X = count of valid days so far. Score shown with label `"Preliminary estimate"`. Do not present as personalised or reliable.

**After calibration:** Full personalised scoring active. Rolling 28-valid-day window for baselines.

### 9.8 Baseline Management

Three baseline types, each a `ReadinessBaseline` row:

**General baseline:**
- Window: last 28 valid days (any schedule)
- Updated: daily after readiness calculation

**Shift-specific baseline:**
- Activated when: ≥ 14 valid days on the same shiftType
- Window: last 28 valid days with the same shiftType
- Falls back to general baseline + "limited comparable shift data" notice until activated

**Ramadan baseline:**
- Uses Ramadan days only (dayType = 'religious', scheduleType = 'ramadan')
- Prior years' Ramadan data may contribute if ≥ 14 usable Ramadan days exist in history
- Activated at start of Ramadan if prior data meets threshold; otherwise general baseline + "Ramadan context — calibrating" notice

**Shift schedule change:** Never resets 21-day application calibration. Shift-specific baseline for the new schedule begins accumulating independently.

### 9.9 Historical Integrity

When the readiness formula is updated:
- All historical `ReadinessRecord` rows retain their original `formulaVersion` and `inputSnapshot`.
- Historical scores are NEVER silently rewritten.
- Recalculated scores (for comparison or analytics) are stored in a separate table or clearly labelled.

### 9.10 Feedback Timing

The 👍/👎 feedback question is scheduled for delivery **after the outcome is known**:
- Post-workout: after the session is marked complete
- Non-training days: at the start of the next cycle (next wake)

It is NEVER shown immediately after the readiness score is displayed.

---

## 10. Workout Merge Confidence Model

### 10.1 Scoring Factors

A merge candidate pair = (ManualSession, HealthKitWorkout). Score = sum of factor scores (max 100):

| Factor | Max Points | Scoring Rule |
|---|---|---|
| **Time overlap** | 40 | Time intervals overlap: 40. Within 5 min of overlapping: 30. No overlap: 0. |
| **Start time difference** | 20 | ≤ 5 min: 20. ≤ 15 min: 15. ≤ 30 min: 10. > 30 min: 0. |
| **Duration similarity** | 20 | Within 5%: 20. Within 15%: 15. Within 30%: 10. > 30%: 0. |
| **Sport/type compatibility** | 15 | Exact match: 15. Compatible (e.g., "Strength" ≈ bodybuilding): 10. Unknown: 5. Incompatible: 0. |
| **Heart rate coverage** | 5 | HR data spans ≥ 80% of manual session time: 5. Otherwise: 0. |

### 10.2 Confidence Thresholds

| Score | Confidence | Action |
|---|---|---|
| ≥ 75 | High | Auto-merge (no user prompt) |
| 40–74 | Medium | Present merge suggestion; user confirms or rejects |
| < 40 | Low | Keep as separate sessions (no auto-action) |

### 10.3 Merge Rules

- **One-to-one only:** One HK workout may merge with at most one manual session. One manual session may merge with at most one HK workout.
- **Ambiguous multi-session match:** If one HK workout scores Medium with two different manual sessions → always request user confirmation for all candidates; never auto-merge.
- **No double-counting:** After merge, session record uses:
  - `calorieSource = healthkit` (HK calories preferred over manual estimate)
  - `heartRateSource = healthkit`
  - `durationMinutes` = the longer of the two (HK tends to be more accurate)
  - Session load = final duration × session RPE (from manual)
- **Late arrivals:** A HealthKit workout arriving up to **7 days** after the manual session remains eligible for merge proposal.
- **Audit trail:** Every merge action writes a `WorkoutMergeRecord`. Every merge is undoable. Undoing a merge restores both sessions to their pre-merge state.
- **Unmatched HealthKit workouts:** Imported as standalone sessions with `source = 'healthkit'` and `isPlanned = 0`.

---

## 11. Fasting Engine

### 11.1 Intermittent Fasting

**Suggestion trigger:** If no calorie-containing entries have been logged for N hours (default: 14 hours, user-configurable). Wording: *"No calories have been logged for [N] hours. Are you currently fasting?"*

- User taps "Yes" → `FastingSession` created with `sessionType = 'if_confirmed_suggestion'`, `startTimestamp` set to the timestamp of the last nutrition log.
- User taps "No" → no session created; suppress re-asking for 4 hours.
- Day Type flips to 'if' only after user confirmation.

**Planned fast:** user manually starts a timer. `sessionType = 'if_planned'`.

**Fast-breaking rules:**
- `fluidVolumeMl > 0 AND caffeineMg = 0 AND calories = 0` (water) → does NOT break fast
- `caffeineMg > 0 AND calories = 0` (black coffee/tea) → does NOT break fast
- `calories > 0` (ANY calorie-containing entry) → breaks fast immediately

**Break action:**
```
FastingSession.endTimestamp = entry.timestamp
FastingSession.isActive = 0
FastingSession.finalDurationMinutes = (endTimestamp - startTimestamp) in minutes
```

**Backdated calorie entry:**
```
If entry.timestamp < FastingSession.startTimestamp:
    → Invalidate session (isInvalidated = 1)
    → Add to correctionHistory

If FastingSession.startTimestamp ≤ entry.timestamp < FastingSession.endTimestamp:
    → Shorten session: set endTimestamp = entry.timestamp
    → Recalculate finalDurationMinutes
    → Add to correctionHistory

Trigger recalculation of: dependent achievements, insights
```

**Precedence:** When a fast is active, `notification_rule` rows with `suppressDuringConfirmedFast = 1` are suppressed in notification scheduling.

### 11.2 Religious Fasting

**Auto-creation:** When a `ReligiousFastSchedule` is active and prayer times are available for date D:
- Check if D is a fast day (within Ramadan range, or Mon/Thu, or White Day 13–15 Hijri).
- If yes and no `FastingSession` exists for D: create one automatically with:
  - `sessionType = 'religious'`
  - `isDryFast = 1`
  - `startTimestamp = Fajr(D)`
  - `endTimestamp = null` (still open during the day)
  - `isActive = 1`

**Auto-end:** At Maghrib(D), set `FastingSession.endTimestamp = Maghrib(D)`, `isActive = 0`.

**Night nutrition window:** Created alongside the fasting session (Section 7.2).

**Calendar honesty:** The app never assumes its Hijri calculation is accepted. The user can:
- Manually mark any day as a fast day (overrides calculation)
- Manually remove a calculated fast day
- All manual corrections logged in `ReligiousFastSchedule.manualCorrections`

### 11.3 Interaction with Shifts

Fasting and shift schedule are independent. A night-shift worker on Ramadan:
- The Fajr→Maghrib dry-fast window is unchanged (prayer times, not shift times)
- The night nutrition window (Maghrib→Fajr) may overlap with a work shift
- Notification cadence for suhoor/iftar respects both the shift schedule and the fasting state

---

## 12. Prayer-Time Engine

### 12.1 Calculation Methods

Implemented on-device using the **Adhan algorithm** (well-tested Swift port: `adhan-swift` library or equivalent).

| Method ID | Name | Fajr Angle | Isha Calculation |
|---|---|---|---|
| `umm_al_qura` | Umm al-Qura (Saudi Arabia) | 18.5° | Maghrib + 90 min |
| `mwl` | Muslim World League | 18° | 17° |
| `isna` | ISNA (North America) | 15° | 15° |
| `egypt` | Egyptian General Authority | 19.5° | 17.5° |
| `karachi` | University of Islamic Sciences, Karachi | 18° | 18° |

**Default:** `umm_al_qura` (most commonly used in Saudi Arabia).

### 12.2 Coordinate Sourcing

Priority:
1. User's current Core Location (requested contextually on first religious fasting feature use).
2. Manual city selection from a bundled list of major cities with coordinates.
3. Last known coordinates (for offline/travel scenarios).

**Manual city fallback:** Bundled JSON with 200+ cities: `{ name, country, lat, lon, timezone }`. City selection persists in `prayer_settings.city`, `prayer_settings.latitude`, `prayer_settings.longitude`, `prayer_settings.manualCityOverride = 1`.

### 12.3 Caching

Pre-calculate **30 days ahead** whenever:
- Prayer settings change (method, location, offsets)
- Location changes by > 50 km
- App launches and fewer than 7 days are cached

Stored in `prayer_times_cache`. One row per day.

Calculation steps:
```
For each date D in [today, today+30]:
  1. Calculate base prayer times using adhan algorithm for (lat, lon, date, method).
  2. Apply per-prayer minute offsets from prayer_settings.
  3. Convert to ISO 8601 with timezone offset.
  4. Upsert into prayer_times_cache (unique on date).
```

### 12.4 Travel Handling

On Core Location update:
1. If new coordinate is > 50 km from stored coordinate: update `prayer_settings.latitude/longitude`.
2. Set `prayer_settings.manualCityOverride = 0`.
3. Invalidate future `prayer_times_cache` rows (date > today).
4. Recalculate 30-day cache for new coordinates.
5. Reschedule Suhoor/Iftar notifications.

**Historical prayer times:** Never altered. Past dates in `prayer_times_cache` are preserved as-is.

---

## 13. Circadian Context Engine

### 13.1 Context Determination

Run once per readiness cycle, after primary sleep is identified. Inputs: shift_occurrence for today and yesterday.

```
currentShift  = shift_occurrence.shiftType for anchorDate
previousShift = shift_occurrence.shiftType for anchorDate - 1 day

if currentShift = previousShift AND stable for ≥ 5 days:
    if currentShift = 'day':     contextType = 'stable_day'
    if currentShift = 'evening': contextType = 'stable_evening'
    if currentShift = 'night':   contextType = 'stable_night'

else if currentShift ≠ previousShift:
    transition = classify_transition(previousShift, currentShift)
    // e.g. night→day = 'transition_earlier', day→night = 'transition_later'
    transitionDayN = days since last shift type change

else if transitionDayN ≤ 3:
    contextType = 'transition_earlier' or 'transition_later' (as above)

if currentShift = 'rest':  contextType = 'recovery'
if currentShift = null:    contextType = 'unknown'
```

### 13.2 Usage

- `readiness_record.baselineContext` uses shift-specific baseline if shiftType is stable and ≥14 comparable days exist.
- Notification scheduling reads `circadian_context` to suppress inappropriate notifications.
- Insights use `circadian_context.contextType` as a filter/confounder.
- `transition_earlier` / `transition_later` states add a readiness text suffix (Section 9.4).

---

## 14. Notification Scheduling Design

### 14.1 Architecture

All notifications are **local** (UNUserNotificationCenter). No push server.

**Scheduling triggers** — the notification engine runs on:
1. App launch / foreground activation
2. After any log entry that changes state (day type change, fast confirmation, session complete)
3. After shift schedule change
4. After prayer times recalculate

**Scheduling horizon:** Up to **48 hours** ahead (respects iOS notification scheduling limits).

**On each scheduling run:**
1. Cancel all pending non-critical notifications (preserving already-delivered ones).
2. Load: current day type, active fasting session, today's shift, prayer times, current time.
3. Apply suppression matrix (Appendix B).
4. Schedule new notifications per rules below.

### 14.2 Notification Types & Scheduling Rules

**Readiness Check-in Notification**
- Trigger: end of detected primary sleep episode OR estimated wake time (from shift schedule or 7-day average wake time).
- Title: "Morning check-in" / "Post-sleep check-in" (shift-aware label — never "morning" for evening/night schedules).
- Body: "How are you feeling? Log your mood and soreness to finalise today's readiness."
- Suppression: during post-shift sleep; if user already submitted final readiness this cycle.

**Water Reminder**
- Schedule: every `intervalMinutes` minutes during the user's active window.
- Active window = `expectedWakeTime` to (`expectedSleepWindowStart` - 2 hours).
- Default interval: 90 minutes.
- Suppression: during religious dry fast (`suppressDuringDryFast = 1`).

**Suhoor Cutoff Alert**
- Trigger: 20 minutes before Fajr on religious fast days.
- Title: "Suhoor — 20 minutes remaining"
- Body: "Fajr is at [time]. Fast begins soon."
- Enabled automatically when a Ramadan or recurring religious fast schedule is active.

**Iftar Notification**
- Trigger: at Maghrib on religious fast days.
- Title: "Iftar time 🌙"
- Body: "Maghrib is now. Your fast has ended."
- Enabled automatically when a religious fast schedule is active.

**Meal Logging Reminder**
- Default: OFF. User sets preferred times.
- Suppression: `suppressDuringConfirmedFast = 1`.
- Never sent if a fasting session is active.

**Bedtime Reminder**
- Default: OFF.
- Timing: relative to `expectedSleepWindowStart` from shift_occurrence (e.g., 30 min before). Falls back to user-set time.
- Suppression: if current shift = 'night' (`suppressDuringNightShift = 1`).

**Supplement Reminders**
- Default: OFF per supplement.
- User sets time per supplement plan.
- One notification per active supplement at its configured time.

**Contextual: Pre-workout Snack Suggestion**
- Default: OFF.
- Trigger: when gap between last logged meal and planned workout start > user's configured threshold (default: 3 hours).
- Body: "Your workout is in [X] hours. Consider a snack — a banana or similar fast carb."
- Computed at log time and at app launch.

**Contextual: Pre-meal Hydration Suggestion**
- Default: OFF.
- Trigger: ~60 min before usual meal time (derived from last 14 days of logged meal timestamps).
- Body: "Your usual [meal] is about an hour away. Drinking 200 ml now can help with hunger."
- Suppression: `suppressDuringDryFast = 1`.

### 14.3 Notification Text — Discretion Rules

Notification bodies do NOT expose:
- Bristol stool scale details
- Digestion advisory levels
- Specific lab values
- Progress photo details

Notification bodies for wellness topics use neutral language.

---

## 15. Goals & Targets Engine

### 15.1 Formula (Version 1.0)

Calorie target uses **Mifflin-St Jeor** BMR + activity multiplier + goal adjustment:

```
BMR (male) = 10 × weightKg + 6.25 × heightCm - 5 × age + 5
BMR (female) = 10 × weightKg + 6.25 × heightCm - 5 × age - 161

TDEE = BMR × activityMultiplier

Activity multiplier:
  Sedentary:         1.2
  Lightly active:    1.375
  Moderately active: 1.55
  Very active:       1.725
  Extremely active:  1.9

Goal adjustment:
  Bulk:        TDEE + 300 kcal
  Cut:         TDEE - 500 kcal
  Maintain:    TDEE
  Performance: TDEE + 150 kcal

calorieTarget = TDEE + goalAdjustment
```

**Macro targets (v1.0):**

```
proteinTarget = 2.2g × leanBodyMassKg (if known) or 2.0g × bodyWeightKg
fatTarget     = 0.9g × bodyWeightKg
carbTarget    = (calorieTarget - protein×4 - fat×9) / 4
```

**Hydration target:**

```
hydrationTarget = 35 ml × bodyWeightKg
(adjusted +500 ml if very active or extremely active multiplier)
```

### 15.2 Snapshot Immutability

Every time the user changes goal, body stats, or activity level:
- A **new** `GoalTargetSnapshot` row is inserted.
- The previous row is never modified.
- Historical `nutrition_log` rows look up the snapshot effective on their `logicalDay` for variance analysis.

### 15.3 Manual Overrides

Manual override values are stored alongside generated values in the same row. For display and calculations: if `manualCalorieTarget IS NOT NULL`, use manual value; else use generated `calorieTarget`. Both are always preserved.

---

## 16. Backup / Restore Contract

### 16.1 Archive Format

```
almanac-backup-YYYY-MM-DD-HHmmss.zip
├── manifest.json
├── database/
│   └── almanac.db         (SQLite WAL-checkpointed copy — app-owned tables only)
├── photos/
│   └── [UUID].[jpg|heic]  (one file per progress photo)
└── integrity/
    └── checksums.json     (SHA-256 hash of each file)
```

**manifest.json schema:**

```json
{
  "formatVersion": 1,
  "appVersion": "1.0.0",
  "schemaVersion": 1,
  "exportTimestamp": "2026-08-05T14:30:00+03:00",
  "exportedBy": "Almanac",
  "deviceModel": "iPhone 16 Pro",
  "recordCounts": {
    "nutritionLogs": 450,
    "sessions": 120,
    "sleepEpisodes": 95,
    "readinessRecords": 90,
    "progressPhotos": 12
  },
  "photoFilenames": ["uuid1.jpg", "uuid2.heic"],
  "checksum": "sha256-of-this-manifest-file"
}
```

**checksums.json schema:**

```json
{
  "manifest.json": "sha256-hex",
  "database/almanac.db": "sha256-hex",
  "photos/uuid1.jpg": "sha256-hex"
}
```

**HealthKit-imported data:** NOT included in the archive. The database export includes only app-owned tables. HealthKit-authoritative data (sleep, RHR, HRV, steps, imported workouts) is excluded from the SQLite export or included as a read-only cache clearly labelled in the manifest.

### 16.2 Restore Procedure

```
RESTORE PROCEDURE:

1. VALIDATE ARCHIVE:
   a. Unzip to temporary directory.
   b. Read manifest.json; verify formatVersion and schemaVersion are supported.
   c. Compute SHA-256 of each file; compare against checksums.json.
   d. If any checksum fails: abort with error "Archive appears corrupted."
   e. If schemaVersion > current app schemaVersion: abort with error "Archive requires a newer version of Almanac."

2. SHOW RESTORE SUMMARY to user:
   - Export date, app version, record counts, photo count.
   - Warning: "This will replace all current Almanac data. HealthKit data will be re-synced separately."

3. USER CONFIRMS.

4. TRANSACTIONAL RESTORE:
   a. Copy current almanac.db to almanac.db.pre-restore-backup (rollback target).
   b. Begin SQLite transaction.
   c. Drop all app-owned tables.
   d. Attach exported almanac.db; copy all tables.
   e. Run any pending migrations if schemaVersion < current.
   f. Commit transaction.
   g. If any step throws: rollback; restore from almanac.db.pre-restore-backup.

5. PHOTOS:
   a. Move photo files from ZIP/photos/ to Application Support/photos/.
   b. Verify each filename matches a progress_photo record.

6. DERIVED DATA REBUILD:
   a. Recalculate day_achievement rows.
   b. Recalculate readiness baselines from history.
   c. Rebuild caffeine_log.caffeineContext values.
   d. Rebuild nutrition_window assignments for religious fast days.

7. HEALTHKIT RECONCILIATION:
   a. Clear all sync_anchor rows.
   b. Set healthkit_link.syncState = 'pending_reconcile' for all imported-type links.
   c. Prompt user to re-grant HealthKit permissions.
   d. Run Sync Procedure on next foreground.
   e. DO NOT blindly rewrite any imported HealthKit data back into HealthKit.
   f. Pending writes for app-created entries (body weight, nutrition, workouts):
      verify each record still needs writing before retrying.

8. NOTIFICATIONS:
   Reschedule all notifications based on restored configuration.
```

### 16.3 What is Excluded from the Archive

- HealthKit-authoritative data (sleep, RHR, HRV, steps, watch-imported workouts)
- Derived analytics outputs (recalculated on restore)
- OS-level keychain entries (excluded — none in current v1 personal-use phase)

---

## 17. Screen Map

All screens listed with their parent navigation path.

### Tab 1 — Home

```
HomeScreen
  ├── ReadinessCard
  │     └── ReadinessDetailScreen (tap to expand)
  │           └── InputBreakdownView (which inputs contributed)
  │           └── MoodSorenessCheckInSheet (if provisional)
  ├── DailyTargetsCard (calories, protein, hydration — actual vs target)
  ├── ActiveFastTimerCard (visible when fasting active)
  │     └── FastDetailScreen (tap)
  ├── TodayWorkoutCard
  │     └── ActiveWorkoutScreen (tap to start)
  ├── VitalsSnapshotCard (RHR, HRV, Steps)
  ├── QuickLogBar
  │     ├── QuickWaterSheet (+200 ml / +500 ml / custom)
  │     ├── QuickMealSheet → NutritionLogScreen
  │     └── StartWorkoutSheet → ActiveWorkoutScreen
  └── SleepEpisodeQuickEditSheet (accessible from Home when sleep needs correction)
```

### Tab 2 — Log

```
LogScreen (category list)
  │
  ├── Nutrition
  │     ├── NutritionLogScreen (today's log, meal list)
  │     │     ├── AddMealScreen
  │     │     │     ├── FoodSearchScreen
  │     │     │     │     └── FoodDetailScreen (portion selector)
  │     │     │     ├── QuickEntryScreen (cal/protein/carbs/fat only)
  │     │     │     └── SavedMealsScreen
  │     │     │           └── SavedMealDetailScreen
  │     │     └── EditMealScreen (same as AddMealScreen in edit mode)
  │     └── NutritionHistoryScreen (past days)
  │
  ├── Hydration & Caffeine
  │     ├── HydrationScreen (today's log, target progress)
  │     │     ├── AddDrinkScreen (select type, volume, caffeine)
  │     │     └── DrinkPresetsScreen (manage presets)
  │     └── CaffeineTimelineScreen (daily caffeine vs intended sleep chart)
  │
  ├── Fasting
  │     ├── FastingScreen (active timer or start new fast)
  │     │     ├── IFTimerScreen (start/stop IF)
  │     │     └── IFHistoryScreen
  │     └── ReligiousFastingScreen
  │           ├── ReligiousFastScheduleScreen (Ramadan / Mon-Thu / White Days)
  │           └── PrayerSettingsScreen
  │                 ├── CalculationMethodPicker
  │                 ├── ManualCityPicker
  │                 └── OffsetAdjustmentScreen (per-prayer minute offsets)
  │
  ├── Sleep
  │     ├── SleepScreen (episode list for current cycle + recent)
  │     │     ├── SleepEpisodeDetailScreen
  │     │     └── AddEditSleepEpisodeScreen
  │     └── SleepHistoryScreen
  │
  ├── Mood & Soreness
  │     └── MoodSorenessScreen (1-10 sliders + body area tagging)
  │
  ├── Injuries
  │     ├── InjuryListScreen
  │     └── AddEditInjuryScreen
  │
  ├── Context Tags
  │     └── ContextTagScreen (multi-select tags for today)
  │
  ├── Digestion & Urination
  │     ├── DigestionUrinationScreen (log list + summary)
  │     │     ├── AddBowelMovementScreen (Bristol picker + colour + flags)
  │     │     │     └── AdvisorySheet (if level ≥ 2)
  │     │     └── AddUrinationScreen (colour grade visual picker)
  │     └── HydrationFeedbackCard (urine colour → hydration advice)
  │
  ├── Supplements
  │     ├── SupplementScreen (today's adherence)
  │     │     └── LogSupplementSheet (taken / missed)
  │     └── SupplementPlansScreen
  │           └── AddEditSupplementPlanScreen
  │
  └── Body
        ├── BodyCompositionScreen (chart + latest values)
        │     └── AddMeasurementScreen (weight / BF% / lean / skeletal / visceral)
        ├── CustomMeasurementsScreen
        │     ├── AddCustomMeasurementDefinitionScreen
        │     └── LogCustomMeasurementScreen
        ├── ProgressPhotosScreen (grid + comparison view)
        │     ├── AddProgressPhotoScreen (camera / library)
        │     └── PhotoComparisonScreen (side-by-side)
        └── LabResultsScreen
              └── AddEditLabResultScreen
```

### Tab 3 — Train

```
TrainScreen
  ├── ProgramListScreen
  │     ├── ProgramDetailScreen
  │     │     ├── WorkoutDayDetailScreen
  │     │     │     └── ExerciseDetailScreen (view exercise info)
  │     │     └── StartWorkoutFromProgramScreen → ActiveWorkoutScreen
  │     ├── CreateEditProgramScreen
  │     │     ├── AddWorkoutDayScreen
  │     │     └── AddExerciseToWorkoutScreen
  │     │           └── ExercisePickerScreen (search + filter by sport)
  │     └── TemplateLibraryScreen
  │           └── TemplateDetailScreen (preview + copy)
  │
  ├── ActiveWorkoutScreen
  │     (Simple: exercise list → tap → reps/weight → Done)
  │     ├── ExercisePickerSheet (add exercise mid-workout)
  │     └── PostWorkoutSheet (duration confirm + session RPE 1–10)
  │
  ├── SessionHistoryScreen (all completed sessions)
  │     └── SessionDetailScreen
  │           ├── SetListView (all logged sets)
  │           ├── MergeAuditView (merge history for this session)
  │           └── UnmatchedHKWorkoutsSection (pending merge candidates)
  │
  └── WorkoutMergePendingScreen (medium-confidence merge proposals awaiting confirmation)
```

### Tab 4 — Insights

```
InsightsScreen
  │
  ├── TrendsScreen
  │     └── MetricPickerScreen → MetricDetailScreen (chart + data table)
  │           (any metric: weight, sleep, HRV, readiness, session load, caffeine, etc.)
  │
  ├── CorrelationsScreen
  │     └── CorrelationDetailScreen
  │           (association language enforced; data-sufficiency state shown;
  │            filter by Day Type + Circadian Context; confounder tags shown)
  │
  └── AchievementCalendarScreen
        ├── MonthGridView (badge icons on days)
        └── DayAchievementDetailSheet (list of badges earned on tapped day)
```

### Tab 5 — Settings

```
SettingsScreen
  │
  ├── GoalsTargetsScreen
  │     ├── GoalSelectorScreen (Bulk / Cut / Maintain / Performance)
  │     ├── BodyStatsInputScreen (weight, height, BF% for formula)
  │     ├── ActivityLevelScreen
  │     ├── TargetOverrideScreen (manual override per target)
  │     └── TargetHistoryScreen (all past snapshot rows)
  │
  ├── ShiftScheduleScreen
  │     ├── ShiftCalendarScreen (month view with shift colours)
  │     ├── AddEditShiftScreen (single day)
  │     └── RotationPatternScreen (create repeating rotation)
  │
  ├── NotificationsScreen
  │     └── NotificationRuleDetailScreen (per rule: enable, time, interval)
  │
  ├── BackupRestoreScreen
  │     ├── ExportScreen (create ZIP, show last export date)
  │     └── RestoreScreen
  │           ├── ArchivePickerScreen (Files.app integration)
  │           ├── RestoreSummaryScreen (validation + record counts)
  │           └── RestoreProgressScreen
  │
  ├── HealthKitScreen
  │     ├── PermissionsOverviewScreen (per-type read/write status)
  │     └── SyncStatusScreen (pending writes, last sync, retry)
  │
  └── AppSettingsScreen
        ├── UnitsScreen (metric — imperial deferred)
        ├── AchievementDefinitionsScreen (configure badge types + thresholds)
        └── AboutScreen (version, BRD version, formula version)
```

---

## 18. Food Database — Open Research Item

As required by BRD Section 6.1, this is an independent open research item. The Technical Spec does not block on it.

**Three questions to verify (Technical Spec research phase):**

**Q1 — Technical availability:**
- myfood24: Does a controlled API or licensed integration route exist for the myfood24 UK/international database? What is the endpoint format, authentication mechanism, rate limits, and data format (JSON/CSV)?
- SFDA: The "Saudi Food Composition Tables" (June 2026) — is this available as a downloadable dataset (CSV/JSON/Excel), a searchable API, or publication-only tables?

**Q2 — Legal/licensing availability (personal use):**
- myfood24: Are there terms permitting offline caching, modification, and in-app embedding for personal non-commercial use? What attribution is required?
- SFDA: Government-published data — what are the redistribution and caching terms?

**Q3 — Commercial/redistribution terms:**
- Relevant only at commercialisation milestone; deferred.

**Implementation decision pending research:**

| Scenario | Implementation |
|---|---|
| myfood24 API + licensing confirmed | Implement API client with local cache; attribution per terms |
| myfood24 licensed offline dataset | Bundle dataset; implement local FTS5 search |
| myfood24 not available | Fallback: Open Food Facts (CC BY-SA 4.0) + user-created regional foods |
| SFDA data available as dataset | Import into food_item table; sourceDatabase = 'sfda' |
| SFDA publication only | Manual curation of commonly used Saudi foods by owner |

**Fallback (available without research resolution):**
- Open Food Facts database (CC BY-SA 4.0 — freely usable, offline-bundleable, attribution required)
- User-created food items (`isUserCreated = 1`)
- Quick-entry (cal/protein/carbs/fat) for anything else

**Food item table** is already schema-ready (Section 5.9). The research resolution determines which `sourceDatabase` values are populated.

---

## 19. Accessibility Implementation Notes

Implementing BRD Section 6.20:

**Colour-independent interfaces:**
- Urine colour picker: each option shows grade number (1–8) + short text label + colour swatch. VoiceOver label: e.g., `"Grade 4 — Dark yellow. Adequate hydration; drink more soon."` Never rely on colour alone.
- Stool colour picker: same pattern. VoiceOver label includes colour name + clinical context.
- Readiness score: VoiceOver reads `"Readiness: 78 out of 100. Green. Recovery is good — ready for a strong session. Final score. High confidence."`

**Dynamic Type:**
- All text uses `.font(.body)` or named text styles — never fixed point sizes.
- Cards and pickers adapt layout for large accessibility text sizes (minimum tap target: 44×44 pt).

**Internationalisation readiness:**
- All user-facing strings in `en.lproj/Localizable.strings`. No hardcoded English strings.
- Date/time formatting via `DateFormatter` with `locale = Locale.current`.
- RTL layout: all SwiftUI stacks use `HStack` with `.environment(\.layoutDirection)` compatibility. No manual frame positioning that would break RTL.
- Hijri calendar: use `Calendar(identifier: .islamicUmmAlQura)` for all Hijri date calculations and display.
- Plural rules: use `NSLocalizedString` with `NSString.localizedStringWithFormat` for count-based strings.

---

## 20. Build Order Notes

This section maps BRD Section 12 build order to concrete technical deliverables per slice.

| Slice | BRD Step | Technical Deliverables |
|---|---|---|
| 1 | Foundation | DatabaseManager; Migration_001; TimeModel utilities; logicalDay(); ReadinessCycle skeleton; HealthKitManager init; SyncAnchor table; BackupService skeleton; provenance enums |
| 2 | Core daily | Profile; sleep import; VitalsRecord import; MoodLog; SorenessLog; ReadinessEngine v1; HomeScreen; ReadinessCard; DailyTargetsCard; CircadianContextEngine |
| 3 | Hydration & caffeine | DrinkEntry; HydrationLog; CaffeineLog; DrinkPresetsScreen; NotificationService skeleton; water reminder |
| 4 | Training | Program; WorkoutDay; Exercise; Session; SetEntry; ActiveWorkoutScreen (simple); WorkoutMergeConfidenceModel; HealthKit workout import |
| 5 | Nutrition | NutritionLog; FoodItem; SavedMeal; FoodSearchScreen; QuickEntryScreen; NutritionWindow skeleton |
| 6 | Fasting | FastingSession; ReligiousFastSchedule; PrayerTimeEngine; PrayerTimesCache; NutritionWindow full; DayRecord dayType; FastingScreen; ReligiousFastingScreen |
| 7 | Body & wellness | BodyCompositionMeasurement; CustomMeasurement; ProgressPhoto; LabResult; SupplementPlan/Log; InjuryNote; ContextEvent |
| 8 | Regional food | FoodDatabase research resolution; import pipeline; sourceDatabase = 'sfda' or fallback |
| 9 | Digestion & urination | DigestionLog; UrinationLog; DigestiveAdvisoryEngine; hydration feedback card |
| 10 | Insights | Trends; Correlations (with guardrails); AchievementDefinition; DayAchievement; AchievementCalendar |
| 11 | Notifications | Full NotificationRuleEngine; all 9 notification types; suppression matrix; Ramadan/fasting/shift precedence |
| 12 | Migration & polish | Full BackupService; RestoreService; RestoreScreen; migration testing; widgets (water + fasting timer); AppIntents actions |

**Shift schedule & circadian context:** built in Slices 1–2 (time model, cycle detection, sleep classification) and Slice 11 (shift-aware notification suppression). The ShiftScheduleScreen UI lands in Slice 2 or as an early Slice 7 sub-task.

---

## Appendix A — Readiness Formula Reference Card

```
FORMULA VERSION: 1.0

INPUTS (all normalised 0–100):
  I1  = SleepDurationScore(durationMinutes)
  I2  = SleepQualityScore(deepPct, remPct, corePct)   [50 if no stage data]
  I3  = RHRScore(currentRHR, baselineRHR)              [excluded if missing]
  I4  = HRVScore(currentHRV, baselineHRV)              [excluded if missing]
  I5  = MoodSorenessScore(moodScore, sorenessScore)    [final only]

PROVISIONAL (before mood/soreness check-in):
  Weights: I1=33%, I2=22%, I3=22%, I4=23%
  Score = weighted_sum(I1,I2,I3,I4) × 0.90   [max=90, representing pending check-in]

FINAL (after check-in):
  Weights: I1=30%, I2=20%, I3=20%, I4=20%, I5=10%
  Score = weighted_sum(I1,I2,I3,I4,I5)        [max=100]

MISSING INPUT HANDLING:
  Redistribute missing input's weight proportionally among present inputs.
  If I1+I2+I3+I4 all missing → score = null, confidence = 'insufficient'

CONFIDENCE: high(0 missing) | medium(1) | low(2) | very_low(3+) | insufficient

COLOUR: green(≥70) | yellow(40–69) | red(<40) | none(null)

CALIBRATION: first 21 valid days → preliminary estimates only
BASELINE WINDOW: 28 valid days rolling

STORED FIELDS: state, score, colorGrade, textDescription, confidence,
               missingInputs, formulaVersion, inputSnapshot, calculationTimestamp,
               recommendation, precedenceApplied, feedbackValue, feedbackTimestamp,
               baselineContext
```

---

## Appendix B — Notification Suppression Matrix

| Notification type | During dry fast | During confirmed IF | Night shift | Post-shift sleep | Readiness already final |
|---|---|---|---|---|---|
| readiness | ✅ send | ✅ send | ✅ send | 🚫 suppress | 🚫 suppress |
| water | 🚫 suppress | ✅ send | ✅ send | 🚫 suppress | — |
| meal | ✅ send | 🚫 suppress | ✅ send | 🚫 suppress | — |
| bedtime | ✅ send | ✅ send | 🚫 suppress | 🚫 suppress | — |
| supplement | ✅ send | ✅ send | ✅ send | 🚫 suppress | — |
| suhoor | 🚫 (send = end of fast approaching) | — | ✅ send | ✅ send | — |
| iftar | — | — | ✅ send | ✅ send | — |
| contextual_snack | ✅ send | 🚫 suppress | ✅ send | 🚫 suppress | — |
| contextual_hydration | 🚫 suppress | ✅ send | ✅ send | 🚫 suppress | — |

*"During dry fast" = `fastingSession.isDryFast = 1 AND fastingSession.isActive = 1`*
*"During confirmed IF" = `fastingSession.sessionType IN ('if_planned','if_confirmed_suggestion') AND fastingSession.isActive = 1`*
*"Night shift" = `shift_occurrence.shiftType = 'night' AND current time is within shift hours`*
*"Post-shift sleep" = current time is within a detected post-shift sleep episode*

---

## Appendix C — HealthKit Permission Map (Full Table)

| HK Type | Category | Read | Write | Trigger for permission request | Notes |
|---|---|---|---|---|---|
| `sleepAnalysis` | Category | ✅ | ❌ | First time Sleep tab opened | HK authoritative |
| `restingHeartRate` | Quantity | ✅ | ❌ | First time Readiness computed | HK authoritative |
| `heartRateVariabilitySDNN` | Quantity | ✅ | ❌ | First time Readiness computed | HK authoritative |
| `heartRate` | Quantity | ✅ | ❌ | First time Insights/workout detail opened | For workout HR |
| `stepCount` | Quantity | ✅ | ❌ | First time Activity/Vitals opened | HK authoritative |
| `activeEnergyBurned` | Quantity | ✅ | ❌ | First time Activity/Vitals opened | HK authoritative |
| `bodyMass` | Quantity | ✅ | ✅ | First time Body Composition opened | Bi-directional |
| `bodyFatPercentage` | Quantity | ✅ | ✅ | First time Body Composition opened | Bi-directional |
| `leanBodyMass` | Quantity | ✅ | ✅ | First time Body Composition opened | Bi-directional |
| `workoutType` | Workout | ✅ | ✅ | First time Train tab / workout import | Import + export |
| `dietaryWater` | Quantity | ✅ | ✅ | First time Hydration opened | Bi-directional |
| `dietaryEnergyConsumed` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |
| `dietaryProtein` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |
| `dietaryCarbohydrates` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |
| `dietaryFatTotal` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |
| `dietaryFiber` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |
| `dietarySodium` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |
| `dietarySugar` | Quantity | ✅ | ✅ | First time Nutrition opened | Bi-directional |

**Not requested / not used:**
- `menstrualFlow`, `cervicalMucusQuality`, cycle-related types — deferred to commercial release
- `bloodGlucose`, `oxygenSaturation`, `bloodPressure` — not modelled in v1
- `electrocardiogram` — not modelled in v1

**Missing data wording** (required per BRD 5.2):
*"No accessible [data type] data was found. Check that [data source] was recorded and review Health access in Settings."*
Never claim permission was denied. Never show zero in place of missing data.

---

*End of Almanac Technical Specification v1.0*
*Owner: Yazeed | Derived from BRD v1.5 | Ready for Claude Code build*
