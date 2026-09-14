# Hydration Tracking Implementation Checklist

## Phase 1: Backend Verification ✅ COMPLETE

- [x] Verify Database.run() patterns in HydrationStore
- [x] Verify Database.query() patterns in all stores
- [x] Verify transaction usage in CalorieIntegration
- [x] Verify SQLValue type wrappers (.text, .real, .integer, .null)
- [x] Verify Row accessors (.string, .double, .int)
- [x] Verify Migration007 creates all 7 tables
- [x] Verify health bridge reads from health_sample
- [x] Verify calorie scaling calculations
- [x] Verify double-track detection algorithm
- [x] Verify settings default (calorie tracking OFF)
- [x] Create backend verification report
- [x] Create iOS integration guide
- [x] Create UI component library

## Phase 2: Swift Toolchain Verification ⏳ BLOCKED

**Status:** Awaiting Swift 6.3.3 in environment

- [ ] Run `source env.sh && swift build`
  - [ ] Verify all 10 Hydration*.swift files compile
  - [ ] Verify all Database API calls resolve
  - [ ] Verify all Row accessors work
  - [ ] Fix any compilation errors
  
- [ ] Run `swift test`
  - [ ] Execute all 73 test cases
  - [ ] Verify HydrationCalculator tests (8 cases)
  - [ ] Verify HydrationStore tests (12 cases)
  - [ ] Verify HydrationReminderService tests (11 cases)
  - [ ] Verify DrinkCatalog tests (9 cases)
  - [ ] Verify CalorieIntegration tests (10 cases)
  - [ ] Verify HydrationSettings tests (13 cases)
  - [ ] Fix any test failures

## Phase 3: iOS App Integration (iOS Target)

### 3.1: Project Setup
- [ ] Create iOS app target (if not exists)
- [ ] Add AlmanacCore as dependency in Package.swift or Xcode build settings
- [ ] Configure SQLite database path at app launch
- [ ] Create AppState class for shared services

### 3.2: Core Views - HydrationDashboard
- [ ] Create HydrationDashboardView
  - [ ] Display progress ring (current/goal)
  - [ ] Show percentage complete
  - [ ] Display hydration status emoji
  - [ ] Show stat cards: Volume, Goal, Calories (if enabled)
  - [ ] Add "Log Drink" primary button
  - [ ] Add quick-log buttons (250ml, 500ml, 350ml)
  - [ ] Show last drink consumed
  - [ ] Show navigation to settings

- [ ] Implement ProgressRingView
  - [ ] Circular progress indicator
  - [ ] Color changes (red < 0.25, orange < 0.5, yellow < 1.0, green >= 1.0)
  - [ ] Center text: volume / goal ml
  - [ ] Percentage display
  - [ ] Animated transitions

### 3.3: Core Views - Drink Picker
- [ ] Create DrinkPickerView
  - [ ] Search bar (25+ catalog drinks)
  - [ ] List all drinks with nutrition info
  - [ ] Display: name, calories, sodium per drink
  - [ ] Select drink to log
  - [ ] Show "Add Custom Drink" option

- [ ] Create DrinkRow component
  - [ ] Display drink icon emoji
  - [ ] Show drink name
  - [ ] Show calories and sodium
  - [ ] Highlight on selection

- [ ] Create VolumeInputView
  - [ ] Slider for custom volume (50-1000ml)
  - [ ] Display current volume
  - [ ] "Log" confirmation button
  - [ ] Real-time calorie/nutrition scaling

### 3.4: Core Views - Custom Drink
- [ ] Create CustomDrinkSheetView
  - [ ] Input: Name (required)
  - [ ] Input: Type (dropdown - 9 types)
  - [ ] Input: Volume (default 250ml)
  - [ ] Input: Calories (default 0)
  - [ ] Input: Sodium (default 0)
  - [ ] Input: Sugar (optional)
  - [ ] Save button (async operation)
  - [ ] Cancel button
  - [ ] Show loading state

