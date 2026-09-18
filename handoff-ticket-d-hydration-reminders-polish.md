> **STATUS UPDATE (2026-09-19): This ticket's premise didn't match the repo, and the scope was
> narrowed before any code was written.**
>
> Two things below in "What's already built" are wrong or misleading:
> - `CircadianContextEngine` is real, but it classifies *shift-schedule stability*
>   (`.stableDay`/`.transitionEarlier`/`.recovery`/etc. from shift history) — it has no
>   `sleepWindow()`, `peakAlertnessTimes()`, or `context(at:)` time-of-day method. Step 3's
>   pseudocode calls APIs that don't exist.
> - The app's actual reminder UI (`Native/Almanac/SettingsView.swift` +
>   `NotificationScheduler.swift`) did not use `HydrationReminderService`/`HydrationSettings`
>   at all — it stored its own toggle/times in `@AppStorage` (UserDefaults) with 3 hardcoded
>   default times, completely disconnected from the SQLite-backed settings this doc describes
>   as the source of truth.
>
> Per product decision on 2026-09-19: **defer circadian awareness to a later ticket** (it needs
> a real peak-alertness/sleep-window model that doesn't exist yet — a design question, not a
> polish task). Instead, did the smallest real fix: wired `SettingsView`/`NotificationScheduler`
> to `HydrationSettingsStore` so there's one source of truth for reminder settings, replacing
> the `@AppStorage` copy. See `Native/Almanac/HydrationModel.swift` (new `hydrationSettings`
> property, `loadSettings()`/`saveReminderSettings()`) and `Native/Almanac/SettingsView.swift`
> (reminder controls now edit interval/start-hour/end-hour, matching what
> `HydrationSettings` actually models, instead of 3 free-form times).
>
> **Not done:** messaging-tone variation, snooze, circadian-aware timing, mute-overnight toggle
> — all still open, same as before. **Not verified:** `Native/Almanac/*.swift` is outside the
> SPM package (see `Package.swift` — only `AlmanacCore`/`CSQLite`/`Adhan` build there), so this
> change could not be compiled or tested via the Linux/Docker toolchain. Needs Xcode/Simulator
> verification on the iMac before it's trusted.
>
> The rest of this file is kept as-is for reference; its pseudocode and "already built" table
> should not be taken at face value.

---

# Handoff: Ticket D — Hydration Reminders Polish (2026-09-18)

**Status:** Ready to execute. No blockers.

**Next session:** Tune reminder timing, test circadian alignment, refine messaging (3–4 hours).

---

## What Ticket D is

The hydration reminder system exists and fires notifications. This ticket refines it:
- Ensure reminders fire at sensible times (not overnight, not during sleep)
- Verify timing respects the user's circadian rhythm (peak thirst times)
- Adjust messaging if it's too repetitive or unclear
- Allow user to disable/customize frequency

Output: A polished reminder system that feels natural, not intrusive.

---

## What's already built (you don't need to build)

| Component | Status | File | Notes |
|---|---|---|---|
| `HydrationReminderService` | ✅ Done, tested | `Hydration/HydrationReminderService.swift` | Schedules local notifications. Has fixed timing, no circadian awareness yet. |
| `HydrationSettings`, `HydrationProfile` | ✅ Done | `Stores/Hydration*Store.swift` | Store user preferences and hydration profile. |
| `CircadianContextEngine` | ✅ Done, tested | `Circadian/CircadianContextEngine.swift` | Provides circadian data (peak alertness, trough times, sleep window). |
| Notification scheduling | ✅ Done | `UNUserNotificationCenter` | iOS native; system handles delivery. |
| Drink catalog | ✅ Done | `Stores/HydrationDrinkStore.swift` | Has 50+ drinks with calorie/sodium/sugar data. |

**What you need to provide:** Your preferred reminder frequency (e.g., "every 2 hours during waking hours"), messaging tone (medical vs. conversational), and any circadian inputs (sleep window, peak thirst times).

---

## The polish task

### Step 1: Define reminder rules

Answer these:

1. **Frequency:** How often should reminders fire?
   - Every 2 hours during waking hours?
   - Every hour during high-heat times?
   - Adaptive (every 1.5 hrs if it's hot, every 3 hrs if it's cool)?

2. **Sleep window:** When should reminders NOT fire?
   - 22:00–07:00?
   - User's logged sleep times?
   - Circadian trough (lowest alertness)?

3. **Peak times:** When should reminders be more frequent?
   - During exercise?
   - During high circadian alertness?
   - During fasting?

4. **Messaging tone:** How should reminders sound?
   - Medical: "You are 2% dehydrated. Drink 250ml water."
   - Conversational: "Thirsty? Have some water 💧"
   - Motivational: "Time to hydrate! You're doing great."

