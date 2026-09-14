# Hydration Tracking

**Version:** 1.0  
**Status:** Implemented — fully functional hydration tracking module with smart recommendations and adaptive metrics

---

## Overview

The hydration tracking module helps users maintain optimal fluid intake with personalized, adaptive recommendations based on their activity level, body weight, and historical behavior. The system learns from user patterns to provide increasingly accurate suggestions.

## Key Features

### 1. **Personalized Hydration Calculator**

The `HydrationCalculator` computes individualized daily hydration targets based on:

- **Baseline intake** (default 2000ml/day)
- **Activity level** (sedentary, light, moderate, high, very high)
- **Exercise duration** (~500ml per 30 minutes)
- **Body weight** (30ml per kg as baseline)

Activity level multipliers:
- Sedentary: 0.9x baseline
- Light: 1.0x baseline
- Moderate: 1.1x baseline
- High: 1.2x baseline
- Very High: 1.4x baseline

### 2. **Smart Real-Time Recommendations**

The system evaluates multiple factors to provide urgent, contextual guidance:

**Urgency Levels:**
- **Critical** 🚨 — Very dehydrated + long time without water + active exercise
- **High** ⚠️ — Significant hydration gap (>800ml) or >90 min since last drink
- **Moderate** 💧 — Some gap (>300ml) or 45-90 min since last drink
- **Low** ✨ — On track, staying hydrated

**Liquid Type Suggestions:**
- **Water** — Always primary option
- **Sports Drinks** (Gatorade, Powerade) — During/after intense exercise
- **Electrolyte Solutions** (Pedialyte) — For critical dehydration or low sodium intake
- **Coconut Water** — Natural electrolytes, low urgency situations
- **Tea/Coffee** — Variety options when well-hydrated

### 3. **Adaptive Metrics**

Daily hydration metrics automatically track:
- Total volume consumed (ml)
- Sodium intake (mg) — important for electrolyte balance
- Exercise minutes — drives adaptive recommendations
- Compliance percentage — (actual / recommended) × 100
- Sample count — tracks consistency

Metrics enable the system to:
- Visualize hydration trends over time
- Detect personal patterns (e.g., user consistently under-hydrates after workouts)
- Trigger automatic profile adjustments

### 4. **Profile Learning**

The `adaptProfile()` function analyzes recent patterns:

- **Under-hydrating (<75% compliance)** → Baseline increases by 10%
- **Over-hydrating (>110% compliance)** → Baseline decreases by 5%
- **Activity detection** → Automatically updates activity level based on 7-day exercise average

Example: If a user averages 50 minutes of exercise daily but profile says "light", the system updates it to "moderate".

### 5. **Configurable Reminder System**

Reminders are smart and adaptable:

**Configuration:**
- Interval between reminders (default: 60 minutes)
- Active window (default: 7 AM - 10 PM)
- Enable/disable globally

**Smart Triggering:**
Only fires reminders when:
- User hasn't drunk anything in the configured interval
- Current time is within the active window
- Enough time has passed since the last reminder

**Intelligent Messages:**
Messages include:
- Emoji indicating urgency (🚨 ⚠️ 💧 ✨)
- Clear action ("Drink 250ml now")
- Suggested drink types with emojis
- Time elapsed since last drink
- Context ("You're exercising - stay hydrated!")

---

## Data Model

### Core Entities

#### **HydrationSample**
Represents a single drinking event:
```swift
HydrationSample(
    id: UUID,                           // Unique identifier
    timestamp: Date,                    // When drunk
    volumeMilliliters: Double,          // Amount
    liquidType: LiquidType,             // water, sports_drink, etc.
    sodiumMilligrams: Double? = nil,    // Electrolytes
    caloriesKcal: Double? = nil,        // Nutrition info
    sourceName: String? = nil           // Source (Apple Health, manual, etc.)
)
```

#### **HydrationMetrics**
Daily aggregated data (computed automatically):
```swift
HydrationMetrics(
    date: Date,
    totalVolumeMilliliters: Double,     // Sum of all samples
    totalSodiumMilligrams: Double,      // Electrolyte tracking
    exerciseMinutes: Double?,           // From health integration
    recommendedIntakeMilliliters: Double, // Calculated for the day
    hydrationPercentage: Double,        // (actual / recommended) × 100
    sampleCount: Int                    // Consistency metric
)
```

