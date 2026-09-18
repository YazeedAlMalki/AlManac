> **STATUS UPDATE (2026-09-19): This ticket's core work was already closed the day before
> this doc was generated; the one real gap it left has now been built too.**
>
> Like Ticket C, this handoff was regenerated from the earlier
> `almanac-handoff-2026-09-18.md` planning doc without checking current repo state. The
> library research, licence check, port, and accuracy verification below were already done
> on 2026-09-17 (submodule commits `0b39916`, `f897d3e`, `b941ab4`): `batoulapps/adhan-swift`
> (MIT) vendored at `Sources/Adhan/` (see `Sources/Adhan/VENDORED.md`), wrapped by
> `Sources/AlmanacCore/Prayer/AdhanCalculator.swift`, verified for Riyadh against
> `api.aladhan.com`'s Umm al-Qura output (5 tests in
> `Tests/AlmanacCoreTests/AdhanCalculatorTests.swift`). Work went beyond this ticket's scope
> too: `PrayerSettingsStore`, a 30-day `PrayerTimeCacheStore`, and `PrayerTimeEngine`'s >50 km
> travel invalidation (migration 024) were also already built. Full record:
> `almanac/docs/features/fasting.md` §3 and §5–6.
>
> The one genuine gap — §12.2's bundled 200+-city manual-fallback list, for a user without a
> Core Location fix — was built in this session (2026-09-19):
> `Sources/AlmanacCore/Prayer/Resources/manual-cities.json` (230 cities) plus
> `ManualCityCatalog` (`Sources/AlmanacCore/Prayer/ManualCityCatalog.swift`) for
> `search(_:)`/`city(named:country:)` lookups, 12 tests
> (`Tests/AlmanacCoreTests/ManualCityCatalogTests.swift`). It resolves a city name to
> coordinates only; a caller still applies the choice via
> `PrayerSettingsStore.updateLocation(..., manualCityOverride: true)` itself. All 347 tests
> in the package pass (verified via the Docker Swift 6.0 toolchain).
>
> No further action needed on Ticket E. The rest of this file is kept as-is for reference —
> it does not reflect the actual already-shipped state.

---

# Handoff: Ticket E — Prayer Times (Adhan) Research & Port (2026-09-18)

**Status:** Ready to start. No code blockers.

**Next session:** Research library, evaluate fitness, port to Swift, verify accuracy (4–6 hours).

---

## What Ticket E is

The fasting/prayer features (Slice 6) need prayer times for Riyadh (Fajr, Dhuhr, Asr, Maghrib, Isha). The Adhan library is the standard open-source prayer-time calculator. This ticket finds it, evaluates it for licence/compatibility, ports it to Swift (or wraps an existing Swift binding), and verifies accuracy for Riyadh coordinates.

Output: A working Swift library that returns prayer times ±2 min accuracy for Riyadh.

---

## Context

**Why it matters:** Slice 6 (Fasting & Prayer) is sequential — Ticket E must finish before Ticket F (Slice 6 stores/schema) can start. Prayer times feed into the dashboard (showing next prayer time). Fasting state might suppress certain reminders during prayer.

**Why research first:** Adhan exists in JavaScript, Python, and Java. Swift binding may or may not exist. Licence terms matter (GPL/AGPL blocks shipping). Performance on iOS matters (daily recalculation vs. pre-computed). This is a 4–6 hour spike, not a coding task.

---

## The research task

### Step 1: Locate Adhan

**Primary sources:**
- GitHub: `batoulapps/Adhan` (the official repo, JavaScript)
- NPM: `adhan` (JavaScript package)
- PyPI: `adhan` (Python package)
- Maven Central: `com.batoulapps:Adhan` (Java package)

**Questions to answer:**
- Does a Swift binding or wrapper exist already?
- If yes: is it actively maintained, tested, and licence-clear?
- If no: is the JavaScript/Python source clear enough to port manually?

**Where to search:**
- GitHub: search `adhan swift`, `prayer times ios`, `islami ios`
- CocoaPods/SPM: search `adhan`
- Stack Overflow: search `adhan swift`

### Step 2: Evaluate the library

Criteria:

| Criterion | Check | Notes |
|---|---|---|
| **Licence** | Must not be GPL/AGPL | Check LICENSE file; email maintainer if unclear |
| **Accuracy** | ±2 min for Riyadh | Use official prayer time tables for Riyadh as ground truth |
| **Calculation method** | Modern algorithms (not hardcoded tables) | Adhan uses ISNA/MWL/UOIF/Karachi/Jafari methods; pick one |
| **Maintenance** | Recent commits or stable release | Dead repos are risky |
| **Test coverage** | Has test cases | Verify against known prayer times |
| **Swift compatibility** | Compiles on iOS 17+ | If it's a wrapper, check minimum deployment target |

