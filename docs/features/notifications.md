# Almanac — Notifications (Slice 11)

**Status:** §14 wired end to end, 2026-09-29. Trigger arithmetic, the
suppression matrix and the per-type switches were all already written and
tested in `AlmanacCore`; what was missing was a caller. The ~480 lines of
notification logic in `Sources/AlmanacCore/Notifications/` had no production
caller at all, and the app's own scheduler took raw `[DateComponents]`.

## Corrected 2026-10-06 — four defects that reached suhoor and iftar

- **Nothing ever made a day a fast day**, so suhoor and iftar were never planned
  in the running app. See `docs/features/fasting.md` §0.
- **Past reminders were planned, and fired again on every foreground.** The
  planner walks from the start of today's logical day and promised to drop
  instants in the past or beyond the horizon; it never did, and the scheduler
  turns a past instant into "fire in one second". Opening the app after Maghrib
  announced iftar again each time. `plan()` now keeps only `now < fireAt ≤ now +
  horizon`. Two planner tests had been asserting the bug (a suhoor two hours in
  the past was expected in the plan) and were corrected.
- **The scheduler's "is this ours" check was reversed** —
  `ownedPrefix.hasPrefix(id)` rather than `id.hasPrefix(ownedPrefix)` — so stale
  requests were never removed, "Turn all reminders off" cancelled nothing, and
  "Queued now" always read 0.
- **The dry-fast axis was evaluated "as of now" for 48 hours.** During a fast,
  that muted every water reminder for two days and *tomorrow's suhoor*. It is now
  per fire instant (`DryFastSpans`): each scheduled fast day contributes
  `[Fajr, Maghrib)` — or up to the moment its fast was broken — so tomorrow's
  suhoor and tonight's water are planned, and tomorrow's daytime water is muted
  before tomorrow's fast has begun. A dry session with no schedule or prayer
  times behind it still mutes the whole pass, as before.

**Added: `prayer`**, an alert at each chosen prayer's time (Migration050).
Seeded **off**; the switch is on the Prayer screen and in Reminders, and
`prayer_settings.alertPrayers` holds which of the five prayers alert. It is not
an Appendix B row and nothing suppresses it — a prayer's time is the same fact
during a fast or a shift, and the user asked to be told it. On a fast day with
iftar on, Maghrib's alert is left to iftar, which fires at the same instant.
Identifier `almanac.prayer.<name>.<day>`.

## What the feature is

Ten notification types — §14.2's nine plus `prayer` — all local (`UNUserNotificationCenter`, no
push server). For each one: when it fires, what it says, whether the user wants
it, and whether the user's current state says it should be suppressed.

| Type | Fires | Default | Identifier |
|---|---|---|---|
| `readiness` | End of the primary sleep episode, or the expected/averaged wake time | on | `almanac.readiness.<day>` |
| `water` | Every N minutes across the active window | on | `almanac.water.<day>.<epoch>` |
| `meal` | The time set per meal type | off | `almanac.meal.<mealType>.<day>` |
| `bedtime` | 30 min before `expectedSleepWindowStart` | off | `almanac.bedtime.<day>` |
| `supplement` | Each active plan's own time | off | `almanac.supplement.<planId>.<day>` |
| `suhoor` | 20 min before Fajr, on religious fast days | on | `almanac.suhoor.<day>` |
| `iftar` | Maghrib, on religious fast days | on | `almanac.iftar.<day>` |
| `contextual_snack` | **Delivered immediately**, not scheduled | off | `almanac.contextual_snack.immediate` |
| `contextual_hydration` | ~60 min before the usual time for a logged meal type | off | `almanac.contextual_hydration.<mealType>.<day>` |
| `prayer` | Each chosen prayer's time (not Maghrib on a fast day with iftar on) | off | `almanac.prayer.<name>.<day>` |

The on/off column is §5.25's default table, transcribed in `Migration045`.

## The four layers, and why there are four