#### **HydrationProfile**
User's personalized settings:
```swift
HydrationProfile(
    userId: String,
    baselineIntakeMilliliters: Double = 2000,
    bodyWeightKg: Double?,
    activityLevel: ActivityLevel = .moderate,
    updatedAt: Date
)
```

#### **HydrationReminder**
Reminder configuration:
```swift
HydrationReminder(
    id: String,
    intervalMinutes: Int = 60,
    startHour: Int = 7,
    endHour: Int = 22,
    isEnabled: Bool = true,
    createdAt: Date
)
```

#### **HydrationRecommendation**
Current hydration guidance:
```swift
HydrationRecommendation(
    recommendedVolumeMilliliters: Double,
    urgency: Urgency,                   // critical | high | moderate | low
    reason: String,                     // "You're exercising - drink water!"
    suggestedLiquidTypes: [LiquidType],
    timeSinceLastDrinkMinutes: Int?
)
```

### LiquidTypes

```
.water                  — Plain water (primary)
.sportsDrink           — Gatorade, Powerade, etc. (6-8% carbs, 20-30mg Na)
.electrolyteSolution   — Pedialyte, ORS, etc. (low carb, 20-75mg Na)
.coconutWater          — Natural hydration (600mg+ potassium)
.juice                 — Fruit juice (sugary, full of calories)
.tea                   — Tea (mild caffeine, no calories)
.coffee                — Coffee (more caffeine)
.milk                  — Dairy milk (protein, calcium)
.other                 — User-defined beverages
```

### ActivityLevel

```
.sedentary      — <15 min exercise per day
.light          — 15-45 min exercise per day
.moderate       — 45-90 min exercise per day
.high           — 90+ min exercise per day
.veryHigh       — 2+ hours exercise per day
```

---

## Database Schema (Migration 007)

### hydration_sample
Stores every drinking event:
```sql
CREATE TABLE hydration_sample (
    id              TEXT        PRIMARY KEY,
    timestamp       TEXT        NOT NULL,           -- ISO8601
    volume_ml       REAL        NOT NULL,
    liquid_type     TEXT        NOT NULL,           -- Enum value
    sodium_mg       REAL,
    calories_kcal   REAL,
    source_name     TEXT,                           -- Apple Health, manual, etc.
    recorded_at     TEXT        NOT NULL            -- When entered
);
```
Indexes: timestamp, date (for daily queries)

### hydration_metrics
Daily roll-up (for performance):
```sql
CREATE TABLE hydration_metrics (
    date                    TEXT        PRIMARY KEY, -- Logical day
    total_volume_ml         REAL        NOT NULL,
    total_sodium_mg         REAL        NOT NULL,
    exercise_minutes        REAL,
    recommended_intake_ml   REAL        NOT NULL,
    hydration_percentage    REAL        NOT NULL,
    sample_count            INTEGER     NOT NULL,
    last_updated            TEXT        NOT NULL
);
```
Enables fast trend queries without scanning thousands of samples.

### hydration_profile
Per-user settings (one row per user):
```sql
CREATE TABLE hydration_profile (
    user_id             TEXT        PRIMARY KEY,
    baseline_intake_ml  REAL        NOT NULL DEFAULT 2000,
    body_weight_kg      REAL,
    activity_level      TEXT        NOT NULL DEFAULT 'moderate',
    updated_at          TEXT        NOT NULL,
    created_at          TEXT        NOT NULL
);
```

### hydration_reminder
Reminder configuration (typically one row):
```sql
CREATE TABLE hydration_reminder (
    id              TEXT        PRIMARY KEY,
    interval_minutes INTEGER     NOT NULL DEFAULT 60,
    start_hour      INTEGER     NOT NULL DEFAULT 7,
    end_hour        INTEGER     NOT NULL DEFAULT 22,
    is_enabled      INTEGER     NOT NULL DEFAULT 1,
    created_at      TEXT        NOT NULL,
    updated_at      TEXT        NOT NULL
);
```

### hydration_profile_history
Audit trail (optional, for future analysis):
```sql
CREATE TABLE hydration_profile_history (
    id                  TEXT        PRIMARY KEY,
    user_id             TEXT        NOT NULL REFERENCES hydration_profile,
    baseline_intake_ml  REAL        NOT NULL,
    activity_level      TEXT        NOT NULL,
    reason              TEXT,
    recorded_at         TEXT        NOT NULL
);
```
Tracks when and why the profile changed, enabling analysis of what triggered adaptations.