### Step 3: Find or create a Swift binding

**Option A: Use existing Swift wrapper (if maintained)**

Example (hypothetical):
```
repo: `mutualmobile/adhan-swift`
licence: MIT ✅
tests: 50+ ✅
maintained: 2024 ✅
→ Use this
```

**Option B: Wrap the JavaScript version with JavaScriptCore**

If no native Swift binding exists, wrap `adhan.js`:

```swift
import JavaScriptCore

class AdhanCalculator {
    let context = JSContext()!
    
    init() {
        let adhanJS = loadAdhanJS()  // Load adhan.js from bundle
        context.evaluateScript(adhanJS)
    }
    
    func prayerTimes(for date: Date, latitude: Double, longitude: Double) -> PrayerTimes {
        let jsParams = "new Date(\(date.timeIntervalSince1970 * 1000)), \(latitude), \(longitude)"
        let result = context.evaluateScript("calculatePrayers(\(jsParams))")
        
        return PrayerTimes(
            fajr: result["fajr"],
            dhuhr: result["dhuhr"],
            asr: result["asr"],
            maghrib: result["maghrib"],
            isha: result["isha"]
        )
    }
}
```

**Option C: Manual port from JavaScript**

If the library is small (~500 lines) and licence is clear, port the core math to Swift.

Adhan's core algorithm:
1. Julian day number from Gregorian date
2. Mean solar time for each prayer
3. Adjustment for latitude/longitude/method
4. Return as local time

Pseudo-code:
```swift
func julianDay(from date: Date) -> Double {
    let cal = Calendar(identifier: .gregorian)
    let components = cal.dateComponents([.year, .month, .day], from: date)
    // JDN = (D + 32044) + (1461 * (Y + 4800 + (M − 14) / 12)) / 4 + (367 * (M − 2 − 12 * ((M − 14) / 12))) / 12 − (3 * ((Y + 4900 + (M − 14) / 12) / 100)) / 4
    return Double(/* JDN formula */)
}

func prayerTimesForDate(_ date: Date, latitude: Double, longitude: Double) -> PrayerTimes {
    let jd = julianDay(from: date)
    let sunCoordinates = calculateSunCoordinates(jd: jd)
    
    var times: [String: Double] = [:]
    
    times["fajr"] = calculateTime(jd: jd, angle: 18, lat: latitude, lng: longitude, isFajr: true)
    times["sunrise"] = calculateTime(jd: jd, angle: 0.833, lat: latitude, lng: longitude)
    times["dhuhr"] = calculateTime(jd: jd, angle: -0.833, lat: latitude, lng: longitude)
    times["asr"] = calculateAsrTime(jd: jd, lat: latitude, lng: longitude)
    times["maghrib"] = calculateTime(jd: jd, angle: -0.833, lat: latitude, lng: longitude)
    times["isha"] = calculateTime(jd: jd, angle: 18, lat: latitude, lng: longitude)
    
    return PrayerTimes(times)
}
```

### Step 4: Verify accuracy for Riyadh

Riyadh coordinates: 24.7136° N, 46.6753° E

Ground truth (official Saudi prayer times, e.g., from Umm Al-Qura calendar):

```
Date: 2026-09-19 (Example)
Fajr:     05:14
Dhuhr:    12:14
Asr:      15:44
Maghrib:  18:15
Isha:     19:45
```

Test against library:

```swift
func testRiyadhPrayerTimesAccuracy() {
    let riyadh = Coordinates(latitude: 24.7136, longitude: 46.6753)
    let date = Date(year: 2026, month: 9, day: 19)
    
    let times = adhan.prayerTimes(for: date, coordinates: riyadh)
    
    XCTAssertEqual(times.fajr, Date(hour: 5, minute: 14), accuracy: 2.minutes)
    XCTAssertEqual(times.dhuhr, Date(hour: 12, minute: 14), accuracy: 2.minutes)
    XCTAssertEqual(times.asr, Date(hour: 15, minute: 44), accuracy: 2.minutes)
    XCTAssertEqual(times.maghrib, Date(hour: 18, minute: 15), accuracy: 2.minutes)
    XCTAssertEqual(times.isha, Date(hour: 19, minute: 45), accuracy: 2.minutes)
}
```

Where to get ground truth:
- Umm Al-Qura calendar (Saudi official): https://www.mawqiit.net/
- Islamic Society of North America (ISNA): https://www.isna.net/prayer-times/
- Multiple dates (50+) to verify consistency.

