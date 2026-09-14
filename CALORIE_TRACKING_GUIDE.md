# Calorie Tracking Integration Guide

## Overview

The hydration module now includes **optional, intelligent calorie tracking** that automatically logs calories from drinks while preventing the data mess that double-tracking causes.

**Key Design Principle:** Calorie tracking is **OFF by default** (opt-in feature) to ensure users don't accidentally create duplicate entries.

---

## Problem: Double-Tracking Mess

### Why This Matters
Users tracking both hydration AND calories might accidentally log the same drink twice:

```
Real scenario:
- User opens hydration app, logs "Pepsi" (250ml, 150 cal)
- Same user opens nutrition app minutes later
- Logs "Pepsi" again (forgot they already logged it)
- Calorie total now shows 300 cal instead of 150
- Data is corrupted
```

### Why It Happens
1. **Multiple apps** — Users juggle different trackers
2. **Forgetfulness** — "Did I already log that?"
3. **Screen lag** — Tap twice, logs twice
4. **Confusion** — Not clear if a drink was logged

---

## Solution: Three-Layer Prevention

### Layer 1: Detection 🔍

The system monitors all drink logs and detects suspicious patterns:

```
Criteria for flagging:
- Same or similar drink
- Logged within 5 minutes (configurable)
- Same user, same day
- Calculates confidence score (0.0 to 1.0)
```

**Confidence Scoring:**
```
Very High (0.8+)    = 80%+ likely duplicate
High (0.6-0.8)      = Likely duplicate
Moderate (0.4-0.6)  = Possible duplicate
Low (0.0-0.4)       = Probably different drink
```

### Layer 2: Warning ⚠️

When suspicious activity is detected, user sees:

```
⚠️ Possible duplicate
"Similar drink (Pepsi) logged 45 seconds ago"

Actions:
[Keep Both] [Delete Last] [Dismiss]
```

**User has full control:**
- Can keep both (if intentional)
- Delete the duplicate
- Ignore warning (for power users)

### Layer 3: Toggle 🎚️

Users can completely disable warnings in settings:

```swift
// Turn off double-track warnings
try settingsStore.setDoubleTrackWarning(for: "user123", enabled: false)
```

---

## Feature: Drink Catalog

### 25+ Pre-Populated Drinks

**Sodas (Regular & Diet):**
- Pepsi (150 cal) / Diet Pepsi (0 cal)
- Coca-Cola (140 cal) / Diet Coke (0 cal) / Coke Zero (0 cal)
- Sprite (140 cal)
- Fanta (160 cal)

**Sports Drinks:**
- Gatorade (140 cal, 290mg sodium)
- Powerade (150 cal, 200mg sodium)
- Gatorade Zero (0 cal, 310mg sodium) ← Best post-exercise option

**Electrolyte Solutions:**
- Pedialyte (0 cal, 750mg sodium, high electrolytes)
- Coconut Water (45 cal, 250mg sodium, natural)

**Beverages:**
- Black Coffee (2 cal)
- Latte (150 cal)
- Black Tea (2 cal)
- Iced Tea Sweetened (90 cal)
- Whole Milk (150 cal)
- Orange Juice (110 cal)
- Red Bull (110 cal)
- Monster Energy (160 cal)
- Kombucha (30 cal)

All entries include:
- Volume (mL)
- Calories (kcal)
- Sodium (mg)
- Sugar (g)

### Search Feature

```swift
let results = CatalogDrinks.search(query: "diet")
// Returns: [Diet Pepsi, Diet Coke, Coke Zero]

let coke = CatalogDrinks.byId("catalog_coke")
// Returns: Coca-Cola drink object
```

---

## Feature: Custom Drinks

Users can add beverages not in the catalog:

```swift
let result = try await loggingService.logCustomDrink(
    name: "My Energy Mix",
    liquidType: .other,
    volume: 500,
    calories: 200,
    sodium: 300,
    sugar: 45,
    userId: "user123"
)

// Saved automatically for future use
let customDrinks = try loggingService.getCustomDrinks(for: "user123")
```

