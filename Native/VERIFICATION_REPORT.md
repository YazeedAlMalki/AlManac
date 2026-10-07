# Slice 2 (Core Daily) — Apple SDK verification report

**Status: not run.** This report was written in a headless Linux session with
no macOS, Xcode or iOS Simulator available — there is no `swift`/`swiftc`
toolchain and no Docker daemon on this machine either, so nothing below was
compiled or executed here, Linux-only `swift test` included. Every section is
a template: run the commands, work the checklist on a Mac, and fill in the
results in place of the `TODO`s.

## What changed

1. **HealthKit sleep/vitals bridges** — already wired on `master` before this
   session (`HealthModel.swift`, commit history up to `6d90c75`): `HealthModel
   .syncNow()` runs `HealthSyncService` per domain, mapping `.sleep` to
   `SleepEpisodeHealthBridge` and `.heartRate`/`.hrv` (among others) to
   `VitalsRecordHealthBridge`. No change was needed here — see the updated
   `Native/README.md` "Authored" section for the corrected description (the
   old text claimed the HealthKit sheet only covered water; it has covered
   every readable domain since `HealthModel` was added).
2. **Readiness-cycle creation (§8.4)** — this was the actual gap.
   `ReadinessCyclePrimaryLinkingService` existed, fully built and tested in
   isolation, but nothing in the app or in any HealthKit bridge ever called
   it — `ReadinessModel`'s own doc comment said as much ("`ensureCycle` makes
   a bare cycle... if the primary-sleep-linking task hasn't created one
   yet"). `SleepEpisodeHealthBridge.reclassify()` now calls
   `primaryLinking.linkPrimaryEpisode(episodeId:)` for every episode it
   writes with `type == .primary`, inside the same sync transaction
   `HealthSyncService.syncOnce()` already opens (nested via SQLite
   savepoints — see `Database.transaction`). New coverage:
   `SleepEpisodeHealthBridgeTests.testPrimaryNightCreatesReadinessCycleAndLinksSameDayLogs`.

Diff is otherwise limited to those two files plus `Native/README.md`'s
checklist (items 10/11 corrected, 14/15 added).

## Build

Run from the repository root on a Mac with Xcode installed:

```sh
xcodebuild -project Native/Almanac.xcodeproj -scheme Almanac \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

On an Intel Mac, add `ONLY_ACTIVE_ARCH=YES` (see the README's "Verification
boundary" section for why).

| Check | Result |
|---|---|
| `xcodebuild` exits 0 | TODO |
| App launches in Simulator without crashing | TODO |
| Database survives relaunch (`almanac.sqlite`, migrations recorded) | TODO |

## Linux-provable coverage (run before the Xcode pass)

This machine could not run it, but it should be run first, on any machine
with the Swift toolchain, since it is faster to iterate on than the
Simulator:

```sh
swift test --filter SleepEpisodeHealthBridgeTests
swift test --filter ReadinessCyclePrimaryLinkingServiceTests
```

| Check | Result |
|---|---|
| `SleepEpisodeHealthBridgeTests` passes, including `testPrimaryNightCreatesReadinessCycleAndLinksSameDayLogs` | TODO |
| Full suite (`swift test`) still passes — no regression in the ~141 existing tests | TODO |

## Simulator acceptance checklist

Full checklist is `Native/README.md`'s "Interactive acceptance checks —
outstanding". This task's acceptance criteria are items **10** (corrected
wording — re-verify the authorization sheet lists every domain, not water
alone), **14** and **15** (new). Record each as pass/fail with a note on
what was observed, not just a checkmark — a failing step here is the reason
to come back to the code, not to relax the check.

| # | Check | Result | Notes |
|---|---|---|---|
| 10 | HealthKit connect sheet lists every readable domain + water; HealthKit-sourced water delete doesn't resurrect | TODO | |
| 14 | A Health-app sleep entry (23:00–07:00) reaches Almanac after sync: Today's sleep duration updates, readiness score recomputes | TODO | |
| 15 | RHR/HRV logged in Health reach the readiness score's inputs; completing the mood/soreness check-in moves the score from provisional to final on the **same** cycle the sleep sync created | TODO | |

The last column of item 15 is the one most likely to catch a real bug: if
the check-in's cycle id and the sleep-sync's cycle id differ, something in
`ReadinessCyclePrimaryLinkingService`'s anchor-date computation or
`ReadinessCycleStore.ensureCycle`'s bare-cycle fallback disagrees with this
change, and that is worth filing rather than working around.

## Known ceiling, not a defect

`SleepEpisodeHealthBridge.swift` carries a `ponytail:` comment on this: a
first HealthKit connect re-classifies and now also re-links every historical
night (`ReadinessCyclePrimaryLinkingService.link` scans the whole
`readiness_cycle` table per call), which is O(days²) across roughly 1,000
days of history. If the Simulator's first Connect-and-sync with a
long-history test account is noticeably slow, that is the place to look —
narrowing it (skip the call when a day's primary episode id didn't change)
is the documented upgrade path, not a rewrite.

## Sign-off

- [ ] Build succeeds
- [ ] Linux test suite passes (run wherever `swift` is available)
- [ ] Checklist items 10, 14, 15 pass in Simulator
- [ ] Any failures above are filed as follow-up issues, not silently patched over