### Step 5: Decide on port vs. wrapper

**Choose wrapper (JavaScriptCore) if:**
- JavaScript binding is well-tested and actively maintained
- Performance is acceptable (pre-compute daily if needed)
- Licence is clear

**Choose manual port if:**
- JavaScript binding doesn't exist or is unmaintained
- Performance requirements demand native code
- Licence is GPL/AGPL (can't use)
- Codebase is small (<1000 lines)

**Avoid multiple ports:** Once chosen, commit to it for Slice 6.

### Step 6: Document integration point

For Ticket F (Slice 6 stores), document how to call it:

```swift
// In PrayerTimeStore or similar
let calculator = AdhanCalculator()
let riyadhCoordinates = Coordinates(latitude: 24.7136, longitude: 46.6753)
let prayerTimes = calculator.prayerTimes(for: Date(), coordinates: riyadhCoordinates)

// Returns
struct PrayerTimes {
    let fajr: Date      // Pre-dawn
    let sunrise: Date   // Sunrise
    let dhuhr: Date     // Noon
    let asr: Date       // Afternoon
    let maghrib: Date   // Sunset
    let isha: Date      // Night
}
```

---

## Acceptance criteria

- [ ] Adhan library identified and evaluated (licence, maintenance, accuracy)
- [ ] Decision made: use existing Swift binding, wrap JavaScript, or manual port
- [ ] Swift integration (binding, wrapper, or port) compiles on iOS 17+
- [ ] 50+ test dates verified against ground truth (±2 min accuracy)
- [ ] Accuracy ≥99% across all five prayer times
- [ ] Integration point documented for Ticket F
- [ ] No uncommitted changes to codebase (this is research + decision, not shipping code yet)

---

## Blockers

**None.** This is pure research; no code dependencies.

**Potential slowdowns:**
- If JavaScript binding is unmaintained, porting might add 2–3 hours
- If licence is unclear, email exchange with maintainer might add 1–2 hours
- If ground-truth data is hard to find, verification might add 1 hour

Mitigate by starting with existing Swift bindings first; if none exist after 1 hour, pivot to JavaScriptCore wrapper.

---

## Estimated time breakdown

| Task | Est. | Notes |
|---|---|---|
| Locate library + evaluate licence (Step 1–2) | 1–1.5 hrs | GitHub search + README/LICENSE review |
| Find or create Swift binding (Step 3) | 1–2 hrs | If existing, 30 min; if wrapper, 1.5 hrs; if port, 2+ hrs |
| Verify accuracy for Riyadh (Step 4) | 1–1.5 hrs | Gather ground truth + write tests + run verification |
| Decide on approach (Step 5) | 0.5 hr | Trade-offs doc |
| Document integration point (Step 6) | 0.5 hr | Pseudocode for Ticket F |
| **Total** | **4–6 hrs** | |

---

## Files to create/modify

- Research doc: `docs/adhan-research-2026-09-18.md` (new)
- Integration guide: `docs/prayer-time-integration.md` (new)
- Optionally: Swift binding code (if porting/wrapping)
  - `Sources/Adhan/AdhanCalculator.swift` (new or copy)
  - `Tests/AdhanAccuracyTests.swift` (new)

---

## Skills for this work

- **`mattpocock-skills:research`** — investigate the Adhan ecosystem, compare options, document findings, make a binding/port/wrapper decision
- **`engineering:architecture`** — if choosing between wrapper vs. port, weigh trade-offs (performance, maintainability, licence risk)
- **`mattpocock-skills:implement`** — if porting or wrapping, execute Steps 3–4 (integration + verification)

**Recommendation:** `mattpocock-skills:research` (2–3 hrs) to evaluate all options, then `mattpocock-skills:implement` (1–3 hrs) to build/verify the chosen approach.

---

## Definition of done

- Adhan library identified and licence confirmed
- Swift integration (binding/wrapper/port) compiles cleanly
- 50+ test dates pass (accuracy ≥99%)
- Integration documented for Ticket F
- No breaking changes to existing codebase
- Ready for Ticket F to use immediately

---

## Open questions for Yazeed

1. **Licence sensitivity:** Is GPL/AGPL a hard blocker, or acceptable with proper attribution?
2. **Performance:** Is pre-computing prayer times daily acceptable, or must it be real-time?
3. **Method preference:** ISNA, MWL, UOIF, Karachi, or Jafari? (Affects angle calculations; different methods give ±3–5 min variation)
4. **Additional features:** Do you need prayer-time notifications, or just display?
5. **Customization scope:** Should users be able to adjust by manual offset (e.g., "my mosque is 5 min slower")?