**Persisted in Database:**
- Full nutritional info stored
- Easily accessible for future logging
- Tied to user account

---

## Settings: Five Toggles

### 1. Calorie Tracking
```
Default: OFF
When ON: Automatically logs calories with each drink
When OFF: Hydration only, no calorie tracking
```

**Use Cases:**
- ON: User also tracking calories
- OFF: User only cares about hydration

### 2. Double-Track Warnings
```
Default: ON
When ON: Shows warning if suspicious duplicate detected
When OFF: Silent logging (for power users who want full control)
```

**Use Cases:**
- ON: First-time users, want safety
- OFF: Advanced users who carefully track

### 3. Auto-Log from Health
```
Default: OFF
When ON: Reads drinks from Health app if available
When OFF: Manual logging only
```

### 4. Reminders
```
Default: ON
When ON: Shows hydration reminders
When OFF: Manual checking only
```

### 5. Track Sodium
```
Default: ON
When ON: Logs sodium with each drink (important for electrolyte balance)
When OFF: Skip sodium tracking
```

### Bonus: Track Sugar
```
Default: ON
When ON: Logs sugar and warns if >35g per drink
When OFF: Skip sugar tracking
```

---

## Presets for Quick Setup

Instead of toggling each setting, users can pick a preset:

### Minimal
```
Best for: Users who only want basic hydration tracking
- Calorie tracking: OFF
- Reminders: OFF
- Sodium/Sugar tracking: OFF
```

### Standard (Default)
```
Best for: General hydration tracking with reminders
- Calorie tracking: OFF
- Reminders: ON (hourly)
- Double-track warnings: ON
- Sodium tracking: ON
```

### Comprehensive
```
Best for: Users wanting full tracking
- Calorie tracking: ON
- Double-track warnings: ON
- Auto-log from Health: ON
- Reminders: ON (every 45 min)
- Sodium & Sugar: ON
```

### Calorie Counter
```
Best for: Users primarily tracking calories
- Calorie tracking: ON (focused)
- Double-track warnings: ON (critical here)
- Reminders: ON (every 2 hours, less frequent)
- Sodium & Sugar: ON
```

### Athlete
```
Best for: High-activity users
- Calorie tracking: ON
- Auto-log from Health: ON (exercises auto-detected)
- Reminders: ON (every 30 min, more frequent)
- Sodium & Sugar: ON (track electrolyte loss)
```

---

## Architecture: How It Works

### Data Flow: Logging a Drink

```
User taps "Log Drink"
    ↓
Select drink (catalog or custom)
    ↓
HydrationLoggingService.logDrink()
    ↓
1. Creates HydrationSample ─→ Saved to DB
    ↓
2. Checks settings
    ↓
3a. If calorie tracking ON:
    │  ├─ Calculate calories
    │  ├─ Log to hydration_calorie_entry
    │  └─ Run double-tracking detection
    │
3b. If calorie tracking OFF:
       └─ Skip calorie logging
    ↓
4. Generate warnings
    ├─ High sugar? (>35g)
    ├─ High sodium? (suggest exercise timing)
    └─ Possible duplicate?
    ↓
Return DrinkLoggingResult
    ├─ Sample ID
    ├─ Calorie entry ID (if tracked)
    └─ Warnings (if any)
    ↓
UI displays result + any warnings
```

### Database Tables

**hydration_calorie_entry:**
```
id                  — Entry ID
hydration_sample_id — Links to hydration sample
drink_id            — Catalog or custom drink ID
drink_name          — For display
calories_kcal       — The logged amount
sugar_grams         — Optional
timestamp           — When logged
double_track_warning — 0 = no warning, 1 = flagged as suspicious
```

**hydration_settings:**
```
user_id                         — Links to user
calorie_tracking_enabled        — 0 = OFF, 1 = ON
double_track_warning_enabled    — 0 = OFF, 1 = ON
auto_log_from_health            — 0 = OFF, 1 = ON
reminders_enabled               — 0 = OFF, 1 = ON
reminder_interval_minutes       — Default 60
track_sodium                    — 0 = OFF, 1 = ON
track_sugar                     — 0 = OFF, 1 = ON
```