- [ ] Implement custom drink persistence
  - [ ] Call HydrationLoggingService.logCustomDrink()
  - [ ] Save to hydration_custom_drink table
  - [ ] Return to drink picker
  - [ ] Show custom drinks in subsequent picks

### 3.5: Core Views - Settings Panel
- [ ] Create HydrationSettingsView
  - [ ] Profile section:
    - [ ] Display user ID
    - [ ] Activity level picker (sedentary - very high)
    - [ ] Body weight input (kg)
  
  - [ ] Tracking section:
    - [ ] Toggle: Calorie Tracking (OFF by default)
    - [ ] Toggle: Double-Track Warnings (ON by default)
    - [ ] Toggle: Track Sodium (ON)
    - [ ] Toggle: Track Sugar (ON)
  
  - [ ] Reminders section:
    - [ ] Stepper: Interval (30-120 min, default 60)
    - [ ] Stepper: Start hour (0-23)
    - [ ] Stepper: End hour (0-23)
  
  - [ ] Presets section:
    - [ ] Picker: Minimal / Standard / Comprehensive / Athlete / Calorie Counter
    - [ ] Apply preset on selection

### 3.6: Warning & Feedback
- [ ] Create WarningAlertView
  - [ ] Display warning type (double-track, high sugar, high sodium)
  - [ ] Show appropriate emoji (⚠️, 🚨, ℹ️)
  - [ ] Display message from DrinkLoggingWarning
  - [ ] "Dismiss" and "Keep" buttons
  - [ ] Color-coded background

- [ ] Implement warning handling
  - [ ] Show dialog when logDrink() returns warnings
  - [ ] Parse warning.type
  - [ ] Display appropriate message
  - [ ] Allow user to keep or undo

### 3.7: Data Display Components
- [ ] Create StatCard component
  - [ ] Icon, title, value layout
  - [ ] Light background color
  - [ ] Responsive sizing

- [ ] Create WeeklyTrendChart
  - [ ] Bar chart of 7-day hydration
  - [ ] X-axis: day of week (Mon-Sun)
  - [ ] Y-axis: hydration percentage
  - [ ] Color-coded bars

- [ ] Create DrinkTimelineView
  - [ ] List of drinks logged today
  - [ ] Per drink: emoji, type, time ago, volume
  - [ ] Reverse chronological order
  - [ ] Empty state message

### 3.8: Helper Components
- [ ] Create SearchBar component
  - [ ] Text input field
  - [ ] Magnifying glass icon
  - [ ] Clear button (X)
  - [ ] Styled background

- [ ] Create NutritionFactsView
  - [ ] Show drink name
  - [ ] Display volume (scaled)
  - [ ] Display calories (scaled)
  - [ ] Display sodium (scaled)
  - [ ] Display sugar (scaled)
  - [ ] Highlight if values exceed thresholds

- [ ] Create HydrationEmptyStateView
  - [ ] Large water drop icon
  - [ ] "Stay Hydrated!" heading
  - [ ] "Log your first drink" message
  - [ ] "Log Drink" button link

### 3.9: State Management
- [ ] Create AppState class
  - [ ] Initialize HydrationStore from shared database
  - [ ] Initialize CalorieIntegration
  - [ ] Initialize HydrationSettingsStore
  - [ ] Initialize HydrationLoggingService
  - [ ] Initialize HydrationReminderService
  - [ ] Load user profile on init
  - [ ] Refresh today's metrics on demand
  - [ ] @Published properties:
    - [ ] userProfile
    - [ ] todayMetrics
    - [ ] currentRecommendation
    - [ ] isLoading
    - [ ] errorMessage

- [ ] Implement async tasks
  - [ ] loadUserProfile()
  - [ ] refreshTodayMetrics()
  - [ ] logDrink() → calls HydrationLoggingService
  - [ ] updateSettings() → persists to database

## Phase 4: Health Framework Integration

### 4.1: Workout Sync
- [ ] Update HealthProvider protocol
  - [ ] Add workouts async stream
  - [ ] Expose HealthWorkout struct