5. **Customization:** What should users control?
   - Turn reminders on/off?
   - Change frequency (daily, hourly, etc.)?
   - Mute during certain times?
   - Snooze for 30 min?

### Step 2: Audit current timing

Look at `HydrationReminderService` and check:

```swift
// Current implementation (hypothetical)
func scheduleReminders() {
    let times = [09:00, 12:00, 15:00, 18:00, 21:00]  // Fixed times
    for time in times {
        scheduleNotification(at: time, title: "Drink water", body: "You should hydrate")
    }
}
```

**Questions to ask:**
- Does it fire during sleep? (e.g., 21:00 reminder at night?)
- Does it account for user's actual sleep window?
- Does it know about exercise/fasting context?
- Can the user change frequency?
- Does it use the `CircadianContextEngine` at all?

### Step 3: Refine the logic

If circadian awareness is missing, add it:

```swift
func scheduleReminders() {
    let sleepWindow = circadianEngine.sleepWindow()  // e.g., 22:30–06:30
    let peakTimes = circadianEngine.peakAlertnessTimes()  // e.g., 08:00, 14:00, 18:00
    
    var reminderTimes: [Date] = []
    let wakeStart = sleepWindow.end   // e.g., 06:30
    let sleepStart = sleepWindow.start // e.g., 22:30
    
    // Schedule reminders every 2 hours during waking, avoiding sleep window
    for hour in stride(from: wakeStart, to: sleepStart, by: 2.hours) {
        if !sleepWindow.contains(hour) {
            reminderTimes.append(hour)
        }
    }
    
    // Add extra reminders during peak times
    for peakTime in peakTimes {
        if !reminderTimes.contains(peakTime) && !sleepWindow.contains(peakTime) {
            reminderTimes.insert(peakTime, sortedBy: chronological)
        }
    }
    
    for time in reminderTimes {
        let message = messageForTime(time)  // Tone-aware messaging
        scheduleNotification(at: time, title: "Hydrate", body: message)
    }
}

func messageForTime(_ time: Date) -> String {
    let context = circadianEngine.context(at: time)
    switch context {
    case .peak:
        return "You're alert. Hydrate to stay sharp 💧"
    case .afternoon:
        return "Afternoon slump? Water helps. Take a sip."
    case .evening:
        return "Evening wind-down. Hydrate gently (no caffeine after water)."
    default:
        return "Time to drink water."
    }
}
```

### Step 4: Test edge cases

Create tests in `Tests/HydrationReminderPolishTests.swift`:

```swift
func testNoRemindersOvernightDuringSleep() {
    let sleepWindow = 22:30...06:30
    let reminders = service.scheduledReminders()
    
    for reminder in reminders {
        XCTAssertFalse(sleepWindow.contains(reminder.time),
                      "Reminder scheduled during sleep window: \(reminder.time)")
    }
}

func testRemindersRespectUserFrequencyPreference() {
    settings.reminderFrequency = .every3Hours
    let reminders = service.scheduledReminders()
    
    let gaps = zip(reminders.dropFirst(), reminders).map { $0.1 - $0.0 }
    for gap in gaps {
        XCTAssertGreaterThanOrEqual(gap, 3.hours - 5.minutes)  // Allow 5 min tolerance
    }
}

func testPeakTimeRemindersCluster() {
    let reminders = service.scheduledReminders()
    let peakTimes = circadianEngine.peakAlertnessTimes()
    
    for peakTime in peakTimes {
        let nearby = reminders.filter { abs($0.time - peakTime) < 1.hour }
        XCTAssertGreaterThan(nearby.count, 0, "No reminder near peak time \(peakTime)")
    }
}

func testMessagingVariesByContext() {
    let morning = Date(hour: 08, minute: 00)
    let evening = Date(hour: 20, minute: 00)
    
    let morningMsg = service.messageForTime(morning)
    let eveningMsg = service.messageForTime(evening)
    
    XCTAssertNotEqual(morningMsg, eveningMsg, "Messages should vary by time of day")
}
```

### Step 5: Integrate with settings

Add toggles to `HydrationSettings`:

```swift
struct HydrationSettings {
    var remindersEnabled: Bool = true
    var reminderFrequency: ReminderFrequency = .every2Hours  // .every1Hour, .every2Hours, .every3Hours
    var respectCircadianRhythm: Bool = true
    var muteOvernight: Bool = true
    var snoozeMinutes: Int = 30
    var messagingTone: MessageTone = .conversational  // .medical, .conversational, .motivational
}
```

Wire these to the UI (settings tab or modal):

