# Hydration Tracking Quick Start Guide

## What Was Built

A comprehensive hydration tracking module that helps users stay hydrated with intelligent, personalized recommendations that adapt to their exercise habits and personal patterns.

**Now includes:** Integrated calorie tracking for drinks, drink catalog with 25+ beverages, double-tracking prevention, and full user customization via settings.

### Core Components

1. **HydrationCalculator** — Computes personalized daily intake goals
2. **HydrationStore** — Persists all hydration data to SQLite
3. **HydrationReminderService** — Manages smart reminders with contextual recommendations
4. **HydrationModels** — Data structures for samples, metrics, profiles, and recommendations

### Key Capabilities

✅ **Smart Hydration Goals** based on:
- Body weight
- Activity level (sedentary to very high)
- Exercise duration (gets added boost)

✅ **Real-Time Urgency Levels**:
- 🚨 Critical (severe dehydration)
- ⚠️ High (needs attention)
- 💧 Moderate (regular reminders)
- ✨ Low (good hydration)

✅ **Liquid Type Tracking**:
- Water (primary)
- Sports Drinks (Gatorade, Powerade)
- Electrolyte Solutions (Pedialyte)
- Coconut Water, Tea, Coffee, Juice, Milk, Other
- Tracks sodium and calories per type

✅ **Adaptive Learning**:
- Analyzes recent hydration compliance
- Automatically updates recommendations if user consistently under/over-hydrates
- Detects activity level from exercise patterns

✅ **Smart Reminders**:
- Configurable interval (default every 60 min)
- Active time window (default 7am-10pm)
- Only triggers when enough time has passed
- Suggests appropriate drinks based on context

✅ **Post-Exercise Recommendations**:
- Detects exercise sessions
- Recommends electrolyte-rich drinks (sports drinks, Pedialyte)
- Higher urgency for rehydration
- Sodium tracking to prevent depletion

---

## Quick Usage Examples

### 1. Set Up User Profile

```swift
import AlmanacCore

let calculator = HydrationCalculator()
let store = HydrationStore(database: db)

// Create personalized profile
let profile = HydrationProfile(
    userId: "john_doe",
    baselineIntakeMilliliters: 2000,
    bodyWeightKg: 75,
    activityLevel: .moderate
)
try store.save(profile)
```

### 2. Log Hydration

```swift
// User drinks a sports drink
let sample = HydrationSample(
    id: UUID().uuidString,
    timestamp: Date(),
    volumeMilliliters: 350,
    liquidType: .sportsDrink,
    sodiumMilligrams: 250
)
try store.save(sample)
```

### 3. Get Recommendation

```swift
// Calculate today's metrics
let metrics = try store.calculateTodayMetrics(
    calculator: calculator,
    profile: profile
)

// Get smart recommendation
let recommendation = calculator.currentRecommendation(
    timeSinceLastDrinkMinutes: 45,
    exerciseActive: false,
    metrics: metrics,
    profile: profile
)

print("💧 Urgency: \(recommendation.urgency)")
print("📊 Recommended: \(Int(recommendation.recommendedVolumeMilliliters))ml")
print("💡 Why: \(recommendation.reason)")
print("🥤 Drink: \(recommendation.suggestedLiquidTypes)")
```

### 4. Configure Reminders

```swift
let reminderService = HydrationReminderService(store: store)

// Create default reminder (hourly, 7am-10pm)
let reminder = try reminderService.createDefaultReminder()

// Customize for user (e.g., 30-minute intervals)
try reminderService.updateReminder(
    id: reminder.id,
    intervalMinutes: 30
)

// Check if reminder should trigger now
let currentMetrics = try store.calculateTodayMetrics(
    calculator: calculator,
    profile: profile
)

if let rec = try reminderService.checkReminder(
    profile: profile,
    currentMetrics: currentMetrics
) {
    let message = reminderService.getReminderMessage(
        recommendation: rec,
        profile: profile
    )
    // Show notification or alert to user
    showNotification(message)
}
```

### 5. Track Exercise Impact

