# Handoff — Almanac Nutrition Database, collection phase

**Date:** 2026-09-01 · **Status:** ~75% complete · **Phase:** collection only, no processing

---

## Read these first (do not duplicate their content)

| What | Where |
|---|---|
| Full collection report — counts, sizes, licence groups, findings | Project doc `almanac/nutrition-data-collection-report-2026-09-01.md`, also at `/home/yamal/ALManac-food-data/COLLECTION_REPORT.md` |
| Layout, folder rules, usage, verification commands | `/home/yamal/ALManac-food-data/README.md` |
| Per-source narrative and collection status | `SOURCES.md` |
| Rights analysis, four licence groups, attribution register, open questions | `LICENSES.md` |
| Machine-readable registry, 21 rows × 31 columns | `DATASETS.csv` |
| Per-source provenance (Phase 10) | `metadata/{source}/SOURCE.md` |
| FAO catalogue + per-dataset relevance verdicts | `metadata/fao/FAO_INFOODS_INVENTORY.md` |
| Gulf/Arab survey, portals, query terms, triage rule | `metadata/GULF_ARAB_OPEN_DATA_INVENTORY.md` |
| Standing user context and constraints | memory `/areas/almanac.md` |

Everything factual lives in those. This document carries only what is **not**
written down anywhere else: session-earned operational knowledge, and the
ordered list of what remains.

---

## Session-earned operational knowledge

These cost real time to discover. They are not in any artifact.

1. **The sandboxed shell on the device "yamal" has no network.** Every outbound
   request returns HTTP 000. The cloud container *does* have network. So:
   downloads either run in the cloud and get transferred, or the user runs the
   scripts in their own terminal.
2. **`device_bash` cannot delete files.** `rm` fails with `Operation not
   permitted`. `truncate -s 0` and `mv` both work. Plan cleanup around that;
   there is no delete-permission tool available in this setup.
3. **Background jobs do not survive between `device_bash` calls.** Each call is
   a fresh sandbox and `nohup`'d children are killed. Run work in the
   foreground inside the ~45 s limit. A full 3.8 GB SHA-256 sweep takes ~11 s,
   so it fits.
4. **Device transfer caps: 20 MB/file, 100 MB/call, 50 files/call.** The working
   pattern for a large payload: `tar czf` → `split -b 19000000` →
   `SendUserFile` (one call, all parts) → `device_commit_files` in ≤100 MB
   batches → `cat` parts → verify SHA-256 → `tar xzf` → `truncate -s 0` the
   scratch.
5. **Two upstream hosts are blocked from the cloud container**, though both work
   from a normal terminal: `ndownloader.figshare.com` (redirects to an S3
   endpoint on port 9000) and `fd.sfda.gov.sa` (geo-restricted).
6. **Derived files are generated, not hand-edited.** After any change:
   `export ALMANAC_ROOT=$PWD` then
   `python3 scripts/utils/build_datasets_csv.py` and
   `python3 scripts/utils/build_source_docs.py`.

---

## Hard rules (full statements in README.md / LICENSES.md)

- No processing yet — no merging, normalising, nutrient renaming, translation,
  unit conversion, deduplication, embeddings or inferred values. `processed/`
  stays empty.
- `raw/` is immutable, mode 0444. New release → new `raw/{source}/{release}/`.
  Never overwrite.
- Never infer legal permission. Unstated → `unclear`; `unclear` behaves as `no`.
- Do not move `FoodData Central United States/` — deliberate exception,
  registered at its real path, verified byte-identical to upstream.
- Do not scrape SFDA's web tool, TBCA, or NEVO's request form. Do not ingest
  `ifct2017.github.io` (third party, asserts proprietary rights).
- Open Food Facts is ODbL share-alike — confine to `raw/openfoodfacts/`, never
  merge into the Almanac core.

Verify before and after any change — must print `RESULT: PASS`:

```bash
cd /home/yamal/ALManac-food-data && export ALMANAC_ROOT=$PWD
bash scripts/verify/verify_raw_immutable.sh
```

---

## Remaining work, in order

