# Almanac

The platform-free half of the app: a Swift package with **no Apple framework
imports**, plus the iOS app and widget that sit on top of it.

Everything under `Sources/AlmanacCore` builds and its tests run on Linux
(`.github/workflows/ci.yml`, `swift:6.0.3-jammy`). Everything under `Native/`
is an Xcode target and is checked by the `build-app` and `test-ios` jobs. The
split is the point: the domain logic does not need a Mac to be verified, and the
UI does not get to be the only thing that is.

## Status

The detailed, newest-first build log is
[`docs/implementation-status.md`](docs/implementation-status.md). The product
requirements are [`docs/brd-v1_6.md`](docs/brd-v1_6.md) and the technical
specification is [`docs/almanac-tech-spec-v1_0.md`](docs/almanac-tech-spec-v1_0.md).

| Foundation (Technical Spec §4) | Here |
|---|---|
| Database | `Database`, `SQLiteError`; SQLite vendored under `Sources/CSQLite` |
| Migration runner | `Migration`, `MigrationRunner`; **54 migrations** |
| Domain schema | **Built** — ~76 tables, transcribed from §5 across migrations 002–045 |
| TimeModel / `logicalDay()` | Built; the §7.1 **04:00** boundary is the default, still injectable |
| Readiness cycles | Built — `ReadinessCycleStore`, and the §8.4 linking services |
| HealthKit | `HealthProvider` protocol + `FakeHealthProvider` in core; the concrete provider is the one file under `Native/` that imports HealthKit |
| SyncAnchor | `sync_anchor`, `SyncAnchorStore` |
| Backup / restore | **Built** — snapshot via SQLite's online backup; `restoreBundle` implements §16.2 |
| Provenance enums | `LicenceGroup`, `NutrientQualifier`, `SourceIdentifier` |

**This table was rewritten on 2026-09-30.** The version before it said the
48-table domain schema was "NOT BUILT — spec text unavailable", that
`ReadinessCycle` was not built, and that restore was "unimplemented by design".
All three were false: the spec was recovered on 2026-09-15 and committed under
`docs/`, the schema exists, and restore is implemented and exercised by the
backup UI. A status table that is confidently wrong is worse than no status
table, so each row above now names the type that implements it and can be
checked.

## What is deliberately not built

**A single `Migration_001` holding all 48 tables.** The spec's §5 schema is
transcribed, but across numbered migrations rather than one. Migrations are
append-only and the app has users, so a table added in migration 031 cannot be
retro-fitted into a migration 001 that already ran on their device.
`docs/architecture/spec-reconciliation.md` holds the four places where the
recovered spec's own tables collide with tables this repo built first.

**The four `notification_rule.suppressDuring*` columns.** They exist because
§5.25 names them, and they are never written. `NotificationSuppressionMatrix`
is the single authority on what suppresses what, and a second writable copy of
the same matrix is a rule that can disagree with itself.

**`day_record.dayType`.** The column exists and nothing writes it. Fasting is
read from `religious_fast_schedule` instead, which is both a range — so "prior
years' Ramadan data" is answerable — and correctable by the user. See
`docs/features/readiness.md`.

**Catalog reference intervals.** Preserved as the source printed them. No
catalog-level fallback is applied, because a range the app invented is a claim
about the user's blood results that nobody made.

## Building

    swift build
    swift test          # 606 tests, 75 suites

On a Mac, the app and widget:

    xcodebuild build -project Native/Almanac.xcodeproj -scheme Almanac \
      -destination 'generic/platform=iOS Simulator'
    xcodebuild test  -project Native/Almanac.xcodeproj -scheme Almanac \
      -destination 'platform=iOS Simulator,name=<device>'

The UI test suite takes roughly 30–50 minutes on a simulator; `swift test` is
the fast gate and is what to run while iterating.

## SQLite

Vendored as the public-domain amalgamation (3.45.1) under `Sources/CSQLite`
rather than linked from the system, so the Linux core and the iOS app compile
against a byte-identical SQLite. To link the OS copy instead, replace the
`CSQLite` target with a `systemLibrary` target — nothing above it changes.

## Layout

    Sources/AlmanacCore/
      Persistence/   Database, Migration, MigrationRunner, Migrations
      Time/          Clock, TimeModel (the 04:00 logical day)
      Provenance/    LicenceGroup, NutrientQualifier, SourceIdentifier
      Sync/ Health/ Backup/ Documents/
      <Domain>/      one directory per domain — see docs/features/
    Sources/CSQLite/          vendored sqlite3 amalgamation
    Tests/AlmanacCoreTests/
    Native/Almanac/           the iOS app
    Native/AlmanacWidgets/    the widget extension
    Native/AlmanacUITests/    UI tests
    docs/                     spec, BRD, build log, per-domain notes

One directory per domain under `AlmanacCore`, and `docs/features/<domain>.md`
beside it. A domain's doc is where its open questions live — the ones that need
a decision rather than more code — so they are not rediscovered every session.

## Working practices this repo holds to

These are the rules that the code is shaped by, and they are worth knowing
before changing it.

**Foundational modules do not know about what is built on them.** Hydration and
Nutrition do not learn that Fasting exists. New wiring goes in a wrapper beside
the base store — `FastingAwareHydrationLog`, `FastingAwareNutritionLog` — and
not inside it.

**Pull-based, idempotent reconciliation beats a call site per write path.**
`ensureCache`, `ensureCycle`, `ensureDay`, `NotificationPlanner.plan()`. The
repo has been bitten by manual multi-site wiring: six hydration write paths had
to be wired by hand for night-window assignment, and the note left behind was
that the seventh path added later would be the one that forgot. A missed call
site should cost one stale refresh, not a permanently wrong state.

**A status claim is a claim that can be checked.** Several handoffs in a row
arrived with confidently wrong statements about this codebase — that a feature
was blocked on a column nothing reads, that a table was unbuilt when it had
been written weeks earlier. Read the source before believing one, including
this README.

**A test that asserts a bug is worse than no test.** When a test and reality
disagree, work out which is which before editing either. One such test is
recorded in `docs/implementation-status.md` for the religious-fasting work.

**Say what was not run.** A manual or device-only step that nobody drove is
marked unrun, not ticked. `docs/acceptance-checklist.md` is the place to look.