```swift
// After a 60-minute workout, calculate adjusted hydration needs
let exerciseMetrics = try store.calculateTodayMetrics(
    calculator: calculator,
    profile: profile
)
exerciseMetrics.exerciseMinutes = 60

// Recommendations will automatically:
// - Increase daily goal (~1000ml for 60 min exercise)
// - Suggest sports drinks instead of just water
// - Set higher urgency
// - Track sodium (important after sweat loss)
```

---

## Data Flow Architecture

```
User Drinks Water
    ↓
HydrationSample saved to DB
    ↓
calculateTodayMetrics() aggregates samples
    ↓
HydrationCalculator evaluates current state
    ↓
Returns HydrationRecommendation with:
  - Urgency level
  - Volume to drink
  - Liquid type suggestions
  - Context message
    ↓
ReminderService checks if reminder should fire
    ↓
getReminderMessage() formats user-friendly alert
```

---

## Database Tables (Migration 007)

### hydration_sample
Stores every drinking event:
- `id` — UUID
- `timestamp` — When consumed (ISO8601)
- `volume_ml` — Milliliters
- `liquid_type` — Type enum (water, sports_drink, etc.)
- `sodium_mg` — Optional electrolytes
- `calories_kcal` — Optional nutrition
- `source_name` — Where it came from (Apple Health, manual, etc.)

### hydration_metrics
Daily aggregated data (one row per day):
- `date` — Logical day
- `total_volume_ml` — Sum of samples
- `total_sodium_mg` — Electrolyte tracking
- `exercise_minutes` — From Health module
- `recommended_intake_ml` — Calculated for day
- `hydration_percentage` — (actual/recommended)*100
- `sample_count` — How many times user drank

### hydration_profile
User's personalized settings (one row per user):
- `user_id` — Unique identifier
- `baseline_intake_ml` — Base daily goal
- `body_weight_kg` — For weight-based calc
- `activity_level` — Enum (sedentary-veryHigh)
- `updated_at` — Last modification time

### hydration_reminder
Reminder configuration (typically one row):
- `id` — Reminder ID
- `interval_minutes` — Time between reminders
- `start_hour` — Morning start time (0-23)
- `end_hour` — Evening end time (0-23)
- `is_enabled` — Whether reminders are on

---

## Activity Level Multipliers

How activity affects hydration goals (baseline * multiplier):

| Level | Multiplier | Daily Exercise |
|-------|-----------|-----------------|
| Sedentary | 0.9x | 0-15 min |
| Light | 1.0x | 15-45 min |
| Moderate | 1.1x | 45-90 min |
| High | 1.2x | 90+ min |
| Very High | 1.4x | 2+ hours |

**Plus** ~500ml per 30 minutes of exercise on top of base.

---

## Urgency Calculation Logic

```
Critical 🚨 when:
  (Large gap AND long time without drinking AND exercising)
  OR (Very behind on daily goal AND hasn't drunk in 2+ hours)

High ⚠️ when:
  Large gap (>800ml) OR long time without water (>90 min)

Moderate 💧 when:
  Some gap (>300ml) OR moderate time without water (45-90 min)

Low ✨ when:
  On track with hydration goals
```

---

## Liquid Types & Nutritional Value

### Recommended Hydration Hierarchy

**Best:**
1. 💧 **Water** — Zero calories, zero sodium (pure hydration)
2. 🥥 **Coconut Water** — Natural, potassium-rich, good post-exercise

**During Intense Exercise (>1 hour):**
3. ⚡ **Sports Drinks** (Gatorade) — 6-8% carbs, ~25mg sodium, 50-60 cal
4. 🧂 **Electrolyte Solution** (Pedialyte) — Optimized ratio, low sugar

**Occasional:**
5. 🍵 **Tea/Coffee** — Caffeine, essentially calorie-free
6. 🥛 **Milk** — Protein, calcium, natural sugars
7. 🧃 **Juice** — Avoid (high sugar, minimal hydration benefit)

---

## Testing Coverage

The implementation includes 31 comprehensive test cases:

