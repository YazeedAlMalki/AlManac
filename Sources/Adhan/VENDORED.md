# Vendored: batoulapps/adhan-swift

Prayer-time astronomical calculations, vendored as source rather than an SPM
dependency — same pattern as `Sources/CSQLite` (see its `Package.swift`
comment): the Linux core and the iOS app should compile against byte-identical
code, and this repo prefers vendoring over a dependency graph for a component
this small and this stable.

- **Source:** https://github.com/batoulapps/adhan-swift
- **Commit vendored:** `0bc10007aa215ead55e8ee294f9254f0dc2f9a7d` (2026-08-21)
- **License:** MIT (c) 2016 Batoul Apps — see `LICENSE` in this directory,
  copied verbatim per the license's own terms.
- **Files:** everything under upstream `Sources/` (`Astronomy/`,
  `Extensions/`, `Models/`, `Units/`, plus `PrayerTimes.swift`, `Qibla.swift`,
  `SunnahTimes.swift`), unmodified. Upstream's `Example/` and `Tests/` were
  not vendored — this repo's own `AdhanCalculatorTests` cover the wrapper in
  `Sources/AlmanacCore/Prayer/`, not the astronomy itself.
- **Why this library:** decided in `docs/features/fasting.md` §3 — a proven,
  MIT-licensed, actively-maintained Swift port rather than hand-writing the
  solar-position formulas.

To re-vendor after an upstream update: re-fetch the files listed above from
the new commit, diff before overwriting (this repo has made no local
modifications to vendored files, so a clean diff is expected), and update the
commit hash here.
