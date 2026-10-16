# Hydration & Caffeine audit — 2026-10-16

Phase 3 against BRD v1.6 §6.2, the hydration parts of §5.5, §6.13, §6.14,
§6.16, §6.21, and acceptance scenarios A1 and A5, as the 2026-10-16 handoff
asked. **The code and its tests are the evidence**; nothing here was run on a
device. "CI" means the core suite and UI suite as they passed at `76ed79b`
(run 38927873088).

**Outcome.** Water is complete in the app. **Caffeine is not**: nothing in the app
records caffeine, though the store and the "relative to intended sleep" rule
are built and tested in the core. That breaks A1's latte step and three of
§6.2's five lines. Three smaller gaps need an owner call.

## Requirements

| # | Requirement | Where | State | Evidence |
|---|---|---|---|---|
| 1 | Water logged against a daily target | §6.2 | **Built** | `HydrationStoreTests`, `HydrationFeatureTests`; Quick Log +250/500/750; Settings daily goal; UI `testLoggingADrinkShowsItOnTheDashboardWithCalories` (CI) |
| 2 | One drink entry fills hydration, caffeine and nutrition (a latte) | §6.2, A1 | **Built 2026-10-16** (see below); was Partial | Hydration and calories: `HydrationLoggingService.logDrink` attaches scaled calories, sodium and sugar to the hydration row (`HydrationFeatureTests`). **Caffeine: no.** `Drink` has no caffeine field, and nothing in `Native/` writes `caffeine_log` |
| 3 | Caffeine presets per drink type, editable | §6.2 | **Built 2026-10-16**: catalog presets, editable per drink (Migration 065), and a custom drink's own caffeine (Migration 064) | `CatalogDrinks.all` (coffee, tea, colas, energy drinks) carries no caffeine; a custom drink cannot record any |
| 4 | Caffeine as a variable: mg and time | §6.2 | **Built 2026-10-16**; was Core only | `CaffeineLogStore` with `CaffeineLogStoreTests`; unreachable from the app |
| 5 | Caffeine judged against intended sleep, not the clock (8 AM is late for a 10 AM sleeper) | §6.2, §6.11 | **Built 2026-10-16**; was Core only | `ShiftScheduleStore.intendedSleepTimestamp` and `CaffeineLogStore`'s context, `ShiftAwareCaffeineContextTests` (night shift → `very_late`); unreachable, same cause as 4 |
| 6 | Water written to Apple Health; a failed write stays and is retried | §5.5, A6 | **Built** | `HydrationSyncTests.testWritebackPushesUnsyncedManualEntriesOnly`, `testAFailedPushLeavesTheRowPendingAndItIsRetriedNext`. Device: UNRUN (`docs/device-checklist.md`, check 1) |
| 7 | A clear status while an entry is not yet in Apple Health | §5.5, A6 | **Built 2026-10-16**, device check pending; was Not shown | "Not yet in Apple Health" on a manual entry not yet written, once Almanac may write water (`HydrationDashboardView`). Found with it: HealthKit was hooked up only by tapping Connect, so nothing synced after a relaunch; now reconnected at launch when write permission exists (`AlmanacApp`). Simulator: UI test asserts the line is absent without permission. Device: `docs/device-checklist.md` check 1, step 5 |
| 8 | Water reminders: toggleable, time-adjustable | §6.14 | **Built** | Settings → Reminders (interval, from, until); `NotificationSettingsUITests` (CI) |
| 9 | No water reminder during a dry fast or post-shift sleep | §6.13, §6.14 | **Built** | `NotificationSuppressionMatrix` and its tests |
| 10 | Ramadan: hydration target compressed into the night, shift-aware cadence | §6.13 | **Not built** | The target is unchanged on fast days; water reminders run wake → sleep − 2 h at a fixed interval (`NotificationTriggerTimeComputer.waterReminderTimes`) |
| 11 | Drinks between Maghrib and Fajr belong to the night window | §6.13 | **Built** | `FastingAwareHydrationLogTests` |
| 12 | Hydration ring fills when the target is hit | §6.16 | **Built** | `ActivityRingCalendarTests` |
| 13 | Dark urine despite the target → offer to raise it; not during a dry fast | §6.3, A1 | **Built** | `UrineColourHydrationFeedbackTests` |
| 14 | One-tap water logging as an App Intent | §6.21 | **Built, not driven** | `LogWaterIntent` in `Native/AlmanacWidgets/WidgetIntents.swift`; no test runs it |
| 15 | A contextual pre-lunch water suggestion | A1 | **Core** | `contextual_hydration` in `NotificationPlannerTests`, `NotificationTriggerAssemblerTests`; delivery is device only |
| 16 | Permissions asked when a feature is first used, not all at once | §5.5, A5 | **Differs** | Settings → "Connect to Health" asks for every type in one sheet (`HealthModel.connect`: "One sheet, one answer"). Asked on a tap, not at launch, but not per feature |
| 17 | Missing HRV shown as unavailable, never zero; readiness lists missing inputs | A5 | **Built** | `ReadinessEngineTests.testMissingHRVRedistributesRatherThanScoringZero`, `testBaselineWithoutAMetricMakesThatInputMissing`; `ReadinessBaselineServiceTests` "A missing baseline is reported as missing"; `ProblemChannelUITests` (CI) |

## Gaps, and what closing each needs

| Gap | Rows | Needs a decision? | To close |
|---|---|---|---|
| **Caffeine is never recorded** | 2, 4, 5 | Only the figures: mg per catalog drink. The catalog's other figures are already "typical values, not measured"; caffeine would follow that rule, logged unconfirmed | Add caffeine to `Drink` and the catalog; `logDrink` writes `caffeine_log` with the day's intended sleep, in one transaction with the hydration row; deleting or resizing the drink follows (needs an additive migration linking the two rows); core tests |
| Caffeine presets editable; a custom drink's caffeine | 3 | No | A caffeine field on the custom-drink form and its table (migration); per-drink overrides of catalog presets |
| ~~No "not yet in Apple Health" status~~ | 7 | Built 2026-10-16: only once Health may be written (`CONTEXT.md`) | Device check |
| Ramadan night hydration | 10 | **Yes**: the night target and the reminder cadence across Maghrib → Fajr, and how a night shift changes it | Planner and target rules, core tests |
| Health permissions per feature | 16 | **Yes**: the single sheet was a deliberate choice | Ask per domain when its screen first opens |
| App Intent not driven | 14 | No | A test that runs `LogWaterIntent` against a database |

## Closed on 2026-10-16: caffeine from logged drinks

Rows 2, 4 and 5. `Drink.caffeineMilligrams` and figures for 15 catalog drinks;
`HydrationLoggingService.logDrink` writes the hydration row and its
`caffeine_log` row in one transaction, judged against the day's intended sleep
from the shift schedule; Migration 063 links the two, so resizing, moving or
deleting the drink carries its caffeine. Tests: `DrinkCaffeineTests` (9).
Choices: `CONTEXT.md`, "Caffeine from logged drinks". The logging screen states
a drink's caffeine for the amount chosen (UI test
`testTheDrinkLoggerStatesCaffeineForTheAmountChosen`), and a custom drink can
carry caffeine (Migration 064). A catalog drink's caffeine can be set to the
person's own figure and put back (Migration 065; UI test
`testACatalogDrinksCaffeineCanBeChangedAndPutBack`). `DrinkCaffeineTests`: 13.

## Score

Phase 3 stays at **90** until a gap is closed and tested. Closing the caffeine
gap with its tests is the change the handoff's +2 points for this phase asked for.