### HydrationCalculatorTests (8 tests)
- ✓ Basic daily intake calculation
- ✓ Exercise boost logic
- ✓ Activity level multipliers
- ✓ Urgency calculations
- ✓ Exercise recommendations
- ✓ Profile adaptation
- ✓ Body weight adjustment

### HydrationStoreTests (12 tests)
- ✓ Save and fetch samples
- ✓ Multiple sample handling
- ✓ Delete operations
- ✓ Metrics persistence
- ✓ Profile storage
- ✓ Reminder management
- ✓ Date range queries
- ✓ All liquid type variations

### HydrationReminderServiceTests (11 tests)
- ✓ Default reminder creation
- ✓ Reminder updates
- ✓ Enable/disable functionality
- ✓ Message generation with emojis
- ✓ Next reminder time calculation
- ✓ Electrolyte suggestions
- ✓ Post-exercise recommendations

No Swift toolchain is available in this environment, so none of this has actually been run through `swift test` — these counts reflect what's written and manually reviewed against the real `Database`/`Row`/`SQLValue` API, not a passing run. Run `source env.sh && swift test` on a machine with the toolchain before trusting it further; an earlier pass of this module looked identically "done" while being written against an API this package doesn't have.

---

## Future Integration Points

### 1. Health Module Integration
Connect to the existing Health module for automatic exercise detection:
```swift
// When workout is logged to Health module
exerciseMetrics.exerciseMinutes = totalFromHealth
```

### 2. Notifications
Send platform-specific notifications:
```swift
// iOS
UNUserNotificationCenter.current().add(request)

// Watch
WKUserNotificationCenter.default().presentLocalNotification()
```

### 3. UI Display
Show hydration dashboard:
- Daily progress towards goal
- Time-series chart of consumption
- Suggested actions
- Achievement badges

### 4. Smart Watch
Quick drink logging on Apple Watch:
- Tap to log common amounts (250ml, 500ml)
- Get taps on wrist for reminders
- See progress at a glance

### 5. Health Sync
Two-way sync with Apple Health:
- Read workouts → adjust hydration needs
- Write hydration samples → visible in Health app

---

## Files Created

```
Sources/AlmanacCore/Hydration/
├── Hydration.swift                 # Module public API
├── HydrationModels.swift           # Data structures
├── HydrationCalculator.swift       # Recommendation logic
├── HydrationStore.swift            # Database persistence
└── HydrationReminderService.swift  # Reminder management

Sources/AlmanacCore/Persistence/
└── Migration007.swift              # Database schema

Tests/AlmanacCoreTests/
├── HydrationCalculatorTests.swift
├── HydrationStoreTests.swift
└── HydrationReminderServiceTests.swift

docs/
└── features/hydration.md           # Complete specification
```

---

## Calorie Tracking Integration

### Overview
The hydration module now integrates with calorie tracking, automatically logging calories from drinks while preventing double-tracking.

### Features
- **25+ Drink Catalog** with pre-populated calories, sodium, and sugar
  - Sodas (regular & diet): Pepsi, Coca-Cola, Sprite, Fanta
  - Sports drinks: Gatorade, Powerade
  - Electrolyte solutions: Pedialyte, coconut water
  - Beverages: Coffee, tea, milk, juice, energy drinks
  
- **Double-Tracking Prevention** ⚠️
  - Detects if similar drinks logged within 5 minutes
  - Confidence scoring system
  - User can acknowledge and dismiss warnings
  - Fully configurable (can be disabled)

- **Smart Warnings**
  - High sugar warning (>35g)
  - High sodium context (especially during/after exercise)
  - Double-track alerts with time stamps

- **Custom Drinks**
  - Users can add their own beverages
  - Saved for future use
  - Full nutritional tracking

### Settings (User-Configurable)

**Calorie Tracking Toggle** ✓
```
Default: OFF (opt-in to prevent mess)
Enabled: Calories auto-logged with each drink
Disabled: Hydration-only tracking
```

**Double-Track Warnings** ✓
```
Default: ON
Logs are flagged if similar drink logged in 5-minute window
User can dismiss after reviewing
```