```
NotificationRuleStore        per-type on/off, user-set times      (SQLite)
NotificationTriggerAssembler when each type fires                  (reads stores)
NotificationSuppressionContextAssembler  the five axes, now        (reads stores)
NotificationSuppressionMatrix whether to send, given the axes     (pure)
        │
        ▼
NotificationPlanner          one pass → [PlannedNotification]      (reads stores)
        │
        ▼
NotificationScheduler        make UNUserNotificationCenter agree    (Darwin only)
        ▲
NotificationModel            the app's entry point                  (@MainActor)
        ▲
NotificationSettingsView     per-type switches                      (SwiftUI)
```

The two pure types (`NotificationTriggerTimeComputer`, `NotificationSuppressionMatrix`)
were already there and stay untouched. The two assemblers were already there and
are now actually called. `NotificationPlanner` is new and is the piece that was
missing: it is §14.1's "on each scheduling run" as one function.

**The interface is small on purpose.** A caller learns `plan()` and
`immediateSnackSuggestion()`; everything else — which days the horizon touches,
which type's trigger rule applies, what each one says, what the matrix says about
it — happens behind those. Tests reach the same seam callers do, so
`NotificationPlannerTests` exercises all nine types and five suppression axes
through two methods rather than through the internals.

## The suppression limitation, stated plainly

`NotificationSuppressionContextAssembler`'s own doc comment records that three of
Appendix B's five axes (`isDryFastActive`, `isConfirmedIFActive`,
`isReadinessAlreadyFinal`) can only be evaluated "now" — the stores behind them
have no point-in-time variant. The other two (`isNightShift`,
`isPostShiftSleep`) carry their own start/end timestamps and are evaluated
correctly for an arbitrary instant.

`NotificationPlanner` therefore evaluates suppression **per notification, at that
notification's own fire instant**, rather than once for the whole pass. This is
not cosmetic:

- `isNightShift` and `isPostShiftSleep` are then *right* for a notification 30
  hours out. A night shift tonight suppresses tonight's bedtime reminder and
  leaves tomorrow's alone. `suppressionIsPerFireInstant` pins this, because a
  pass-wide decision gets one of those two wrong.
- The other three axes carry this pass's value into future rows. A fast that
  starts at 04:00 tomorrow suppresses tomorrow's water reminders only from the
  pass that observes it — which is the pass that runs when the user next opens
  the app or logs something.

This is §14.1's own architecture, not a workaround: the spec makes the *pass*
the unit of work and reruns it on every log entry, shift change and app launch.
The consequence is that the plan is a **snapshot**, valid as of `computedAt`, and
the app must keep rerunning the pass. That is why the wiring below is a
reconciliation and not a one-time schedule.

## The wiring, and why it is pull-based

`docs/features/fasting.md` records this repo's known multi-site failure mode:
six hydration write paths had to be wired by hand for night-window assignment,
with the note that "the seventh path added later will be the one that forgets".
§14.1 names four kinds of event that should trigger a scheduling pass — app
launch, any state-changing log entry, a shift change, prayer times
recalculating — spread across most of the app. Wiring a call into each is the
same mistake at a larger scale.

So the pass is **pull-based and idempotent**: `NotificationPlanner.plan()` reads
current state, and it is safe to call from anywhere including code that has no
idea notifications exist. `NotificationModel.reconcileNotifications()` is the
one entry point, and it is wired to the two places every one of those events
passes through anyway:

1. **`AlmanacApp`'s `scenePhase == .active` handler** — which is already the home
   of `prayerModel.ensureCache()` and `fastingModel.ensureToday()`. The pass runs
   after those, because suhoor and iftar triggers are derived from exactly the
   prayer times and the fast state they maintain. This one call covers app
   launch, foreground, shift changes and prayer recalculation, because all four
   change state that the *next* foreground pass reads.
2. **`NotificationSettingsView`, after any switch is flipped** — a deliberate
   action whose whole point is to take effect now.

A missed call site therefore costs **one pass of staleness, not a permanently
wrong schedule** — the next foreground repairs it. That is the property worth
having, and it is why this is a reconciliation rather than a fifth and sixth call
site.

