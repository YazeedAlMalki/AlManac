# Handoff — Almanac calorie database, build phase starts next session

**Context:** Almanac is a body-monitor app (sleep/food/energy/activity). Food-composition data collection is done, processing/schema design is done, and the shared app architecture is done. None of that is repeated here — read the referenced docs directly rather than asking Yazeed to re-explain them.

**What this session is for:** stop planning, start building. Yazeed wants the calorie database actually under construction this session, using the already-collected sources (USDA CC0, CIQUAL CC BY, CoFID OGL, AFCD CC BY — ~2.11M foods, licence Groups A/B, already cleared to ship) as the benchmark/foundation. A prior planning pass (`almanac/calorie-database-build-prep-2026-09-13.md`) listed six open decisions before building — Yazeed pushed back on that: don't reopen them, proceed under defaults, get to building.

## Proceed under these defaults — do not re-ask

| Decision | Default to build under |
|---|---|
| Licence group for Almanac-native rows | New tag (e.g. `N`), always ships — Almanac's own IP. Extend the bundle assertion to `group in ('A','B','N')`. |
| Calorie calculation method | General Atwater factors (4/4/9/7 kcal/g protein/carb/fat/alcohol). Per-food specific factors are a v2 refinement. |
| Canonical nutrient set for this phase | Just what calorie calculation needs: energy, protein, carbohydrate, fat, fibre, alcohol. Not the full USDA 477 — separable later. |
| Branded Foods (95% of USDA's rows) | Hold out of this phase. Start from Foundation Foods + CIQUAL + CoFID + AFCD (~8k foods, analytically clean), not the 2M-row branded set. |
| SFDA-as-benchmark question | Not legally cleared. Treat as informal internal reference only — never store its values verbatim, always independently source/verify quantities in any native entry. Still worth Yazeed getting his law-firm connection to confirm this if it comes up again. |

Only genuinely blocked item: **actual Saudi/Gulf dish data to populate Almanac-native entries.** That has to come from Yazeed (recipes, personal knowledge, or a chosen reference). The schema and pipeline work below doesn't need it to start.

## Build order for this session

(Already decided — see `almanac/processing-design-v0.1.md` §8 for full rationale, don't re-derive it.)

1. Nutrient dictionary + qualifier enum, as data not code — `measured / trace / not_analysed / below_loq / borrowed / calculated_recipe / calculated_factor / zero_reported`.
2. Extract USDA (Foundation Foods first, not Branded) — lowest risk, already relational, CC0.
3. Canonicalise USDA into the Almanac schema, `usda:` namespace, source values preserved verbatim.
4. Build the bundle-step licence assertion (`group in ('A','B','N')` or fail the build) — before a second source exists, per the existing design rationale.
5. Extract + canonicalise CIQUAL, CoFID, AFCD.
6. Wire into AlmanacCore as a new module — migration `007+`, tables prefixed `nutrition_*` (see `almanac/health-data-foundation-v0.2.md` §12 — no generic shared table names, follow the existing `lab_*` per-module-table pattern).

Stack: Swift + SQLite for the AlmanacCore module (on `yamal`, `swift build && swift test`, 79 tests passing as of the last status doc — see `almanac/implementation-status-slice-2026-09-08.md` for toolchain gotchas). ETL/canonicalisation against the raw CSV/JSON files in `/home/yamal/ALManac-food-data` is more naturally Python or shell.

## Suggested skills

- `mattpocock-skills:tdd` — build the nutrition module red-green-refactor, matching how Laboratory and bodyMass were built.
- `mattpocock-skills:codebase-design` — keep the module's interface a seam, not an ORM, consistent with the rest of AlmanacCore.
- `data:sql-queries` / `data:explore-data` — extract/canonicalise scripts against the raw source files.
- `data:validate-data` — QA pass on canonicalised nutrient values before wiring them in. Known bug class in this project: CoFID's `Tr`/`N` tokens must never be coerced to 0 (see `almanac/processing-design-v0.1.md` §2).
- `mattpocock-skills:domain-modeling` — only if a genuinely new concept doesn't fit the existing model. Don't use it to reopen settled decisions.

## Don't do

- Don't re-litigate the five decisions above.
- Don't open with a battery of clarifying questions — build against the defaults, flag issues as they come up.
- Don't ship or use SFDA, NEVO, TBCA, IFCT, FAO/INFOODS, Bahrain, or Tunisia data directly — all Group D, quarantined.

## References (read these, don't ask for a re-summary)

- `almanac/nutrition-data-collection-report-2026-09-01.md` — what was collected, licence groups
- `almanac/food-lake-addendum-2026-09-12.md` — Oman FCT added, portal re-check
- `almanac/processing-design-v0.1.md` — full pipeline design, value model, build order
- `almanac/health-data-foundation-v0.2.md` — shared architecture (events/measurements/plans, identity, time)
- `almanac/implementation-status-slice-2026-09-08.md` — current code state, 79 tests passing, `yamal` toolchain notes
- `almanac/calorie-database-build-prep-2026-09-13.md` — the six-decision planning doc this handoff supersedes for session-start purposes

No secrets, credentials, or personal data in scope for this handoff.
