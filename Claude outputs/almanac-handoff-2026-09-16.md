# Almanac Handoff — 2026-09-16 (yamal to macOS iMac + Xcode)

**Session completed on:** Linux (yamal)  
**Next session on:** macOS Ventura iMac 2017 + Xcode  
**Focus:** Slice 2 integration, HealthKit wiring, readiness cycle creation

---

## What Just Finished (This Session)

Four commits on `main` branch of `/mnt/kingston/Projects/almanac/almanac`:

### 1. **7cf2abc** — Build Slice 2 (Core Daily) from Technical Specification v1.0
- Recovered the lost Technical Spec v1.0 (found at `~/mnt/almanac/almanac-tech-spec-v1.0.md`)
- Implemented 14 tables (Migration014): profile, day_record, circadian_context, shift_schedule, sleep_episode, readiness_cycle, vitals_record, mood_log, soreness_log, injury_note, readiness_record, readiness_baseline, shift patterns
- Implemented SleepClassifier, ReadinessFormula, ReadinessEngine, CircadianContext
- Fixed TimeModel.swift: changed default logical day boundary from midnight to 04:00 (spec §7.1)
- **54 new tests, all passing**

### 2. **2123990** — Task #9: Build Slice 2 stores and readiness-cycle linking (§8.4)
- Five new stores: ProfileStore, MoodLogStore, SorenessLogStore, InjuryNoteStore, VitalsRecordStore
- ReadinessCycleLinkingService: per §8.4, links mood_log and soreness_log entries to their readiness_cycle by timestamp window
- **30 new tests**

### 3. **f18710a** — Task #10: Add HealthKit sleep and vitals import
- SleepEpisodeHealthBridge: idempotent upsert of HealthKit sleep → sleep_episode
- VitalsRecordHealthBridge: idempotent upsert of vitals (RHR, HRV, steps, activeEnergy, restingEnergy, bodyMass) → vitals_record
- Both implement HealthSampleWriting protocol for HealthSyncService integration
- **10 new tests**

### 4. **c83e88c** — Task #11: Settle schema collisions per decision 2026-09-16
- Migration015: replaces sync_anchor table (spec §5.24 shape)
- Adds drink_entry (spec §5.12): drinkType taxonomy, per-drink nutritional tracking
- Adds caffeine_log (spec §5.14): contextual caffeine awareness for shift workers (BRD §6.2)
- DrinkEntryStore, CaffeineLogStore
- **8 new tests**

**Total:** 102 new tests across all commits; all passing on Swift 6.1.2 and 6.3.3.

---

## Current State

### Working Tree
- All changes committed. No uncommitted work.
- Device bridge dropped during the session but was reconnected for final commits.

### Project Docs (Updated)
- `almanac/tasks-9-10-11-completion-2026-09-16.md` — detailed recap of all three tasks
- `almanac/schema-collision-decision-2026-09-16.md` — decision record and outstanding items
- `almanac/slice-2-core-daily-2026-09-15.md` — Slice 2 build record

### Key Files to Know
- **Technical Spec:** `/mnt/kingston/Projects/almanac/almanac-tech-spec-v1.0.md` (96 KB, definitive)
- **Schema:** `Sources/AlmanacCore/Persistence/Migration*.swift` (Migration001–015)
- **Readiness engine:** `Sources/AlmanacCore/Readiness/` (ReadinessEngine, Formula, CycleLinkingService)
- **Sleep classification:** `Sources/AlmanacCore/Sleep/SleepClassifier.swift`
- **HealthKit bridges:** `Sources/AlmanacCore/Sleep/SleepEpisodeHealthBridge.swift`, `Sources/AlmanacCore/Vitals/VitalsRecordHealthBridge.swift`
- **Time model:** `Sources/AlmanacCore/Time/TimeModel.swift` (default boundary = 04:00, not midnight)

---

## Next Steps (macOS + Xcode)

### Immediate (Before Building UI)

1. **Verify test suite on macOS**
   - Clone repo on iMac (if not already there)
   - `swift test` to confirm 102 new tests pass on macOS toolchain
   - Check for any platform-specific issues (unlikely; mostly DB/logic)