```swift
Form {
    Toggle("Hydration Reminders", isOn: $settings.remindersEnabled)
    
    Picker("Frequency", selection: $settings.reminderFrequency) {
        Text("Every 1 hour").tag(ReminderFrequency.every1Hour)
        Text("Every 2 hours").tag(ReminderFrequency.every2Hours)
        Text("Every 3 hours").tag(ReminderFrequency.every3Hours)
    }
    
    Toggle("Respect circadian rhythm", isOn: $settings.respectCircadianRhythm)
    Toggle("Mute overnight", isOn: $settings.muteOvernight)
    
    Picker("Message tone", selection: $settings.messagingTone) {
        Text("Medical").tag(MessageTone.medical)
        Text("Conversational").tag(MessageTone.conversational)
        Text("Motivational").tag(MessageTone.motivational)
    }
}
```

### Step 6: Manual QA

Use the app for 24 hours (or simulate with mocked time):

- [ ] Reminders fire at expected times
- [ ] No reminders overnight (22:30–06:30 or user's sleep window)
- [ ] Reminders cluster around peak times
- [ ] Messages vary by time of day
- [ ] Settings changes take effect immediately
- [ ] Snooze for 30 min works
- [ ] Reminders continue if user leaves app open
- [ ] No duplicate reminders

---

## Acceptance criteria

- [ ] `HydrationReminderService` checks `CircadianContextEngine` and sleep window
- [ ] No reminders fire during sleep (overnight or user-defined window)
- [ ] Reminders respect user's frequency preference (1h, 2h, 3h, etc.)
- [ ] Messaging varies by time of day and circadian context
- [ ] `HydrationSettings` has toggles for frequency, tone, circadian respect
- [ ] Settings UI wired and functional
- [ ] 5+ tests cover timing, sleep avoidance, messaging variation
- [ ] Manual QA pass (24-hour observation or time-mocked test)

---

## Blockers

**None.** All dependencies (CircadianContextEngine, notification scheduling, settings storage) exist.

**Potential slowdown:** If the settings UI doesn't exist yet, adding it might add 1–2 hours. Mitigate by keeping it simple (just toggles and pickers; no complex layout).

---

## Estimated time breakdown

| Task | Est. | Notes |
|---|---|---|
| Define reminder rules (Step 1) | 0.5 hr | Answer 5 questions above |
| Audit current timing (Step 2) | 0.25 hr | Read the service code |
| Refine logic + circadian integration (Step 3) | 1–1.5 hrs | Core work; TDD if preferred |
| Add edge-case tests (Step 4) | 0.75 hr | 5+ tests |
| Wire settings UI (Step 5) | 0.5–1 hr | Depends if UI already exists |
| Manual QA (Step 6) | 0.5 hr | Real-time or mocked testing |
| **Total** | **3–4 hrs** | |

---

## Files to touch

- `Hydration/HydrationReminderService.swift` (edit to add circadian awareness)
- `Stores/HydrationSettings.swift` (edit to add frequency/tone/circadian toggles)
- `Settings/HydrationSettingsView.swift` (new or edit if exists)
- `Tests/HydrationReminderPolishTests.swift` (new)

---

## Skills for this work

- **`mattpocock-skills:implement`** — ship Steps 1–6 end-to-end (refine logic, add settings UI, write tests, QA)
- **`mattpocock-skills:tdd`** — all logic changes should be test-driven; step-by-step red-green-refactor for timing rules
- **`engineering:testing-strategy`** — define edge cases (midnight crossings, DST, sleep-window changes, snooze interactions) before coding

**Recommendation:** `engineering:testing-strategy` (30 min) to nail down edge cases → `mattpocock-skills:tdd` (2–3 hrs) to implement the logic + tests.

---

## Definition of done

- Reminders fire only during waking hours (no overnight)
- Timing respects user's circadian rhythm
- Frequency can be adjusted (1h, 2h, 3h, or custom)
- Messaging tone is customizable and varies by context
- Settings persist and take effect immediately on app restart
- 5+ tests, all passing
- Manual QA confirms natural feel (not too intrusive, not too sparse)

---

## Open questions for Yazeed

1. **Preferred frequency:** Every 1, 2, or 3 hours during waking? Or adaptive?
2. **Sleep window:** Fixed 22:30–06:30, or should it follow user's logged sleep times?
3. **Peak times:** Should reminders cluster around high-alertness times, or stay evenly spaced?
4. **Messaging tone:** Medical, conversational, or motivational? Or mixed based on time of day?
5. **Customization scope:** Do users need to set all of this, or pick one preset ("Aggressive", "Balanced", "Gentle")?

