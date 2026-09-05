# AlmanacCore

The platform-free half of **Slice 1 — Foundation**.

Swift package with **no Apple framework imports**. It compiles and its tests run
on `yamal` (Linux) today, which is the point: the parts of Slice 1 that do not
require Xcode, a Mac, or HealthKit are built and verified now, and the parts
that do are left as protocol boundaries.

## Status

| Slice 1 item (Technical Spec v1.0, Section 20) | Here |
|---|---|
| DatabaseManager | Built — `Database`, `SQLiteError` |
| Migration runner | Built — `Migration`, `MigrationRunner` |
| **Migration_001 (48-table domain schema)** | **NOT BUILT — spec text unavailable** |
| TimeModel / `logicalDay()` | Built; boundary rule **injected, not assumed** |
| ReadinessCycle skeleton | Not built — needs the spec's readiness definition |
| HealthKitManager init | Built as `HealthProvider` protocol + `FakeHealthProvider` |
| SyncAnchor table | Built — `sync_anchor`, `SyncAnchorStore` |
| BackupService skeleton | Built — snapshot via SQLite online backup; restore unimplemented by design |
| Provenance enums | Built — `LicenceGroup`, `NutrientQualifier`, `SourceIdentifier` |

## What was deliberately NOT built, and why

**The 48-table domain schema.** `almanac/technical-spec-v1.0.md` in the Claude
project is a *pointer*, not the spec — the verbatim text lives only in the
conversation where it was pasted. Authoring those tables from inference would
produce a Migration_001 that user data accumulates against before anyone
notices it was guessed. That is the same failure class the food-lake processing
design is built to prevent, so it was refused rather than approximated.

`Migration001_CoreInfrastructure` therefore creates only the two tables this
package genuinely owns (`sync_anchor`, `backup_manifest`). The domain schema
belongs in migration 002 and must be **transcribed** from the spec.

**The logical-day boundary.** A body monitor almost certainly does not start its
day at midnight — an entry at 01:30 usually belongs to the night before. The
spec defines the real rule; it is unavailable, so `DayBoundary` is injected and
`.midnight` is a placeholder, not a decision.

**Restore.** `BackupService.restore` throws by design. What happens to in-flight
sync anchors and to rows created after a snapshot is a spec question, and
guessing it is how a restore silently eats a day of logs.

## Building

    source env.sh          # puts Swift 6.3.3 and its libs on PATH
    swift build
    swift test             # 27 tests

Swift 6.3.3 lives in `~/.local/swift/`. Ubuntu 26.04 ships `libxml2.so.16` and
newer ICU, but the ubuntu24.04 toolchain wants `libxml2.so.2` and
`libicuuc.so.74`; copies sit in `~/.local/swiftdeps/` and `env.sh` puts them on
`LD_LIBRARY_PATH`. Nothing was installed system-wide and no sudo was used.

## SQLite

Vendored as the public-domain amalgamation (3.45.1) under `Sources/CSQLite`
rather than linked from the system, so the Linux core and the iOS app compile
against a byte-identical SQLite. To link the OS copy instead, replace the
`CSQLite` target with a `systemLibrary` target — nothing above it changes.

## Layout

    Sources/AlmanacCore/
      Provenance/    LicenceGroup, NutrientQualifier, SourceIdentifier
      Persistence/   Database, Migration, MigrationRunner, Migrations
      Time/          Clock, TimeModel
      Sync/          SyncAnchorStore
      Health/        HealthProvider (protocol) + FakeHealthProvider
      Backup/        BackupService, SHA256File
    Sources/CSQLite/ vendored sqlite3 amalgamation
    Tests/AlmanacCoreTests/

## When the spec arrives

1. Save it verbatim to the Claude project so this cannot happen again.
2. Transcribe the 48 tables into `Migration002_DomainSchema`.
3. If the spec's build order calls the 48-table migration `Migration_001`,
   renumber this one to 000 — free today, expensive after the first install.
4. Replace `DayBoundary.midnight` with the spec's real rule.
5. Add `ReadinessCycle` against the spec's definition.

The iOS app target imports this package, and `import HealthKit` may appear in
exactly one file there: the concrete `HealthProvider`.