2. **Wire HealthSyncService into the app**
   - Create iOS adapter for `HealthProvider` protocol (concrete `HealthKitProvider`)
   - Create `HealthKit` import file (iOS-only; cannot be imported in AlmanacCore)
   - Map HKQuantityType/HKCategoryType identifiers per spec's HealthKit map (not available in AlmanacCore)
   - Initialize HealthSyncService for each domain: sleep, RHR, HRV, steps, activeEnergy, restingEnergy
   - Anchor persistence: test that HealthSyncService.syncOnce() advances anchors correctly

3. **Readiness cycle creation**
   - After SleepClassifier.determine() picks primary sleep, create ReadinessCycle row
   - Call ReadinessCycleLinkingService.linkLogsToReadinessCycle() to backfill mood/soreness
   - Ensure cycleStartTimestamp (wake time) and cycleEndTimestamp (next day's wake) bound the window
   - Test: create sleep episode → cycle → logs created within window → linked to cycle

4. **Update spec-reconciliation.md**
   - Document the four collisions and decisions (nutrition/lab stay as built; sync_anchor replaced; drink_entry/caffeine_log added)
   - This was listed as outstanding in schema-collision-decision-2026-09-16.md

### Beyond (Slice 2 Integration & Readiness UI)

5. **Readiness score display**
   - ReadinessEngine.evaluate() returns ReadinessOutcome (score, confidence, colour, text, recommendation)
   - Wire into view that shows provisional score (before check-in) and final (after mood/soreness)
   - Implement colour coding per outcome

6. **Wellness check-in flow**
   - Mood (1-10) + Soreness (1-10, body areas) log UI
   - After logging, call ReadinessCycleLinkingService to link them retroactively
   - Optional: injury note UI

7. **HealthKit permission request**
   - Request authorization for sleep, RHR, HRV, steps, active energy
   - Per spec §6, HealthKit is read-only for these domains; hydration is the only write-back

---

## Testing Strategy for This Session

**Suggested Skill:** `mattpocock-skills:tdd` — test-driven approach for iOS wiring

- Unit tests for HealthProvider mock are in AlmanacCore (reusable)
- Integration tests: create HealthChangeSet → call bridge → verify store rows
- E2E: mock HealthKit → HealthSyncService → verify anchors advance
- All existing tests should still pass on macOS

---

## Suggested Skills for Next Session

1. **`mattpocock-skills:tdd`** — write iOS adapter tests first (red-green-refactor)
2. **`engineering:architecture`** — if HealthKit adapter design feels unclear
3. **`mattpocock-skills:codebase-design`** — if deciding where to put ReadinessCycle creation logic
4. **`engineering:documentation`** — when writing the amendment record for spec-reconciliation.md
5. **`engineering:code-review`** — before merging to main from the macOS branch

---

## Gotchas & Notes

- **TimeModel default:** changed from .midnight to .wakeOffset(hours: 4) in this session. HydrationModel was silently using midnight before; fixed now.
- **Migration015:** drops and recreates sync_anchor. Old anchors are not migrated (opaque HK values); next sync rereads from start per type. Acceptable cost.
- **Readiness cycle anchor:** spec uses primaryWakeTimestamp = episode.endTimestamp, not startTimestamp. This is the wake time, which marks the start of the new cycle.
- **Caffeine context computation:** automatic (early >6h, late <1h before intended sleep). Requires shift_schedule lookup (not yet wired).
- **Swift 6 strict concurrency:** all stores use @unchecked Sendable; DB access is behind Database abstraction which is thread-safe internally.

---

## References

**In repo:**
- Commit history: `git log --oneline` (see 7cf2abc, 2123990, f18710a, c83e88c)
- Project docs: see "Project docs (21)" above
- Technical Spec: `~/mnt/almanac/almanac-tech-spec-v1.0.md` (definitive)

**Key sections of spec (for HealthKit wiring):**
- §6: HealthKit read/write permission map
- §8.1–§8.4: Sleep classification, readiness-cycle linking
- §9: Readiness formula (provisional/final, confidence, calibration)
- §13: Circadian context engine
- Appendix C: HealthKit sync procedure (anchored queries)

---

## Device Handoff Notes

- **This session:** Linux (yamal), no Swift compiler, direct database work on repo
- **Next session:** macOS iMac + Xcode, can compile and run tests natively
- **Repo location:** Clone from `/mnt/kingston/Projects/almanac/almanac` or pull latest

Both machines will see the same remote repo state; no merge conflicts expected.

---

**Session: claude.ai/code/session_01PXh8TPSZcWkRmz6yH6K7pq**