### hydration_trend
Pre-computed trends (optional, for analytics):
```sql
CREATE TABLE hydration_trend (
    id                  TEXT        PRIMARY KEY,
    period_start        TEXT        NOT NULL,
    period_end          TEXT        NOT NULL,
    period_type         TEXT        NOT NULL,  -- 'week' | 'month'
    average_volume_ml   REAL        NOT NULL,
    compliance_percent  REAL        NOT NULL,
    exercise_minutes    REAL,
    computed_at         TEXT        NOT NULL
);
```
Enables weekly/monthly insights without recomputing from thousands of samples.

---

## Usage Examples

### Example 1: Log Hydration and Get Recommendation

```swift
let calculator = HydrationCalculator()
let store = HydrationStore(database: db)

// Create user profile
let profile = HydrationProfile(
    userId: "user_123",
    baselineIntakeMilliliters: 2000,
    bodyWeightKg: 75,
    activityLevel: .moderate
)
try store.save(profile)

// User drinks water
let sample = HydrationSample(
    id: UUID().uuidString,
    timestamp: Date(),
    volumeMilliliters: 250,
    liquidType: .water
)
try store.save(sample)

// Get today's metrics
let metrics = try store.calculateTodayMetrics(calculator: calculator, profile: profile)

// Get smart recommendation
let recommendation = calculator.currentRecommendation(
    timeSinceLastDrinkMinutes: 30,
    exerciseActive: false,
    metrics: metrics,
    profile: profile
)

print("Urgency: \(recommendation.urgency)")  // Output: low
print("Volume: \(recommendation.recommendedVolumeMilliliters)ml")  // Output: 150ml
```

### Example 2: Post-Exercise Hydration Alert

```swift
// After a 60-minute workout
let postExerciseMetrics = HydrationMetrics(
    date: Date(),
    totalVolumeMilliliters: 500,  // Only had 500ml
    totalSodiumMilligrams: 0,     // No electrolytes yet
    exerciseMinutes: 60,
    recommendedIntakeMilliliters: 2800,  // Increased due to exercise
    sampleCount: 1
)

let postExerciseRec = calculator.currentRecommendation(
    timeSinceLastDrinkMinutes: 15,
    exerciseActive: true,
    metrics: postExerciseMetrics,
    profile: profile
)

// Will suggest sports drink instead of just water
print(postExerciseRec.suggestedLiquidTypes)  // [.sportsDrink, .water]
```

### Example 3: Adaptive Profile Learning

```swift
// Last 7 days of metrics show user consistently exercises 90+ minutes
let recentMetrics = [
    metrics1, metrics2, metrics3, metrics4, metrics5, metrics6, metrics7
]

let adaptedProfile = calculator.adaptProfile(
    baseProfile: profile,
    recentMetrics: recentMetrics,
    averageExerciseMinutes: 95
)

// Profile updated from .moderate to .high
print(adaptedProfile.activityLevel)  // .high
print(adaptedProfile.baselineIntakeMilliliters)  // Increased
```

### Example 4: Configure Reminders

```swift
let reminderService = HydrationReminderService(store: store, calculator: calculator)

// Create default reminder (every hour, 7am-10pm)
let reminder = try reminderService.createDefaultReminder()

// Customize for early riser
try reminderService.updateReminder(
    id: reminder.id,
    intervalMinutes: 45,
    startHour: 5,
    endHour: 23
)

// Get next reminder time
if let nextTime = reminderService.nextReminderTime(reminder: reminder) {
    print("Next reminder at: \(nextTime)")
}

// Check if reminder should trigger now
let currentMetrics = try store.calculateTodayMetrics(
    calculator: calculator,
    profile: profile
)
if let recommendation = try reminderService.checkReminder(
    profile: profile,
    currentMetrics: currentMetrics
) {
    let message = reminderService.getReminderMessage(
        recommendation: recommendation,
        profile: profile
    )
    // Send notification with message
}
```

---

## Integration with Health Module

### Connection Points

The hydration module expects exercise data from the Health module via:

1. **Direct query** — `HydrationStore.calculateTodayMetrics()` accepts exercise minutes
2. **Sync integration** — Future: Watch for `workouts` domain changes in `HealthChangeSet`

### Exercise Data Flow

```
Health Module (workouts)
    ↓
    Gets total exercise minutes for the day
    ↓
HydrationCalculator.recommendedDailyIntake()
    ↓
Adjusts baseline by activity level + exercise boost
    ↓
HydrationMetrics stores exerciseMinutes
    ↓
ReminderService & Calculator use it for urgency evaluation
```