- [ ] Connect HealthSyncService
  - [ ] Subscribe to workouts stream
  - [ ] Write to health_sample table (domain: .workouts)
  - [ ] Sync start_at and end_at timestamps

- [ ] Test health data flows to HydrationHealthBridge
  - [ ] Verify exerciseMinutes(on:Date) reads workouts
  - [ ] Verify isExerciseActive(at:Date) detects active workouts

### 4.2: Exercise Detection in UI
- [ ] Check exercise status when logging drink
  - [ ] Call HydrationHealthBridge.isExerciseActive()
  - [ ] If true, escalate recommendation urgency
  - [ ] Suggest sports drink instead of water
  - [ ] Show "Post-Exercise Recovery" tips

- [ ] Adjust metrics for exercise
  - [ ] HydrationCalculator adds ~500ml per 30 min exercise
  - [ ] Update recommended intake based on exerciseMinutes
  - [ ] Display exercise-adjusted goal in dashboard

### 4.3: Workout History
- [ ] Display recent workouts in dashboard (optional)
  - [ ] Show workout duration
  - [ ] Show recommended hydration boost
  - [ ] Link to drink logging

## Phase 5: Notifications & Reminders

### 5.1: Local Notifications Setup
- [ ] Request user notification permissions
  - [ ] UNUserNotificationCenter.requestAuthorization()
  - [ ] Handle permission grant/denial

- [ ] Create notification content
  - [ ] Use HydrationReminderService.getReminderMessage()
  - [ ] Include urgency emoji (🚨, ⚠️, 💧, ✨)
  - [ ] Include recommended volume
  - [ ] Include drink suggestions

### 5.2: Reminder Scheduling
- [ ] Implement notification scheduling
  - [ ] Timer or background task at reminder interval
  - [ ] Call HydrationReminderService.checkReminder()
  - [ ] If recommendation exists, send notification

- [ ] Handle notification tap
  - [ ] Open app to HydrationDashboardView
  - [ ] Pre-select suggested drink in DrinkPickerView
  - [ ] Focus on "Log Drink" action

### 5.3: Smart Escalation
- [ ] Implement urgency-based escalation
  - [ ] Low 🟢: Normal tone, standard message
  - [ ] Moderate 💧: Encouraging, "time to hydrate"
  - [ ] High ⚠️: Urgent, "needs attention"
  - [ ] Critical 🚨: Emergency, "drink now"

## Phase 6: Calorie Tracking Feature (Optional at Launch)

### 6.1: Calorie Display
- [ ] Show calorie total in dashboard (if enabled)
  - [ ] Call CalorieIntegration.getDailyTotal()
  - [ ] Display in stat card
  - [ ] Show breakdown by drink

- [ ] Display drink calories
  - [ ] Show in drink picker
  - [ ] Show in drink timeline
  - [ ] Highlight high-calorie drinks

### 6.2: Sugar & Sodium Warnings
- [ ] Implement high sugar warning
  - [ ] Trigger when > 35g per drink
  - [ ] Show warning color (red)
  - [ ] Message: "This drink has Xg sugar (high)"

- [ ] Implement sodium context
  - [ ] Show when > 300mg
  - [ ] Different message for exercise vs rest
  - [ ] Color: blue (informational)

### 6.3: Double-Track Prevention UI
- [ ] Show double-track warning dialog
  - [ ] "Similar drink logged Xs ago"
  - [ ] Display both drink names and timestamps
  - [ ] "Keep Both" or "Undo" buttons

- [ ] Handle user acknowledgment
  - [ ] Call CalorieIntegration.markAsReviewed()
  - [ ] Remove warning flag from database
  - [ ] Log the decision

## Phase 7: Analytics & Trends (Post-Launch)

- [ ] Weekly compliance percentage
- [ ] Monthly trend data
- [ ] Achievement badges
- [ ] Streak tracking (days with goal met)
- [ ] Export data functionality

## Phase 8: Testing & QA

### 8.1: Unit Tests (iOS)
- [ ] AppState initialization
- [ ] Metric calculations
- [ ] Settings persistence
- [ ] Custom drink creation
- [ ] Warning detection