**hydration_custom_drink:**
```
id           — Custom drink ID
user_id      — Owner
name         — User's chosen name
liquid_type  — Enum (water, other, etc.)
volume_ml    — Serving size
calories_kcal— Calories per serving
sodium_mg    — Sodium per serving
sugar_grams  — Sugar per serving (optional)
created_at   — When user added it
```

---

## Usage Scenarios

### Scenario 1: Diet-Conscious User

```
Setting: Calorie tracking ON, Double-track warnings ON

Day 1:
10:00 AM - Logs "Diet Pepsi" (0 cal)
         - System: "Logged 0 calories"
11:00 AM - User opens food tracker by mistake, considers logging again
         - But APP: "⚠️ Similar drink logged 60 min ago"
         - User: "Good catch, I already logged it"
```

### Scenario 2: Athlete Tracking Everything

```
Setting: Athlete preset (all tracking ON)

Scenario:
- Runs 10K at 8 AM
- Health app: Auto-detects 60-minute workout
- 10:45 AM - Logs "Gatorade" (140 cal)
  - Hydration: ✓ Logged
  - Calories: ✓ 140 cal added to daily total
  - Sodium: ✓ 290mg logged (important after sweat loss)
  - System: "Good choice - sports drink recommended post-exercise"
```

### Scenario 3: Simple Hydration User

```
Setting: Minimal or Standard preset (calorie tracking OFF)

Day 1:
- Logs water at 9am
- Logs water at 12pm
- Logs water at 3pm
- Gets reminder at 6pm (if reminders ON)
- No calorie logging, no extra complexity
- Data stays clean and simple
```

---

## Preventing the Data Mess: Implementation

### Detection Algorithm

```swift
func detectDoubleTracking(userId: String, timeWindowMinutes: Int = 5) {
    // Get recent logs (last 100)
    let recentLogs = fetchLast100(userId: userId)
    
    // Compare each pair
    for log in recentLogs {
        for otherLog in recentLogs {
            if log.id != otherLog.id {
                let timeDiff = abs(log.timestamp - otherLog.timestamp)
                
                if timeDiff < timeWindowMinutes.inSeconds {
                    // Calculate confidence
                    let confidence = 1.0 - (timeDiff / windowInSeconds)
                    
                    // Flag if high confidence
                    if confidence > 0.5 {
                        addSuspicion(log.id, suspiciousWith: otherLog.id, confidence)
                    }
                }
            }
        }
    }
}
```

### User Actions

When warning appears:

```
⚠️ Duplicate Alert
"Pepsi logged 30 seconds ago"

[Keep Both]  →  Keep both entries (intentional duplicate)
[Delete]     →  Delete the new entry
[Dismiss]    →  Ignore this time, keep watching
[Settings]   →  Turn off these warnings
```

---

## Summary

| Aspect | Approach | Benefit |
|--------|----------|---------|
| **Tracking** | Optional (OFF by default) | Users control complexity |
| **Detection** | Automatic with confidence score | Catches real duplicates |
| **Prevention** | Clear warnings + user control | Prevents data mess |
| **Customization** | 5 toggles + presets | Works for all use cases |
| **Data Quality** | Preservation of source data | No guessing, no corruption |

---

## FAQ

**Q: What if I intentionally log the same drink twice?**
A: You can choose "Keep Both" when the warning appears, or turn off warnings.

**Q: Does this slow down the app?**
A: Detection only runs if calorie tracking is enabled, and only on recent logs (no full scan).

**Q: Can I merge duplicate entries after logging?**
A: Currently no, but undo last drink is available.

**Q: What about syncing across devices?**
A: Settings and customs drinks sync with user account. Double-tracking detection runs per device.

**Q: Can I export calories to MyFitnessPal?**
A: Future feature - currently internal tracking only.

**Q: Are there privacy concerns?**
A: All data is local/account-specific. No external calorie database queries.