Example integration:
```swift
// In a Health sync handler
func syncHealthData(changeSet: HealthChangeSet) async throws {
    if changeSet.domain == .workouts {
        let totalExerciseMinutes = calculateTotalMinutes(from: changeSet.added)
        
        // Update hydration metrics
        var metrics = try store.fetchMetrics(for: Date())
        metrics.exerciseMinutes = totalExerciseMinutes
        try store.save(metrics)
        
        // Recommendations will now include exercise boost
    }
}
```

---

## Liquid Types: Nutritional Reference

| Type | Use Case | Sodium | Carbs | Calories | Ideal For |
|---|---|---|---|---|---|
| **Water** | General hydration | 0-10mg | 0g | 0 | Daily drinking, any time |
| **Sports Drink** (Gatorade 6-8%) | Exercise | 20-30mg | 14-18g per 8oz | 50-60 | Intense exercise >1 hour |
| **Electrolyte Solution** (Pedialyte) | Dehydration/illness | 35mg | 2.5g | 10 | Recovery, high urgency |
| **Coconut Water** | Natural hydration | 250mg | 9g | 45 | Post-workout, potassium |
| **Juice** | Taste, calories | varies | 20-30g | 100-140 | Low priority, high sugar |
| **Tea** | Caffeine + hydration | 0-5mg | 0g | 0-2 | Morning/afternoon |
| **Coffee** | Caffeine | 0-5mg | 0g | 0-5 | Morning boost |
| **Milk** | Protein, calcium | 120mg | 12g | 150 | Nutritional boost |

---

## Urgency Thresholds

Urgency is calculated from:

```
Inputs:
  - hydrationGap = recommended - actual volume
  - timeSinceLastDrink (minutes)
  - exerciseActive (boolean)
  - dayProgress = (actual / recommended) * 100

Logic:
  IF (gap > 1500 OR progress < 20%) AND time > 120min AND exercising
    → CRITICAL 🚨
  ELSE IF gap > 800 OR time > 90min
    → HIGH ⚠️
  ELSE IF gap > 300 OR time > 45min
    → MODERATE 💧
  ELSE
    → LOW ✨
```

This ensures:
- **Critical** is reserved for true dehydration emergencies
- **High** catches early dehydration before it becomes critical
- **Moderate** keeps users gently on track
- **Low** rewards good hydration habits

---

## Future Enhancements

1. **Electrolyte Tracking** — Warn if sodium is too low after exercise
2. **Caffeine Impact** — Adjust hydration goals based on coffee/tea intake
3. **Weather Integration** — Increase goals on hot days
4. **Fitness App Sync** — Automatic exercise data from Apple Health, Strava, etc.
5. **Medication Interactions** — Higher hydration goals for diuretics
6. **Pregnancy/Nursing** — Automatic profile adjustment
7. **Geographic Localization** — Different norms for different regions
8. **Predictive Alerts** — "You'll be dehydrated at 3pm based on your pattern"
9. **Social Features** — Challenge friends to hydration goals
10. **Smart Watch Integration** — Tap reminders on wrist, quick-log drinks

---

## Testing

Comprehensive test suites included:

- `HydrationCalculatorTests` — 8 tests covering intake calculation, urgency logic, profile adaptation
- `HydrationStoreTests` — 12 tests covering persistence, queries, all liquid types
- `HydrationReminderServiceTests` — 11 tests covering reminders, messages, timing

Run tests:
```bash
swift test AlmanacCoreTests
```

---

## Implementation Notes

### Preservation of Source Data

Per the Almanac philosophy, every field is **optional and preserved**:
- If exercise minutes unknown → `exerciseMinutes = nil`
- If sodium unknown → `sodiumMilligrams = nil`
- Recommendations still work; features gracefully degrade

### No Guessing

- Never assumes "today" for unknown dates
- Never uses last activity level if not entered
- Never inflates volumes to meet goals
- All defaults are conservative (recommend less, not more)

### Performance

- **Daily metrics** pre-computed and cached (one row per day)
- **Reminder checks** O(1) — direct reminder lookup
- **Trends** optional and separately computed
- **Queries** indexed by timestamp and date

### Thread Safety

All services are `Sendable`:
- Database access via exclusive write transactions
- Store operations synchronized
- Clock and reminder service fully concurrent-safe