### 8.2: Integration Tests
- [ ] Full drink logging flow
  - [ ] Select drink → log → verify database
  - [ ] Custom drink creation → picker update
  - [ ] Settings change → metric recalculation

- [ ] Health data flow
  - [ ] Workout logged → health_sample update
  - [ ] HydrationHealthBridge reads it
  - [ ] Recommendation escalated

- [ ] Reminder flow
  - [ ] Reminder triggers at interval
  - [ ] Notification appears with correct message
  - [ ] Tap opens app to correct screen

### 8.3: UI/UX Testing
- [ ] Dashboard displays correctly at all screen sizes
- [ ] Drink picker search works smoothly
- [ ] Settings changes persist across app launch
- [ ] Warnings appear at appropriate times
- [ ] Notifications are not spammy
- [ ] Empty states display correctly
- [ ] Loading states show during async operations
- [ ] Error messages are helpful

### 8.4: Data Quality Testing
- [ ] No orphaned calorie entries
- [ ] Double-track detection doesn't have false positives
- [ ] Scaling calculations preserve data integrity
- [ ] Settings apply consistently across the app
- [ ] Historical data persists after app updates

## Phase 9: Documentation

- [x] HYDRATION_QUICK_START.md — ✅ Complete
- [x] CALORIE_TRACKING_GUIDE.md — ✅ Complete
- [x] HYDRATION_iOS_INTEGRATION.md — ✅ Complete
- [x] BACKEND_VERIFICATION_REPORT.md — ✅ Complete
- [x] HYDRATION_UI_COMPONENTS.swift — ✅ Complete
- [ ] API Reference (generated from code)
- [ ] Troubleshooting guide
- [ ] Video walkthrough (optional)

## Phase 10: Release Preparation

- [ ] Security audit
  - [ ] No sensitive data logged
  - [ ] HealthKit permissions properly scoped
  - [ ] No credentials in database
  - [ ] HTTPS for any remote syncing

- [ ] Performance optimization
  - [ ] Dashboard loads in <200ms
  - [ ] Drink picker search < 100ms
  - [ ] Metrics calculation < 100ms
  - [ ] Reminder checks async

- [ ] Localization (if needed)
  - [ ] All UI strings in Localizable.strings
  - [ ] Support multiple languages
  - [ ] Metric system options (ml/L vs oz/gallon)

- [ ] Accessibility
  - [ ] VoiceOver support
  - [ ] Color contrast ratios meet WCAG AA
  - [ ] Interactive elements have labels

## Success Criteria

All phases must be completed with:

✅ `swift build` succeeds without warnings  
✅ `swift test` passes all 73 cases  
✅ iOS app compiles without errors  
✅ Dashboard displays hydration progress  
✅ Drink picker searches and logs drinks  
✅ Settings save and persist  
✅ Reminders fire with smart messaging  
✅ Exercise detection escalates recommendations  
✅ Calorie tracking OFF by default, user can enable  
✅ Double-track warnings appear when appropriate  
✅ Custom drinks save and reappear in picker  
✅ No crashes on any screen  
✅ Data persists across app restart  

---

## Current Status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 | ✅ COMPLETE | Backend verified against Database API |
| 2 | ⏳ BLOCKED | Awaiting Swift toolchain |
| 3 | ⏳ NOT STARTED | iOS app target not yet created |
| 4 | ⏳ NOT STARTED | Awaits Health framework setup |
| 5 | ⏳ NOT STARTED | Notification system not wired |
| 6 | ⏳ NOT STARTED | UI for calorie tracking planned |
| 7 | ⏳ FUTURE | Analytics post-launch feature |
| 8 | ⏳ NOT STARTED | Testing harness not set up |
| 9 | 🟡 IN PROGRESS | Core docs complete, API ref pending |
| 10 | ⏳ NOT STARTED | Release checklist not begun |

**Overall: 10% Complete (Phase 1 verified, Phase 2+ awaiting execution)**