### 1. SFDA enquiry — highest value, not technical
SFDA published no re-use terms at all. Ask for: a structured export of the Saudi
Food Composition Tables; API access to `fd.sfda.gov.sa`; written terms covering
commercial use, modification, redistribution and attribution. File any reply in
`licenses/sfda/`. **Until this lands, the Saudi core of Almanac cannot ship
commercially.**

### 2. Close licensing — 7 of 11 datasets are quarantined
- Read the licence page of each of the 5 FAO user-guide PDFs in
  `raw/fao/inventory-2026-09-01/`, plus the `Copyright` sheet inside
  `BioFoodComp4.0.xlsx`. Record the five rights answers per dataset in
  `DATASETS.csv`. Likely CC BY-NC-SA 3.0 IGO — the `NC` term would exclude all
  five from a commercial product.
- Complete the NEVO request — `raw/nevo/2025-9.0/ACCESS_INSTRUCTIONS.md`.
- Email FSANZ to confirm CC BY 4.0 covers the AFCD data files (asserted
  site-wide, not on the data page).
- Ask NIN/ICMR about IFCT licensing and a structured export.
- Request a TBCA export and written terms from FoRC/USP.

### 3. Two downloads that are ready (user's own terminal)
```bash
bash scripts/download/download_frida.sh                          # self-verifies vs upstream MD5s
OFF_FORMAT=csv bash scripts/download/download_openfoodfacts.sh   # pick format first
bash scripts/verify/checksum_all.sh                              # register new files
```
Open Food Facts sizes: csv ~0.9 GB gz · parquet ~10 GB · jsonl ~10 GB ·
mongodb ~50 GB. Disk is not a constraint (621 GB free).

### 4. Phase 6 Gulf/Arab portal sweep — not started
11 portals with English and Arabic query terms are listed in
`metadata/GULF_ARAB_OPEN_DATA_INVENTORY.md`. Expect low yield. Triage every hit:
Category A (food → nutrient values) is collectable; Category B (agriculture,
prices, establishments, trade) is noted and **not** downloaded.

---

## Two findings that should shape the next phase

- **SFDA's tables are prepared traditional dishes organised by region**, given
  per 100 g edible portion and per whole recipe (4–6 adults) — not a
  raw-ingredient table. They complement USDA/CIQUAL rather than duplicating
  them, but Saudi *ingredient* coverage remains unsolved and the values exist
  only as PDF layout.
- **The Gulf is close to a data desert.** No Gulf state publishes a structured
  food composition dataset. Arabic and Gulf coverage must be **built, not
  collected** — which makes Almanac-native records a differentiator rather than
  a gap.

When processing eventually starts, the first design decision is the **licence
boundary**, not the schema: Groups A/B/C/D must stay separable end to end,
because a merge that mixes ODbL or `unclear` data into the core is not
reversible by deleting rows later. Provenance columns before nutrient columns.

---

## Suggested skills

| Skill | Use it for |
|---|---|
| `mattpocock-skills:research` | Item 2 — investigating each FAO/NIN/FSANZ/RIVM licence against primary sources and capturing findings as a Markdown file. This is the bulk of the remaining work and it is exactly reading legwork. |
| `pdf` | The five FAO user guides and both SFDA volumes are PDFs. Needed to read licence pages now, and essential later for extracting SFDA's dish tables. |
| `xlsx` | Most collected datasets are workbooks (CIQUAL, CoFID, AFCD, all FAO). `BioFoodComp4.0.xlsx` carries its copyright terms in an internal sheet. |
| `nimble:search` | Item 4 — the Gulf/Arab portal sweep across 11 national open-data sites. |
| `data:validate-data` | Only once processing is authorised — schema and integrity checks on extracted data. Not part of the collection phase. |

Do **not** reach for processing, modelling or visualisation skills yet — Phase
16 forbids it until the collection report is accepted.

---

## Working preferences

Execution partner, one thing at a time. Split next steps into personal actions
vs AI-delegatable work. Neutral decision tables, no embedded recommendations.
Name avoidance directly. Scope outputs to the request rather than
over-producing. The user is time-poor — lead with the answer.

*No credentials, keys or personal contact details appear in this project. The
USDA API key referenced in `scripts/download/download_usda.sh` comments is not
required for bulk downloads and none is stored.*