`NotificationScheduler.reconcile(_:)` is the OS half, and it diffs rather than
nuke-and-refills: it adds what is missing, removes only what the plan no longer
wants, and leaves everything else alone. Two runs over unchanged state add and
remove nothing (`planIsStable`, and the app's own repeated foreground passes).

## Deliberate decisions, and what they cost

**Two switches for water, and water requires both.** `notification_rule.water`
is the spec's §5.25 default (on). `hydration_settings.remindersEnabled` is the
toggle the app already shipped and the user already understands. The planner
requires *both* to be on. Either one saying off means off. A user who has turned
their water reminders off must not keep getting them because a schema default
disagrees, and introducing a third switch to arbitrate would be worse than the
ambiguity.

**The `suppressDuring*` columns are created and never written.** §5.25 names
four of them. Appendix B is the authority on what suppresses what, and
`NotificationSuppressionMatrix` already transcribes it as pure, tested logic.
Storing a second, per-row, *writable* copy of that matrix would be a rule that
can disagree with itself. The columns exist because the spec names them;
`testSuppressionColumnsAreNeverWritten` pins that they stay at their defaults.

**`scheduledTimeHHMM` stores an integer minute-of-day, not `"HH:MM"`.** The
column keeps the spec's name and its `"HH:MM"` text format; the Swift side holds
minutes since midnight, the same representation `meal_reminder_setting` and
`supplement_plan` already use, because every time in this repo is arithmetic
before it is text. `testStoredAsHHMM` checks the column still reads `"07:05"`.

**Water's interval precedence:** `notification_rule.intervalMinutes` →
`hydration_settings.reminderIntervalMinutes` → the spec's 90-minute default. Each
level is tested, including the case where no `hydration_settings` row exists at
all, which is the only situation in which the spec's default is reachable.

**The horizon is 48 hours (§14.1), which from some instants spans three logical
days, not two.** `daysCovered` bounds the loop at three, and that bound is
exactly right rather than an arbitrary truncation — `horizonIsBounded` pins the
three-day result and `horizonIsRespected` shows a shorter horizon covering
fewer.

**Nothing is deleted on failure.** `reconcile` returns what it added, removed and
*failed*; the failure list becomes a user-visible message rather than a swallowed
error. A notification the OS refused is a different problem from one the plan
did not ask for, and they are not merged.

**Identifiers are the diff's key, and the app only ever removes its own.**
`almanac.`-prefixed requests that the plan no longer wants are removed; anything
else pending is left strictly alone. The previous `cancelAll` filtered by prefix
too, but it swept *all* prefixed requests on every schedule change, including
ones a user might have been relying on.

## Not built, and why

- **No notification permission prompt on launch.** `requestAuthorizationAndSchedule`
  is only called from a deliberate tap. A system prompt is a result of a user
  action; firing one on app open is how an app teaches people to dismiss prompts.
- **No repeat/recurrence.** Every notification is a one-shot
  `UNTimeIntervalNotificationTrigger`. The previous scheduler used repeating
  `UNCalendarNotificationTrigger`s, which is precisely why a single rule change
  could not unschedule them.
- **The pre-workout snack suggestion is not scheduled.** §14.2 gives it no lead
  time and says it is computed at log time and app launch, so it is delivered
  immediately by `deliverNow`. It still goes through the matrix.
- **Suppression columns are read-only** — see above.
- **No per-type user-set times for readiness, water, bedtime, suhoor, iftar.** The
  storage exists (`scheduledTimeHHMM`); the settings screen exposes switches and
  the existing water interval only. Time-adjustment for the other types is a
  follow-up, and until then those types have no time for a user to have set.
- **Nothing verifies a notification actually arrived.** That is a device-only
  step and is listed unrun in `docs/acceptance-checklist.md`.

## Tests

`NotificationRuleStoreTests` (11) — seeded defaults against §5.25, round-trips,
validation, corrupt-column tolerance, and the "suppression columns are never
written" invariant.
`NotificationPlannerTests` (28) — all nine types wired end to end, all five
suppression axes, per-fire-instant vs per-pass evaluation, horizon bounds,
identifier uniqueness, and the immediate suggestion's four cases.
`NotificationSettingsUITests` (5) — every type has a switch, the screen states
its authorization, a switch flips and reverts, the destructive action asks first.