**Sugar Tracking** ✓
```
Default: ON
Warns if drink has >35g sugar
Tracks daily sugar totals
```

**Sodium Tracking** ✓
```
Default: ON
Notes high sodium drinks (ideal during/after exercise)
Important for electrolyte balance
```

### Usage Example: Enable Calorie Tracking

```swift
let settingsStore = HydrationSettingsStore(database: db)

// Get user settings
let settings = try settingsStore.getOrCreate(for: "user123")

// Enable calorie tracking
try settingsStore.setCalorieTracking(for: "user123", enabled: true)

// Or use comprehensive preset
let compSettings = HydrationSettingsPreset.comprehensive.toSettings(userId: "user123")
try settingsStore.save(compSettings)
```

### Usage Example: Log Drink with Calories

```swift
let loggingService = HydrationLoggingService(
    hydrationStore: store,
    calorieIntegration: calorieIntegration,
    settingsStore: settingsStore
)

// Log a drink (settings determine if calories tracked)
let result = try await loggingService.logDrink(
    drink: CatalogDrinks.byId("catalog_pepsi")!,
    userId: "user123"
)

// Check for warnings
if result.hasWarnings {
    print("⚠️ \(result.warningMessage)")
    // Example: "⚠️ Similar drink logged 2s ago. Did you mean to log this drink?"
}

// Get today's summary
let summary = try await loggingService.getTodaySummary(userId: "user123")
print("Today: \(Int(summary.totalCaloriesKcal)) calories from \(summary.drinkCount) drinks")
```

### Usage Example: Custom Drink

```swift
let result = try await loggingService.logCustomDrink(
    name: "Homemade Sports Drink",
    liquidType: .other,
    volume: 500,
    calories: 120,
    sodium: 400,
    sugar: 30,
    userId: "user123"
)

// Now it's saved for future use
let customDrinks = try loggingService.getCustomDrinks(for: "user123")
print("You have \(customDrinks.count) custom drinks saved")
```

### Prevention of Double-Tracking Mess

**Problem:** Users might log the same drink twice (forget they logged it, screen lag, etc.)

**Solution - Three Layers:**

1. **Detection** 🔍
   - Monitors timestamps of all drink logs
   - Flags if two similar drinks logged within 5 minutes
   - Calculates confidence score (0.0 to 1.0)

2. **Warning** ⚠️
   - Shows clear alert: "Similar drink logged 45 seconds ago"
   - Displays both drink names and times
   - Lets user choose: Keep both or delete one

3. **Toggle** 🎚️
   - Users can turn off warnings if they prefer
   - Can be disabled in settings
   - Settings stored per-user

**Key Design Decision:** Calorie tracking is **OFF by default**
- Prevents auto-logging bloat
- Users opt-in when they want it
- Clear choice, not hidden feature

### Database Tables (In Migration007)

```
hydration_settings
├── user_id (PK)
├── calorie_tracking_enabled
├── double_track_warning_enabled
├── track_sodium
├── track_sugar
└── daily_goal_ml

hydration_calorie_entry
├── id (PK)
├── hydration_sample_id (FK)
├── drink_id
├── drink_name
├── calories_kcal
├── sugar_grams
├── timestamp
└── double_track_warning

hydration_custom_drink
├── id (PK)
├── user_id
├── name
├── liquid_type
├── volume_ml
├── calories_kcal
├── sodium_mg
├── sugar_grams
└── created_at
```

---

## Next Steps

1. **Write iOS UI** — Drink picker, calorie display, settings panel
2. **Add Health Module Integration** — Auto-detect exercises
3. **Setup Notifications** — Scheduled hydration reminders
4. **Add Charts** — Visualize hydration + calories over time
5. **Implement Trends** — Weekly/monthly compliance summaries
6. **Add Settings UI** — Let user configure profiles and features

---

## Questions?

See `docs/features/hydration.md` for:
- Complete feature specification
- Database schema details
- Urgency threshold calculations
- Liquid type nutritional reference
- Advanced usage examples
- Performance notes
- Thread safety guarantees
