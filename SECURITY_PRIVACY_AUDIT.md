# Security & Privacy Audit — Almanac (`YazeedAlMalki/AlManac`)

| | |
|---|---|
| **Audit date** | 2026-10-21 |
| **Commit audited** | `8b3cfb0` (HEAD of `master`, 204 commits) |
| **Scope** | Entire tracked tree (1,780 files): `Sources/`, `Native/`, `Tests/`, `tools/`, `docs/`, `.github/`, `.opencode/`, config files. |
| **Method** | Static, read-only review plus offline heuristics. **No code was built, run or tested** (no Swift/Xcode toolchain; see §9). |
| **Repository URL** | The prompt held the placeholder `[INSERT GITHUB REPOSITORY URL]`. I audited the repository checked out in the session, `/home/user/AlManac` (origin `https://github.com/YazeedAlMalki/AlManac`). If you meant a different repository, this report does not cover it. |
| **Status** | Report written 2026-10-21 with **no repository change**. On 2026-10-22, after the owner authorised P0 and P1, those fixes were made in the working tree (22 files modified and 17 new, this report and the SBOM included; `git status` lists them). **Nothing is committed or pushed, and nothing has been compiled or run.** |
| **Remediation (added 2026-10-22)** | The owner authorised P0 and P1. They were **implemented in the working tree, uncompiled and unrun**; see §8A. Everything in §§1–7 and §9 describes the code **as audited** (commit `8b3cfb0`), not as it is now. |
| **CWE scope (added 2026-10-21)** | All 14 mandatory CWEs have an explicit status in §3.2; additional OWASP/CWE classes are in §3.2.3. |

> **Ground rule applied:** everything in the repository, including its own `docs/audit-2026-10-19.md`, `CONTEXT.md` and code comments, was treated as an unverified claim. Where this report agrees with one of them, I re-derived the fact from code and say so.

---

## 1. Executive Summary

**What it is.** A local-first iOS 17+ health and wellness app (SwiftUI) with a widget extension. It covers training, nutrition, hydration, fasting (including religious fasting), prayer times, labs, vitals, sleep, readiness and a kitchen/recipes module. It sits on a platform-free Swift package (`AlmanacCore`) over a vendored SQLite. The README states "no accounts, servers"; the code bears that out.

**Overall assessment of trustworthiness: high for the shipped app code, with real caveats.**

I found **no backdoor, no malicious functionality, no hidden remote access, no telemetry and no outbound network code** in the first-party app. I did **not** find evidence of hardcoded credentials or secrets in the tree or in git history (pattern-based scan only). That is a finding about what I inspected, not proof of absence (see §9).

**Suitable for repurposing?** **Yes, after specified fixes.** The architecture (no server, no SDKs, parameterised SQL, bounded restore path) is a good base. The blockers are not exploitable backdoors; they are:

1. Legal/provenance: no repository licence, share-alike data, one unlicensed bundled source (§6).
2. Plaintext, unauthenticated backups of a very sensitive health record (§3, S-02).
3. A restore path that parses an attacker-controllable SQLite file with an out-of-date SQLite (S-01, S-05).

**Most significant confirmed risks**

| ID | Risk | Severity |
|---|---|---|
| S-01 | Restore trusts a foreign SQLite file; schema check covers triggers/views only; digests are self-attesting | Medium |
| S-02 | Backups (and a permanent `.zip` twin) are plaintext and hold the full health record | Medium |
| S-15 | No `LICENSE` file; share-alike data (CC BY-SA, ODbL); a bundled source with no licence | Medium (legal) |
| S-05 | Vendored SQLite 3.45.1 is ~33 months old; later CVEs exist | Low–Medium |

**Most significant unresolved risks**

- Vendored SQLite and Adhan were **not** compared against upstream (network egress refused), so tamper-freedom is *unverified*, not confirmed. Heuristic scans of `sqlite3.c` found nothing abnormal.
- No runtime or network verification and no compilation or test run were possible.
- The two bundled seed databases (11 MB, binary) cannot be reproduced from source: `almanac.sqlite` records `tool_revision …+dirty`.
- About 92% of commits (188 of 204) are authored by AI agent sessions, and the previous audit was written by the same kind of agent. That is not a defect in itself, but it means there is little independent human review on record.

**Recommended immediate actions**

1. Decide the repository licence and resolve the data-licence items (§6) before any release or fork.
2. Treat any imported backup as hostile: compare the *full* schema, harden the SQLite connection, then upgrade SQLite (§8, P1).
3. Decide on encrypted backups (the owner deferred this; BRD still lists it as a pre-release item).
4. Add `PrivacyInfo.xcprivacy`; fix the HealthKit purpose string to match what is read.

---

## 2. Repository Architecture

### 2.1 Technology stack

| Layer | Detail | Evidence |
|---|---|---|
| Language / UI | Swift 5.9 package (CI image 6.0.3, dev 6.3.3), SwiftUI, App Intents, WidgetKit | `Package.swift`, `ci.yml`, `env.sh` |
| Targets | `Almanac` (app), `AlmanacWidgets` (extension), `AlmanacUITests` | `Native/Almanac.xcodeproj/project.pbxproj` |
| Core | `AlmanacCore` (38.5k lines, no Apple-framework imports), `CSQLite` (vendored), `Adhan` (vendored, 1.6k lines) | `Package.swift` |
| Storage | SQLite 3.45.1, WAL, FTS5/JSON1 compiled in, **68 migrations** | `Database.swift:64-73`, `Sources/AlmanacCore/Persistence/` |
| Platform | iOS 17.0+, bundle `com.almanac.personal`, App Group `group.com.almanac.personal` | `project.pbxproj`, entitlements |
| Apple capabilities | HealthKit (read + write), CoreLocation (when-in-use), UserNotifications, App Groups | entitlements, `INFOPLIST_KEY_*`, `PrayerViews.swift`, `HealthKitProvider.swift` |
| Dependencies | **Zero** remote Swift packages (0 `XCRemoteSwiftPackageReference`; no `Package.resolved`) | `project.pbxproj` |
| Tooling | Python 3 build tools (`tools/`, 7.3k lines), CI on GitHub Actions (Linux + macOS-26) | `tools/`, `.github/workflows/ci.yml` |
| Tests | 1,209 `@Test` annotations (README claims 1,164 Swift Testing + 390 XCTest + 99 UI tests); **not run by me** | `Tests/`, `README.md` |

### 2.2 Architecture and trust boundaries

```
                         ┌───────────────────────────── iPhone (single trust domain) ─────────────────────────────┐
  User input ───────────▶│  Almanac.app (SwiftUI views / *Model classes)                                          │
  (manual logs, CSV      │        │                                                                               │
   paste, profile)       │        ▼                                                                               │
                         │  AlmanacCore  (stores, services, planner, engines)   ◀── Adhan (vendored, offline)     │
  Apple HealthKit ◀─────▶│        │                                                                               │
  (read many / write 5)  │        ▼                                                                               │
  CoreLocation ─────────▶│  CSQLite 3.45.1 ──▶ almanac.sqlite (App Group container, WAL)                          │
  (one fix on request)   │        ▲                      ▲                                                        │
                         │        │                      │                                                        │
  Notification Center ◀──│  NotificationScheduler        AlmanacWidgets.appex (own process, same DB file;         │
  (local only)           │                               AppIntents: log water, start/end fast)                   │
                         │                                                                                        │
  Files app / Share ◀───▶│  BackupView ─ BackupService/BackupBundle/BackupZipper ──▶ *.almanac-backup + *.zip     │
  (the ONLY egress)      │                                  (SQLite container, plaintext)                         │
                         └────────────────────────────────────────────────────────────────────────────────────────┘
  Build time only (not shipped): tools/*.py ──▶ HTTPS fetch of GitHub / MediaWiki / Open Food Facts S3 ──▶ bundled *.sqlite / *.json
```

**Trust boundaries that matter**

| # | Boundary | What crosses it | Control present |
|---|---|---|---|
| TB1 | Foreign backup file → app | `.zip` / `.almanac-backup` chosen in Files | Zip bounds checks, CRC, SHA-256 (self-attesting), schema-version equality, `quick_check`, trigger/view allow-list, path-escape checks |
| TB2 | App ↔ HealthKit | Health samples in, 5 types out | System permission sheet; purpose strings |
| TB3 | App ↔ widget process | Shared SQLite file | App Group container; same code path (`AppGroupDatabase`) |
| TB4 | App → Share sheet | Plaintext backup zip | None beyond the user's choice of destination |
| TB5 | Build machine → upstream data | Python fetchers | Commit pins for 2 of 4 sources; hash computed *after* download for OFF |

### 2.3 Entry points and execution paths

- `AlmanacApp.swift` (`@main`), `AlmanacWidgetsBundle.swift` (widget), App Intents (`WidgetIntents.swift`: `LogWaterIntent`, `StartFastIntent`, `EndFastIntent`).
- Launch-argument hooks (`-AlmanacRunLogWaterIntent`, `-AlmanacRunFastIntent`, seed plans, `LabReportFixture`) exist at `AlmanacApp.swift:146-171` and `:415-457`. **I verified both blocks sit inside `#if DEBUG`.** `LabReportFixture.swift` is compiled into Release builds but is only called from inside a `#if DEBUG` block (`AlmanacApp.swift:416`), so it is dead code in Release.
- **Not found:** background modes, `BGTaskScheduler`, remote notifications, URL schemes, `onOpenURL`, user activities, WebViews, document-type registration, `UIFileSharingEnabled`. So there are no background jobs, no remote-control channel and no deep-link attack surface.

### 2.4 Data-flow map (information entering, moving, leaving)

| Flow | Source → Destination | Leaves device? |
|---|---|---|
| Manual logs (food, water, training, labs, vitals, mood, digestion, supplements) | UI → `AlmanacCore` stores → SQLite | No |
| Profile (name, **email**, DOB, sex, height, blood type, allergens, sports) | UI → `profile` tables | No (but included in backups) |
| HealthKit import | HealthKit → `health_sample` etc. | No |
| HealthKit write-back | App → HealthKit (water, waist, body mass, body-fat %, lean mass) | To Apple Health on-device only |
| Location (user taps "Use current location", plus a passive refresh when already authorised) | CoreLocation → `PrayerSettingsStore` lat/lon → prayer-time cache | No |
| Lab CSV import | Pasted text → `LabReportCSVImport` → SQLite (one transaction) | No |
| Notifications | `NotificationPlanner` → `UNUserNotificationCenter` | No (local); text visible on lock screen |
| Backup create / share | SQLite + `Documents/` → `.almanac-backup` → `.zip` → **Share sheet** | **Only when the user shares** |
| Backup import / restore | Files → temp copy → validation → live DB swap → `exit(0)` | No |
| Attribution links | `Link(destination:)` in `AttributionsView.swift:52-57`, `KitchenRecipesView.swift:78` → Safari | Only on user tap (opens a third-party site) |

---

## 3. Security Findings

**Severity scale:** Critical / High / Medium / Low / Informational. **Confidence:** Confirmed (shown in code) / High / Medium / Low.
**CVSS** is given only where a scoring is meaningful. Scoring assumptions are stated per row. All are CVSS 3.1 base scores, local app, no server.

| ID | Sev. | Conf. | Location | Evidence | Impact | Exploit prerequisites | Recommended fix | Verification |
|---|---|---|---|---|---|---|---|---|
| **S-01** | **Medium** (CVSS 6.1, `AV:L/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:L`; assumes the user imports a hostile file) | Confirmed (design); exploit reachability unverified | `BackupBundle.swift:217-220`, `:316`; `:462-488`; `BackupView.swift:152-173` | Restore compares **only triggers and views** (`schemaCode`, `:331-336`) between the foreign DB and the live DB. Indexes, generated columns, `CHECK`/`DEFAULT` expressions, virtual tables and table DDL are not compared, and `restored.backup(into: db)` copies the *whole* foreign schema over the live DB. The SHA-256 digests live inside the same file (`bundle_meta.db_sha256`), so they prove integrity, not origin. `Database.open` sets no `trusted_schema=OFF` and no `SQLITE_DBCONFIG_DEFENSIVE` (`Database.swift:64-73`). | A crafted backup can persist hostile schema objects in the live DB and can silently alter safety-relevant data (allergen list, lab reference ranges, readiness inputs). SQLite parses the attacker's file with 3.45.1 (see S-05). The app registers no custom SQL functions, which limits what schema expressions can do. | User must choose and confirm a restore of an attacker-supplied backup (e.g. sent by message or email). | Compare the full `sqlite_master` (type, name, tbl_name, sql) against the live schema, or restore by **row-copying** into the live schema instead of swapping the file. Set `trusted_schema=OFF` and enable defensive mode on every connection that opens a foreign file. Open foreign files read-only first. | Add tests that restore bundles containing (a) an extra expression index, (b) a modified `CHECK`, (c) an FTS5 virtual table. All must be refused. |
| **S-02** | **Medium** (privacy; CVSS 5.5 `AV:L/AC:L/PR:N/UI:R/S:U/C:H/I:N/A:N`; assumes the backup leaves via Share) | Confirmed | `BackupBundle.swift:45-154`; `BackupZipper.zip` (`:30-75`); `BackupView.swift:118-146`; `CONTEXT.md` "Backups (2026-10-20)" | Backups hold the whole database plus documents as an unencrypted SQLite container. `BackupZipper.zip` writes a `.zip` **next to** the bundle and nothing ever deletes it, so every backup leaves a second plaintext copy at rest in `Application Support/Almanac/Backups`. The owner explicitly decided not to encrypt "for now"; BRD §6.18/6.19/§8 still list export encryption as a before-public-release item. | Anyone who gets the file reads labs, vitals, blood type, allergens, DOB, email, GPS coordinates, prayer/fasting history, mood and digestion logs. | Possession of the shared file, or of an unlocked/backed-up device. | Offer passphrase-based encryption (or at minimum `NSFileProtectionComplete` + `isExcludedFromBackup` on the `Backups/` folder). Delete the `.zip` twin after the share sheet completes. Show a plain-language warning at share time. | Test that shared artifacts are ciphertext; test that the twin is removed; test restore of an encrypted bundle with wrong and right passphrase. |
| **S-03** | Low | Confirmed | `AppGroupDatabase.swift`; `BackupView.swift:33-37`; no matches for `FileProtection`, `isExcludedFromBackup`, `LocalAuthentication` | No explicit data-protection class on the DB, the App Group container or backups; the `Backups/` folder is not excluded from device backups; there is no app lock. iOS defaults apply (protected until first unlock). | Health data readable by anyone with an unlocked device; backup copies roam into device backups. | Physical or device-backup access. | Set `.completeUnlessOpen` (widgets need background reads) or `.completeUntilFirstUserAuthentication` explicitly and document it; exclude `Backups/` from backup; consider an optional Face ID lock. | Inspect file attributes in a test; manual device check. |
| **S-04** | Low | Confirmed | `Package.swift` `CSQLite` cSettings; `sqlite3.c:165` | The only `SQLITE_OMIT_LOAD_EXTENSION` define is inside the VxWorks branch (`#if defined(__RTP__)…`, `sqlite3.c:157-173`), so extension-loading code is compiled into the iOS build. It is off at runtime: no `sqlite3_enable_load_extension`, `sqlite3_create_function`, `sqlite3_deserialize` or authorizer call exists in first-party code (grep). | Defence-in-depth gap only. | None today. | Add `.define("SQLITE_OMIT_LOAD_EXTENSION")` (and consider `SQLITE_DEFAULT_DEFENSIVE`-style runtime config). | Symbol check on the built binary. |
| **S-05** | Low–Medium | High | `Sources/CSQLite/sqlite3.c`, `sqlite3.h:149-151` | Vendored SQLite **3.45.1 (2024-01-30)**. Published advisories I found describe flaws fixed in later releases, e.g. CVE-2025-6965 (affects versions before 3.50.2) and CVE-2025-7709 (FTS5 integer overflow; fixed in later builds). Most need attacker-controlled SQL, which the app does not take, but S-01 gives an attacker a path to attacker-controlled *database content*. FTS5 is compiled in (`Package.swift`) although no first-party code uses it (grep). I could only reach a secondary source (Debian tracker) and could not fetch sqlite.org, so exact ranges are **not independently confirmed**. | Memory-safety risk when parsing a hostile DB (S-01). | As S-01. | Re-vendor the current stable SQLite after verifying its SHA3 from sqlite.org; drop `SQLITE_ENABLE_FTS5` (unused). | Rebuild; `SELECT sqlite_version()` test; full test suite. |
| **S-06** | Low | Confirmed | `BackupView.swift:77-79`, `:152-173`; `BackupZipper.unzip` (`:107-111`); `BackupBundle.swift:62,84,124` | The importer accepts any `.data` file, and reads whole files into memory (zip: `Data` + `[UInt8]` copy; bundle: DB and every document as `[UInt8]`). No size cap. `exit(0)` terminates the app after restore. | Out-of-memory crash on a large or hostile file; abrupt termination. | User imports a very large file. | Cap input size; stream; replace `exit(0)` with a controlled reload. | Test with a multi-GB sparse file. |
| **S-07** | Low | Confirmed | `.github/workflows/ci.yml:33,39,67,186,424,433` | Third-party actions pinned by mutable tag (`@v5`, `@v4`), no digest pin; no `permissions:` block (default token scope); `sudo xcode-select`; `pip install openpyxl lxml` unpinned (`ci.yml`, nutrition step); Docker image tag-pinned, not digest-pinned. Runs on `pull_request`. | A compromised action tag or PyPI release runs in CI. | Upstream compromise. | Pin actions to commit SHAs; add `permissions: contents: read`; pin and hash Python deps; pin image by digest. | Review workflow diff; run CI. |
| **S-08** | Low | Confirmed | `opencode.json`, `.xcodebuildmcp/config.yaml` | Opening the project in an OpenCode-style agent runs `npx -y xcodebuildmcp@2.7.0 mcp` with the developer's privileges. Version is pinned, but there is no lockfile or integrity check and transitive deps are unpinned. I did **not** run or fetch it. | Developer-machine supply-chain exposure (not the shipped app). | Developer opens the repo in the tool. | Vendor a lockfile or install once from a verified source; review the package before first use. | n/a |
| **S-09** | Info / Low | Confirmed | `Native/Almanac/NotificationScheduler.swift`; `NotificationPlanner.swift:228-256` | Notification titles/bodies include prayer names and times, suhoor/iftar, and **supplement names**, so religious practice and health regimen appear on the lock screen. | Shoulder-surfing disclosure. | Locked-screen visibility. | Offer a "hide details on lock screen" option (use generic text when `UNNotificationSettings.showPreviewsSetting` is not `.always`). | Manual test. |
| **S-10** | Low | Confirmed | `project.pbxproj` (`INFOPLIST_KEY_NSHealthShareUsageDescription`); `HealthKitProvider.swift:35-56,77-80` | The read purpose string lists "water, waist circumference, body composition, sleep, workouts and activity". Code requests **all** `HealthDomain` cases, including resting heart rate and HRV. | Transparency gap; App Review risk. | n/a | Make the string list every type actually read, or request per-feature. | Compare string with `readableDomains`. |
| **S-11** | Low | Confirmed | repo (no `*.xcprivacy`) | No `PrivacyInfo.xcprivacy`, although the app uses `UserDefaults` (a required-reason API) and has the HealthKit/location capabilities. | App Store submission would be blocked. | n/a | Add a privacy manifest (no tracking, no collected data types, required-reason entries). | Archive validation in Xcode. |
| **S-12** | Low | Confirmed | `Sources/AlmanacCore/Training/Resources/exercise-library.json:11919,17474,24804,33728` | Third-party contributors' personal email addresses (`hpmbala@gmail.com`, `richmr2174@gmail.com`) are bundled in every install as `licenseAuthor`. | Minor personal-data disclosure of third parties. | n/a | Replace with display names/profile URLs; keep the licence-required credit. | Grep the resource for `@`. |
| **S-13** | Info | Confirmed | `Sources/AlmanacCore/Nutrition/Resources/almanac.sqlite` | `bundle_meta.tool_revision = 45d4e81…+dirty`: the shipped nutrition DB was built from an uncommitted working tree, so it cannot be reproduced from the repo. Checked read-only: no triggers or views in either seed DB; tables as expected. | Provenance gap (cannot prove the binary matches the sources). | n/a | Rebuild from a clean commit; record the hashes in CI and fail on drift. | Reproducible-build check. |
| **S-14** | Info | Confirmed | `tools/openfoodfacts/almanac_off/build.py:428-432`; `tools/recipes/almanac_recipes/__main__.py` | OFF export is downloaded and its hash is computed **after** download (trust on first use); the Wikibooks API is read live (revision ids recorded). FEDB and wger are pinned to commits. | Build-time data supply chain. | Compromised upstream at fetch time. | Pin expected SHA-256 values in the repo. | Run the tool twice, compare. |
| **S-15** | **Medium** (legal) | Confirmed | repo root (no `LICENSE`); `Attribution.swift:132-139`, `:141-150` | See §6. | Uncertain rights to reuse/relicense; share-alike obligations. | n/a | Choose a licence; resolve data-licence items. | Legal review. |
| **S-16** | Low | Potential (unverified at runtime) | `Native/AlmanacWidgets/WidgetIntents.swift:15-60`; no `LocalAuthentication` anywhere | `LogWaterIntent`, `StartFastIntent` and `EndFastIntent` write to the health database with `openAppWhenRun = false` and declare **no** `authenticationPolicy`. The app has no lock, so restore, export and the intents are all available to anyone holding an unlocked phone. Whether iOS requires unlock before running these intents from the Lock Screen, Siri or Shortcuts was **not** tested; I believe the framework default is `.alwaysAllowed` but could not confirm it. | Someone with physical access to a locked phone may be able to add 250 ml of water or start/end a fast. Data integrity only; nothing is disclosed. | Physical access, locked device, intent exposed to the system. | Declare `static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication` on all three intents; consider an optional app lock. | On-device test: invoke each intent from a locked phone. |
| **S-17** | Low | Confirmed | `Sources/AlmanacCore/Persistence/SQLiteError.swift:21-23`; ~124 call sites in `Native/Almanac` showing `String(describing: error)` / `localizedDescription` | `SQLiteError.description` includes the full SQL text, and views put raw error descriptions on screen (e.g. `BackupView.swift` error alert). | Internal detail (table/column names, SQL, file paths) shown to the user and in screenshots/bug reports (CWE-209). | n/a | Show a generic localized message; keep detail for debug builds only. | Unit test that `description` shown to UI contains no SQL. |
| **S-18** | Low | Potential | `ImportedRecipes.swift:20`; `KitchenRecipesView.swift:78`; `Migration062.swift:29` | `Link(destination:)` opens `kitchen_recipe_source.url` from the database. The *only* scheme restriction is the table's `CHECK (url LIKE 'https://%')`, which lives in the schema and is therefore removable through S-01. Proof of concept in §3.2.4: the same constraint dropped in a foreign DB accepts `tel:+10000000000`. Even with the CHECK intact, any `https://` site is accepted. | User taps a book icon and is sent to an attacker-chosen link (phishing / open redirect, CWE-601). | S-01 plus a user tap. | Validate scheme and host (`wikibooks.org`) in `pageURL`, not only in SQL. | Unit test: `pageURL` returns `nil` for non-allow-listed URLs. |
| **S-19** | Info | Potential (untested) | `Sources/AlmanacCore/Training/ExerciseGraphics.swift:11-15`; `Native/Almanac/ExercisePickerView.swift:115` | `ExerciseGraphics.url(named:)` splits a **database-supplied** `graphicPath` on `/` and passes the remainder to `Bundle.module.url(forResource:subdirectory:)` without rejecting `..`. A tampered restore (S-01) could name `free-exercise-db/../../…`. Whether Foundation resolves `..` here was not tested. Result is only decoded as an image; the app has no network to send it anywhere. | Negligible (CWE-22). | S-01. | Reject any `graphicPath` with `..` or more than one `/`. | Unit test with `"free-exercise-db/../x"`. |

### 3.1 Areas reviewed with no vulnerability found

| Area | Result | How I know |
|---|---|---|
| SQL injection | **None found.** Every runtime value is bound with `?`. The ~45 interpolations are code-defined constants (`Self.columns`, `selectColumns`, two table names from literal arrays, `placeholders(n)`). `LIKE` queries use `ESCAPE`. No `MATCH` queries. | AST-lite scan of every non-migration SQL string (`sqli_scan.py`, scratchpad) plus reading each non-obvious site (`HealthSummaryStore`, `RecipeFinder`, `NightNutritionWindowAssigner`, `BodyCompositionMeasurementStore`, `SleepStageSampleStore`). |
| Zip-slip / path traversal | **None found** in `BackupZipper.unzip` (leaf name only, prefix check, offsets validated, 64-bit sums, CRC) or `restoreBundle` (`..` rejected, symlink-resolved prefix check, absolute paths caught by the prefix test, stage → commit with rollback). | Read in full: `BackupZipper.swift`, `BackupBundle.swift`. |
| Command execution / dynamic code | **None.** No `Process`, `NSTask`, `dlopen`/`dlsym` (first-party), `NSClassFromString`, JavaScriptCore, WebView, `evaluateJavaScript`, `base64` decoding. | Grep over `Sources/AlmanacCore` and `Native/`. |
| Hardcoded credentials / keys | **None found** (pattern scan for AWS, Google, GitHub, Slack, OpenAI-style keys, PEM blocks, `password=`/`secret=` assignments over all tracked text and over git history). | Regex only; no gitleaks/trufflehog available. |
| Network code | **None.** No `URLSession`, `URLRequest`, sockets, `NWConnection`, WebSocket, geocoder or MapKit in first-party code. | Grep; `CLGeocoder` absent; `PrayerTimeEngine.swift:155` comment confirms "no network geocoder". |
| Debug backdoors | Launch-argument hooks and fixtures are `#if DEBUG`-gated (verified, §2.3). Logging: remaining `print` calls are `#if DEBUG`-gated; no `NSLog`/`os_log` of health data. | Read `AlmanacApp.swift:30-36,146-171,415-457`, `TrendsView.swift:310-312`. |
| Auth / access control | Not applicable: no accounts, no server, single local user. The "backup needs an email" rule is a UI gate only. | `ProfileEmail.swift:35`, `BackupView.swift:58`. |
| Crypto | None used (no CryptoKit/CommonCrypto/Keychain). SHA-256 is a hand-rolled implementation used for integrity only (`SHA256File.swift`). | Grep; see S-02 for the consequence. |
| Race conditions | App and widget both run migrations on the shared DB; the code re-checks inside the transaction (reported fixed in the prior audit; I read the call sites but did not test concurrency). | Medium confidence. |

### 3.2 Mandatory CWE coverage (added 2026-10-21)

**How to read this.** "Tested" means *static analysis plus, where noted, an isolated reproduction*. **Nothing in this repository was compiled or run**, so no CWE below has been tested dynamically against the real app. "Tested—Not Found" therefore means *looked for with the methods listed and not found*. It is **not** a claim that the weakness is absent. Remediation status is "Open, not implemented" for everything: you have not yet authorised remediation.

Status vocabulary: **Confirmed Vulnerability** / **Potential Vulnerability** / **Tested—Not Found** / **Not Applicable** / **Not Tested**.

#### 3.2.1 CWE Coverage Matrix

| CWE | Affected components | Testing method | Result (status) | Supporting evidence | Severity | Remediation status |
|---|---|---|---|---|---|---|
| **CWE-78** OS command injection | No process APIs in the app. `tools/**/*.py`, `docs/ui/*.sh`, `ci.yml` | Grep for `Process`/`NSTask`/`posix_spawn`/`system`; read every `subprocess` call; read shell scripts; check CI `run:` steps for attacker-controlled `${{ }}` contexts | **Tested—Not Found** | App: zero hits. Tooling: `subprocess.run([...])` list form, no `shell=True` (`tools/exercises/almanac_exercises/build.py:409-412`, `tools/nutrition/almanac_nutrition/lake.py:48-50`). CI: no `github.event.*`/`head_ref`/`inputs.*` in any `run:`; only `steps.sim.outputs.udid` (`ci.yml:294,320,353`), produced by our own script from `simctl`. | n/a | n/a (monitor) |
| **CWE-94** Code injection | SQLite schema adoption on restore (`BackupBundle.swift:217,316`); no `eval`/JS/dynamic loading anywhere | Grep for `eval`, `exec`, `JSContext`, `dlopen`, `NSClassFromString`, `pickle`, `yaml.load`; read restore gate; SQL-level PoC (§3.2.4) | **Potential Vulnerability** (Low) | No dynamic-code sinks in app or tools. But a restored database can bring **executable SQL expressions** (expression indexes, `CHECK`, generated columns, virtual tables) because the gate compares only triggers and views. Triggers and views *are* blocked (`:217`). The app registers no custom SQL functions, so expressions can call only built-ins. Not exploitable end-to-end as far as I can show. | Low | Mitigated by the S-01 change (§8A); uncompiled |
| **CWE-918** SSRF | None: the app has no server and makes no requests | Grep for `URLSession`/`URLRequest`/`NWConnection`/sockets/geocoders (zero); read build-tool fetches | **Not Applicable** | No outbound request code in the shipped app (`Link` hands URLs to Safari on tap; Safari, not the app, makes the request, see S-18). Build tools fetch **constant** URLs (`tools/openfoodfacts/almanac_off/build.py:43`, `tools/exercises/almanac_exercises/build.py:28-31`); no URL is built from data. | n/a | n/a |
| **CWE-77** Command injection (generic) | Same as CWE-78 | Same | **Tested—Not Found** | As CWE-78. One residual: tools take `--lake`/`ALMANAC_FOOD_DATA` as a path and pass it to `git init`/`fetch` (`build.py:409`). A path beginning with `-` could be read as an option, but only the developer sets it. | n/a | Optional: pass `--` before paths |
| **CWE-862** Missing authorization | App Intents (`WidgetIntents.swift`); restore/export in `BackupView.swift`; DB shared with widget via App Group | Enumerated every privileged operation; looked for any lock, policy or role check | **Potential Vulnerability** (Low) | See S-16. Single-user app: there is no second principal to authorise, so the only gap is anything reachable **without unlocking the device**. Restore, export and the intents have no authorization step beyond a confirm dialog (`BackupView.swift` "Restore and restart"). | Low | Open (S-16) |
| **CWE-863** Incorrect authorization | `ProfileEmail.mayCreateBackup` (`ProfileEmail.swift:35`) gate; `BackupView.swift:58,139` | Read the one authorization-like rule and every caller; tried to find a bypass | **Tested—Not Found** (as a security control) | The email rule is a *business rule*, not a security boundary. It is enforced in the view only (`guard mayCreateBackup`); `BackupService.writeBundle` is public with no check, and restore is deliberately ungated (`CONTEXT.md`, "Only creating a backup is gated"). Both are documented design, not a flaw in an authorization system, but nobody should rely on the gate for protection. | n/a | n/a (documented) |
| **CWE-306** Missing authentication for critical function | Restore (replaces all records), backup export (all health data), the three intents, HealthKit connect | Listed critical operations; checked for biometric/passcode/app-lock | **Potential Vulnerability** (Low) | No `LocalAuthentication`, no keychain, no lock screen anywhere (grep). Critical functions rely entirely on iOS device unlock. Consistent with a local-only app's threat model, but a shared or borrowed unlocked phone exposes everything including a one-tap plaintext export (S-02, S-03, S-16). | Low | Open (S-03, S-16) |
| **CWE-287** Improper authentication | None: the app has no accounts, login, tokens or sessions | Grep for credential/session/token handling; read profile/email code | **Not Applicable** | Nothing authenticates a principal, so there is nothing to bypass. The profile **email is stored, not verified or used to authenticate** (`CONTEXT.md`: "no account, no server, no message sent"). I looked specifically for authentication bypasses and found no authentication logic to bypass. Warning: if a future feature treats the email as identity, it would be an authentication weakness by construction. | n/a | n/a |
| **CWE-501** Trust boundary violation | Backup/restore: `BackupView.importBackup`, `BackupZipper.unzip`, `BackupBundle.restoreBundle` (`:178-328`) | Full read of the restore path; SQL-level reproduction of the gate (`s01_schema_trust_poc.py`); regression test written | **Confirmed Vulnerability** (Medium, S-01) | A foreign SQLite file is validated by integrity digests it carries itself (`:462-488`), `quick_check` (`:201`), version equality (`:211`), and a trigger/view comparison (`:217,331-336`), then swapped in wholesale (`:316`). **Reproduced:** a foreign schema that drops a `CHECK`, adds an expression index and an FTS5 table passes `schemaCode(restored) == schemaCode(db)` and `quick_check`. Reproduction is at the SQL-query level using SQLite 3.45.1 (the vendored version); the Swift code itself was not run. | Medium (CVSS 6.1) | **Implemented 2026-10-22** (full-schema comparison before any statement runs); uncompiled; regression test now asserts the fix |
| **CWE-269** Improper privilege management | HealthKit scope (`HealthKitProvider.swift:35-56,67-100`); location (`PrayerViews.swift`); widget extension DB access | Compared requested permissions with feature need; checked entitlements | **Tested—Not Found** | No roles, so no vertical escalation path exists. Write access to HealthKit limited to 5 types (`writableDomains`, `:67`); location is when-in-use only; `healthkit.access` entitlement empty; no background modes. Observation (Info): the widget extension opens the **whole** database read/write (`AppGroupDatabase.open`) to serve three small intents. Read-purpose string understates HealthKit reads (S-10). | Info | Open (S-10) |
| **CWE-384** Session fixation | None: no sessions, cookies, tokens or server | Grep for session/cookie/token handling (zero); no `URLSession`, `HTTPCookie`, WebView | **Not Applicable** | There is no session to fix. | n/a | n/a |
| **CWE-89** SQL injection | `AlmanacCore` stores (all `db.query/run/execute`), lab CSV import, search | Scanned every non-migration SQL string for interpolation (`sqli_scan.py`) and read each dynamic site; checked `ATTACH`, `PRAGMA`, `LIKE`, `MATCH` | **Tested—Not Found** | Values are bound via `sqlite3_bind_*` (`Database.swift:190-206`). Interpolated fragments are code constants: `Self.columns`, `selectColumns`, `placeholders(n)`, two literal table names (`NightNutritionWindowAssigner.swift:170,181`, `ReligiousFastingService.swift:178`), `HealthSummaryStore` static `spec`s. `ATTACH DATABASE ?` is parameterised (`NutritionReferenceImporter.swift:84`). `LIKE` uses `ESCAPE '\'` (`NutritionCatalog.swift:272`, `RecipeFinder.swift:190`, `LabStore+Reading.swift:66`). No `MATCH`/FTS queries. **Second-order case:** values read back from a *restored* database are never interpolated, only bound. | n/a | n/a (add a lint test) |
| **CWE-120** Classic buffer overflow (and out-of-bounds read/write) | Vendored C: `Sources/CSQLite/sqlite3.c` (3.45.1). First-party unsafe code: `Database.swift`, `Database+Handle.swift` | Inventory of every unsafe Swift API; line-by-line bounds review of `BackupZipper.unzip`; heuristic scan of `sqlite3.c`; CVE look-up (secondary sources). **No fuzzing, no sanitizer build** (no toolchain) | **Potential Vulnerability** (Low) | First-party Swift: unsafe use is confined to the SQLite bridge: `unsafeBitCast` for `SQLITE_TRANSIENT` (`Database.swift:41`), `withUnsafeBufferPointer` + `sqlite3_bind_blob` with matching length (`:202-203`), `UnsafeRawBufferPointer(start:count:)` with `count` from `sqlite3_column_bytes` (`:164-166`, BLOB-typed so no conversion hazard). The zip reader checks every read against `bytes.count` before indexing (`BackupZipper.swift:107-119,128,137,174`), uses 64-bit sums (`:119`) and only STORE entries (`:148`); a malformed archive can at worst **trap** (denial of service), not corrupt memory, because Swift array access is bounds-checked. One DoS: `Int32(bytes.count)` traps for blobs over 2 GiB (`Database.swift:203`). **Vendored C is the open question:** 3.45.1 predates published fixes for memory-safety CVEs (e.g. CVE-2025-6965; see S-05), and S-01 lets an attacker supply a database file for it to parse. Not demonstrated; no exploit shown. | Low | Partly: S-01 change and FTS5/extension removal in; **SQLite upgrade pending** (§8A); S-06 open |
| **CWE-79** Cross-site scripting | None: no `WKWebView`, HTML rendering, `loadHTMLString`, or JavaScript bridge | Grep for web views, HTML, `AttributedString(markdown:)`, `LocalizedStringKey(...)`, `Text(.init(…))`, `NSAttributedString(html:)`; checked tools for HTML generation | **Not Applicable** | All text is rendered with SwiftUI `Text`. The two grep hits for `Text((` (`ProgramSessionView.swift:393`, `DigestionQuickEntryView.swift:155`) pass `String` values, which `Text` renders verbatim. No markup interpreter handles user or database text. Links open in Safari via `Link` (S-18). | n/a | n/a (re-check if a web view or Markdown is added) |

#### 3.2.2 Attention areas you called out

| Concern | What I looked at | Conclusion |
|---|---|---|
| **Authentication bypass** | Whole tree for login, tokens, passcodes, biometrics, registration (`registeredAt`), email gate | No authentication exists, so none can be bypassed (CWE-287 N/A). The nearest thing, the backup email rule, is bypassable by design (restore is ungated, service API unchecked). The real exposure is the **absence** of authentication on critical functions (CWE-306, S-16). |
| **Horizontal privilege escalation** | Single-user store, no user ids. App Group `group.com.almanac.personal` | Not applicable inside the app. Other apps cannot read the container; only code signed by the same team can join the group. |
| **Vertical privilege escalation** | Roles, admin screens, debug modes | No roles. Debug-only launch hooks are `#if DEBUG` (verified at `AlmanacApp.swift:146-171,415-457`). No hidden admin path found. |
| **Session fixation** | Cookies/sessions/tokens | None exist (CWE-384 N/A). |
| **Unsafe command execution** | App, tooling, CI, Xcode project (0 run-script build phases) | None in the app; tooling uses list-form `subprocess`; CI has no attacker-controlled interpolation. |
| **Memory corruption** | Unsafe API inventory, zip/bundle parsers, vendored C | No first-party corruption path found; residual risk is in the vendored C parsing a hostile database (S-01 + S-05). Not fuzzed. |

#### 3.2.3 Additional weaknesses assessed (OWASP and MITRE CWE)

Guidance used, confirmed by search on 2026-10-21 (not by reading the primary pages, which were not fetchable): **OWASP Mobile Top 10 (2024)** M1–M10; **OWASP Top 10:2025** (SSRF now sits under A01 Broken Access Control; new A03 Software Supply Chain Failures and A10 Mishandling of Exceptional Conditions); **2025 CWE Top 25** (CWE-79, 89, 352, 862, 787 lead). Web-only items (CSRF, CORS, cookies) are N/A.

| CWE / OWASP | Status | Evidence |
|---|---|---|
| CWE-22 path traversal | Tested—Not Found in backup/restore (`BackupZipper.swift:182-187`, `BackupBundle.swift:338-356`, symlink test `BackupBundleTests.swift:142`); **Potential** via `graphicPath` (S-19) | |
| CWE-345 / CWE-347 data authenticity (M4/M10) | **Confirmed**: backups carry self-attesting digests, no signature/MAC (S-01) | `BackupBundle.swift:462-488` |
| CWE-311 / CWE-312 cleartext storage (M9) | **Confirmed**: plaintext backups and `.zip` twin (S-02); no explicit file protection (S-03) | |
| CWE-209 error-message exposure (A10:2025) | **Confirmed** (Low): S-17 | `SQLiteError.swift:21-23` |
| CWE-502 unsafe deserialization | Tested—Not Found | `NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self…)` with secure coding (`HealthKitProvider.swift:108,130`); all others are `JSONDecoder` into fixed types (`try?`) |
| CWE-601 open redirect | **Potential** (S-18) | |
| CWE-20 / M4 input validation | Tested—Not Found for lab CSV, numbers (NaN/hex rejected per prior audit; the validators were read, not run), zip, paths; gaps listed in S-01, S-06, S-18, S-19 | |
| CWE-400 / CWE-770 resource exhaustion; CWE-190 integer overflow | **Confirmed** (Low): no size caps, whole-file reads, `Int32(bytes.count)` (S-06) | |
| CWE-367 TOCTOU | Tested—Not Found of consequence: document targets validated, then written (`BackupBundle.swift:254,275,298`); local, single-user | |
| CWE-532 / CWE-200 logging & exposure | Tested—Not Found: no `NSLog`/`os_log`; `print` calls are `#if DEBUG` | |
| CWE-798 hardcoded credentials (M1) | Tested—Not Found (pattern scan, history included) | |
| CWE-829 / CWE-1104 / CWE-494 supply chain (M2, A03:2025) | **Confirmed** (Low): S-05, S-07, S-08, S-13, S-14 | |
| CWE-319 / M5 insecure communication | Not Applicable: no communication | |
| M7 binary protections | Not Tested: no build; Swift/iOS defaults only | |
| M8 security misconfiguration | See S-03, S-04, S-07, S-11 | |
| M6 privacy controls | See §5 and §7 | |
| CWE-352 CSRF, CWE-434 upload, CWE-639 IDOR, CWE-918 | Not Applicable (no web surface, no multi-user data). File *import* is the one upload-like surface: S-06 | |
| CWE-416 / CWE-787 use-after-free / OOB write | Not Tested dynamically; first-party Swift gives none by construction; vendored C untested (CWE-120 row) | |

#### 3.2.4 Safe, isolated testing performed

- **S-01 reproduction**: `/tmp/claude-0/-home-user-AlManac/f1ce3ae9-0fa6-52b3-9e42-fbce2e98a875/scratchpad/poc/s01_schema_trust_poc.py`. Runs only against two temporary SQLite files, no network. Output (SQLite library 3.45.1):

  ```
  quick_check (foreign) : ok
  schemaCode(live)      : []        schemaCode(foreign) : []
  GATE `schemaCode(restored) == schemaCode(db)` passes for the tampered schema: True
  objects the gate never compares that differ: kitchen_recipe_source, planted_expr_idx, planted_fts (+ 5 FTS shadow tables)
  live    rejects non-https url: CHECK constraint failed: url LIKE 'https://%'
  foreign accepts non-https url: YES -> tel:+10000000000
  ```
  **Limits of this test:** it reproduces the *comparison query* and the constraint behaviour, with DDL copied from `Migration062.swift`. It does not run `restoreBundle`, so it does not show the end-to-end swap, and the live app's own schema may contain triggers/views I did not enumerate.
- **Static scans** (scratchpad, not committed): `sqli_scan.py` (SQL interpolation sources).
- **No fuzzing, no sanitizer or TSan runs, no dynamic analysis, no device or simulator testing.**

#### 3.2.5 Regression tests for confirmed vulnerabilities

Only **CWE-501 / S-01** is a *Confirmed Vulnerability*, so it is the only one with a new test:

- `Tests/AlmanacCoreTests/RestoreSchemaTrustTests.swift` (new, untracked): written on 2026-10-21 as a `withKnownIssue` draft that passed while the bug existed. **Since 2026-10-22 the fix is in and the wrappers are removed**: the file now asserts that restore refuses a payload with an extra expression index, an extra view or an altered table, and still accepts an untampered one. **Not compiled or run**; CI is the first check. (Chosen over `XCTExpectFailure`, which does not exist in Linux XCTest.)
- **Not compiled or run.** This environment has no Swift toolchain, so a compile error or an incorrect assumption (e.g. that `sync_anchor.sampleType` exists, which `SyncAnchorStore.swift:38` indicates) is possible. CI is the first real check. Treat it as a draft until CI has compiled it.
- Tests suggested but **not written** (status is Potential, not Confirmed, or they need a device): S-16 intents on a locked phone; S-18 `pageURL` allow-list; S-19 `graphicPath` with `..`; S-17 error text; S-06 size caps; fuzz harnesses for `BackupZipper.unzip` and `openValidBundle`.

#### 3.2.6 Limitations of the CWE assessment

1. No build, no tests, no runtime: every status is based on code reading, search and the one SQL-level reproduction.
2. "Tested—Not Found" is bounded by what I read. I did not read all 57k lines of first-party Swift; searches were targeted at sinks and sources.
3. Vendored C and Adhan were not diffed against upstream (network refused); fuzzing and sanitizers were not possible.
4. The App Intents authentication default and the behaviour of `Bundle.url(forResource:)` with `..` are from memory and untested.
5. OWASP/CWE editions were confirmed through search summaries, not primary pages.
6. Absence of findings is not evidence of security. These are the checks that were possible here.

---

## 4. Backdoor and Suspicious Behaviour Analysis

### 4.1 Confirmed malicious mechanisms
**None found.**

### 4.2 Suspicious or unexplained mechanisms (each with the legitimate explanation)

| Item | Why it looked unusual | Legitimate explanation / assessment |
|---|---|---|
| `Backup requires a valid email` with no server | Collecting an email nobody uses reads like harvesting | Owner request, 2026-10-20 (`CONTEXT.md`). The value is stored locally, never transmitted. **Classified Unnecessary** for privacy purposes (§5), not suspicious. |
| `exit(0)` after restore (`BackupView.swift:~226`) | Abrupt termination | Used to force a reload after the DB file is replaced. Poor UX, not malicious. |
| Test hooks reachable by launch arguments | Could seed data or run intents | `#if DEBUG` only (verified). Not present in Release. |
| `dlopen` and `fork` in `sqlite3.c` | Typical backdoor words | Stock SQLite: `unixDlOpen` (line 44706) is the VFS extension loader and `fork` appears in a PRNG comment (line 38282). `system(`, `popen`, `socket`, `connect`, `getaddrinfo`, `curl_` = 0 hits. |
| `.opencode/` skills, `opencode.json` | Agent-instruction files are a classic prompt-injection vector | All seven skill files and `CONNECTORS.md` were read via targeted greps and size checks; they contain design-review guidance only. No instructions to exfiltrate, fetch, or override rules. (S-08 notes the `npx` launch.) |
| `+dirty` seed DB build | Unreproducible binary | Process hygiene (S-13). Structural checks passed: no triggers or views. Row-level content was not audited. |
| ~188/204 commits by AI agents | Reduced independent review | Provenance observation; no evidence of misconduct. |

**Not verified:** that `sqlite3.c` and `Sources/Adhan/*` match upstream byte for byte. Offline checks only: `SQLITE_SOURCE_ID` string present and consistent with 3.45.1, size and line count plausible (255,680 lines), no network/process APIs, Adhan imports only `Foundation` and has no network, process or `base64` use. A real diff against sqlite.org and the pinned Adhan commit is still needed (§9).

---

## 5. Privacy and Tracking Findings

### 5.1 Tracker / SDK inventory

| Mechanism | Present? |
|---|---|
| Analytics, crash reporting, attribution, ad SDKs | **None found** (grep for Firebase, Crashlytics, Sentry, Amplitude, Mixpanel, AppsFlyer, Adjust, Segment, PostHog, Datadog, etc.: no hits in first-party code) |
| Third-party Swift packages | **None** (0 remote package references) |
| Advertising / device identifiers (IDFA, IDFV, `AppTrackingTransparency`) | **None** |
| Persistent identifiers | Random UUIDs for local row ids and temp folders only |
| Fingerprinting | None. "fingerprint" hits are lab-report content hashes for de-duplication (`LabStore.swift`) |
| AI / model-provider calls | **None** |
| Background sync / uploads | **None** (no background modes, no network code) |
| Cookies / WebViews | **None** |

### 5.2 Data-flow classification

All data below is stored **only on the device** (SQLite in the App Group container), unencrypted by the app, protected by iOS defaults (S-03), with deletion only by deleting the app or editing records in the UI. No third-party recipient exists unless the user shares a backup.

| # | Data category | Source → Destination | Trigger | Encryption | Retention / deletion | Needed for core function? | Classification |
|---|---|---|---|---|---|---|---|
| 1 | Health logs (water, food, training, body composition, digestion, urination, mood, soreness, supplements, caffeine) | User → SQLite | Manual entry | iOS file protection only | Until user deletes / app removed | Yes | **Essential** |
| 2 | HealthKit samples (sleep, steps, resting HR, HRV, energy, weight, body fat, lean mass, waist, workouts) | HealthKit → SQLite; five types written back | User taps Connect; system permission | iOS only | As above | Yes (feature is opt-in) | **Optional and justified** |
| 3 | Lab results (report text, values, ranges, specimen, LOINC) | User/CSV → SQLite | Manual / paste | iOS only | As above | Yes | **Essential**; special-category health data |
| 4 | Profile: name, DOB, sex, height, blood type, allergens | User → SQLite | Manual | iOS only | As above | Calorie targets, allergen filtering | **Essential/Optional** per field |
| 5 | **Email** | User → SQLite (and into every backup) | Required to enable backup creation | iOS only | As above | **No** (no message is ever sent; gate is UI-only) | **Unnecessary** |
| 6 | Precise location (lat/lon doubles) | CoreLocation → `PrayerSettingsStore` | "Use current location", then passive refresh on foreground when authorised | iOS only | **Persisted indefinitely, full precision as far as I found** | Prayer times and qibla need ~city-level precision only | **Optional and justified**, over-retained |
| 7 | Religious practice (prayer settings and completion, religious-fast schedule, suhoor/iftar notifications) | User/derived → SQLite → notifications | Opt-in features | iOS only | As above | Yes for those features | **Optional and justified**; special-category data (GDPR Art. 9; PDPL "sensitive") |
| 8 | Shift schedule, sleep episodes, readiness scores | User/derived → SQLite | Manual/derived | iOS only | As above | Yes | **Essential** |
| 9 | Backups (everything above + documents) | SQLite → `.almanac-backup` and `.zip` → Files/Share | User taps Create/Share | **None** (S-02) | `.zip` twin never deleted | Optional feature | **Optional and justified**, but unsafe as built |
| 10 | Notification text (names of supplements, prayer/fast labels) | Planner → OS | Scheduled | OS | OS-managed | Reminders | **Optional and justified** (lock-screen exposure, S-09) |
| 11 | External links (attribution, recipe source) | App → Safari | User tap | TLS (Safari) | n/a | Attribution requirement | **Optional and justified** |

### 5.3 Recommended removals / minimisation

1. **Email (row 5):** remove the requirement, or make it genuinely optional and exclude it from backups. As built, it is data minimisation noise with no purpose.
2. **Location (row 6):** round stored coordinates to ~2 decimals (≈1 km) or store city only; delete the stored fix when "manual city" is chosen. I confirmed no rounding in `PrayerSettingsStore`; `PrayerTimeEngine.applyLocationUpdate` was not read exhaustively.
3. **Backups (row 9):** encrypt, and delete the `.zip` twin after sharing.
4. **Third-party emails in `exercise-library.json` (S-12).**
5. **Health purpose string and privacy manifest (S-10, S-11).**

---

## 6. Dependency and Licence Risks

Full inventory: `SBOM.cdx.json` (CycloneDX 1.5, hand-compiled; no generator was available).

### 6.1 Code dependencies

| Component | Version | Licence | Risk |
|---|---|---|---|
| SQLite (vendored) | 3.45.1 | Public domain | Outdated (S-05); integrity vs upstream unverified |
| adhan-swift (vendored) | commit `0bc10007…` | MIT (notice present in `Sources/Adhan/LICENSE`) | Diff vs upstream unverified; MIT notice must ship in the app attributions |
| Fraunces, Almarai fonts | n/a | OFL-1.1 (licence texts in repo) | Fine; OFL forbids selling the fonts alone |
| Remote Swift/npm/pip packages shipped | **None** | — | — |

Known-vulnerability scanning (OSV/Grype/Trivy) **was not possible**: none of the scanners were installed and egress to vulnerability databases is restricted. The only known-CVE assessment is for SQLite (S-05), from a secondary source.

### 6.2 Data and content licences (the larger obligation)

| Source | Licence (per `Attribution.swift`; not independently verified) | Obligation / concern |
|---|---|---|
| Everkinetic, workout-guide art | CC BY-SA 4.0 | Attribution; **share-alike** on modified images (they are modified: scaled) |
| wger exercise data | CC BY-SA 3.0 / 4.0, CC BY 4.0, CC0 per exercise | Per-exercise credit; share-alike |
| free-exercise-db text + photos | Unlicense | Photo provenance unclear; **owner accepted the risk** (`Attribution.swift` comment) |
| USDA FDC | CC0 | None |
| Open Food Facts | ODbL 1.0 (DB) + DbCL (contents) | Adapted database is itself released under ODbL (a share-alike obligation the repo documents) |
| CIQUAL, CoFID, AFCD | CC BY 4.0 / Etalab 2.0 / OGL v3 / CC BY 4.0 | Attribution notices |
| LOINC | LOINC licence | Verbatim notice required; owner accepted 2026-10-16 |
| Wikibooks recipes | CC BY-SA 4.0 | Share-alike on the derived recipe set |
| **Bristol Stool Form Scale wording** | **"No licence identified"** (the repo's own entry says so) | Shipping published wording without a licence; open item in `CONTEXT.md` |
| TheMealDB | **Not bundled** (gate deliberately closed; no data in `Sources/` or `Native/`) | Good: bundling terms were never granted |
| **This repository itself** | **No `LICENSE` file** | Default is "all rights reserved". Authors: the owner (16 commits) and AI agent sessions (188). If you are the owner, state a licence; if not, you need permission. Share-alike data constrains how the combined work can be relicensed. |

---

## 7. Compliance Gap Assessment

> These are **technical control checks, not legal conclusions.** Applicability depends on who the users are, where they are, and whether you distribute through the App Store, none of which the repository establishes. Legal review is required.

### 7.1 Saudi PDPL (assuming Saudi users or a Saudi controller)

| Control | Evidence | Gap / status |
|---|---|---|
| Sensitive data (health, religious belief) identified | Labs, vitals, prayer, religious fasting stored (§5.2) | Recognised in design docs? Not found in a privacy policy (none exists in repo) |
| Data minimisation | Local-only; no third parties | **Gaps:** email (row 5), full-precision location (row 6) |
| Lawful basis / consent | Permission prompts exist for HealthKit, location, notifications | No in-app privacy notice or consent record; no privacy policy |
| Transparency (privacy notice) | None in repo | **Gap** (needed before release) |
| Security safeguards | See S-01…S-03 | Backups unencrypted; no app lock |
| Cross-border transfer | None by the app; user-initiated backup share is the user's act | Operational review if you add any server |
| Data-subject rights (access, deletion, portability) | Backup = export; deletion = app removal / manual edits | No in-app "delete everything" action found |
| Breach notification, DPO, records of processing | n/a for a no-server personal app | Operational/legal review if distributed commercially |

### 7.2 GDPR (if EU/UK users)

| Control | Status |
|---|---|
| Art. 9 special-category data (health, religion) | Processed locally. Explicit consent mechanics rely on OS prompts; no app-level record |
| Art. 5(1)(c) minimisation | Gaps as above (email, location precision) |
| Art. 25 privacy by design/default | Strong baseline (no server, no SDKs); weak on backup protection |
| Art. 32 security | Unencrypted backups; no explicit file protection |
| Art. 13 notice | No privacy policy in repo |
| Art. 20 portability | Backup is a SQLite container, not a documented open export format (CSV/JSON export not found) |
| Art. 17 erasure | No single "erase all data" control found |
| Controller status | If distributed, the publisher is likely a controller for nothing it receives (no data reaches it); confirm with counsel |

### 7.3 Platform rules (Apple)

| Item | Status |
|---|---|
| Privacy manifest (`PrivacyInfo.xcprivacy`) | **Missing** (S-11) |
| App Privacy "nutrition label" | Can answer "Data Not Collected" if the claim stays true; needs re-check on every change |
| HealthKit purpose strings | Incomplete (S-10); HealthKit data must not be used for advertising/data mining (not done) |
| Location purpose string | Present and accurate for the feature |
| Health data in iCloud | No iCloud entitlement (good for the claim; also means no sync) |
| Ending the process with `exit(0)` | May draw review attention (S-06) |

### 7.4 Items requiring legal or operational review

Privacy policy text; PDPL/GDPR applicability; whether health/religious data requires registration or DPIA in the target market; repository and data licences (§6); medical-device classification of readiness, allergen and lab-interpretation features (the code withholds claims it cannot support, but regulatory classification is a legal question).

---

## 8. Remediation Roadmap

*Proposed only. Nothing below has been implemented. Awaiting your authorisation.*

Effort: S ≤ ½ day, M ≈ 1–3 days, L ≈ 1 week+.

### P0 — immediate blockers (before any release, fork or publication)

| # | Change | Why | How | Breakage risk | Verify | Effort |
|---|---|---|---|---|---|---|
| P0-1 | Add a repo `LICENSE`; resolve Bristol-scale wording and free-exercise-db photo provenance | S-15 | Owner decision; replace the Bristol text with original wording or obtain permission; replace unclear photos | Content change in digestion screens | Legal sign-off; attribution page updated | S–M |

### P1 — must resolve before release

| # | Change | Depends on | Breakage / compat | Verify | Effort |
|---|---|---|---|---|---|
| P1-1 | Harden restore: full `sqlite_master` comparison (or row-copy restore); `trusted_schema=OFF` and defensive mode for foreign DBs; open foreign DBs read-only first (S-01) | — | Backups from older builds with benign index differences would be refused; keep the schema-version gate | New refusal tests (extra index, altered CHECK, FTS5 table) | M |
| P1-2 | Re-vendor current SQLite, verify against sqlite.org SHA3; drop FTS5; add `SQLITE_OMIT_LOAD_EXTENSION` (S-04, S-05) | Network access to sqlite.org | Rebuilds the DB engine; run all 1.5k tests plus migration fixtures | Full CI; `sqlite_version()` assertion | M |
| P1-3 | Encrypted backups (passphrase → key derivation → authenticated encryption), delete the `.zip` twin after share, exclude `Backups/` from device backup (S-02, S-03) | Owner reverses "unencrypted for now" | New backup format version; old plaintext bundles must still import | Ciphertext test; wrong-passphrase test | L |
| P1-4 | Add `PrivacyInfo.xcprivacy`; fix HealthKit purpose string (S-10, S-11) | — | None | Xcode archive validation | S |
| P1-5 | Privacy policy and in-app notice; "erase all data" action; data export in an open format (§7) | — | New UI | Manual + UI test | M |
| P1-6 | Remove or make optional the email requirement and exclude it from backups (§5) | Owner decision (it was an explicit request) | Changes an owner-requested rule | UI test updates (`backup-needs-email`) | S |

### P2 — important hardening

| # | Change | Effort |
|---|---|---|
| P2-1 | Round/limit stored coordinates; clear when manual city chosen (§5) | S |
| P2-2 | Explicit file-protection class on DB and container; optional Face ID app lock (S-03) | M |
| P2-3 | Lock-screen privacy option for notifications (S-09) | S |
| P2-4 | CI: pin actions to SHAs, `permissions: contents: read`, pin/hash Python deps, digest-pin the image (S-07) | S |
| P2-5 | Cap import sizes, stream large reads, replace `exit(0)` (S-06) | M |
| P2-6 | Replace contributor emails in `exercise-library.json` (S-12) | S |
| P2-7 | Reproducible seed DBs: rebuild from a clean commit, record hashes in CI; pin OFF export hash (S-13, S-14) | M |
| P2-8 | Verify vendored SQLite/Adhan against upstream (§9) | S (needs network) |

### P3 — optional

Add gitleaks/Semgrep/OSV to CI; generate the SBOM automatically; lockfile for `xcodebuildmcp` (S-08); remove dead `LabReportFixture.swift` from Release via build setting; add an independent human code review of the backup/restore and HealthKit paths.

**Dependencies between fixes:** P1-2 should precede P1-1's regression tests being finalised; P1-3 and P1-1 both change the backup format, so do them together; P1-5 depends on P1-6 and P1-3 for accurate wording.

---

## 8A. Remediation applied (P0 and P1, 2026-10-22)

Authorised by the owner on 2026-10-22, with four decisions: licence **all rights
reserved**, Bristol wording **rewritten**, exercise photos **kept (risk re-confirmed)**,
sharing **requires a passphrase**. Recorded in `CONTEXT.md` ("Security audit
remediation, P0 and P1") and `docs/implementation-status.md`.

> **Nothing here has been compiled, run or reviewed by a second person.** There is no
> Swift or Xcode toolchain in the environment, so no test below has ever executed.
> What I did instead: bracket-balance checks on all 26 touched Swift files (with a
> negative control), a Python mirror of the Arabic-string checks for both catalogs
> (no missing or mismatched entries), validation of the manifest and string-catalog
> JSON, and a self-checking script for the Xcode project edits (each new id defined
> once and referenced exactly where intended). Those catch typos and missing
> translations. They do **not** catch type errors, API misuse or wrong logic. Treat
> every item as "written, awaiting CI".

| Item | Status | What changed | Verification that exists | Still open |
|---|---|---|---|---|
| **P0-1** licence | Done (file) | `LICENSE`: all rights reserved, third-party material excluded and listed | None needed | Confirm the copyright holder's legal name and year; legal review |
| **P0-1** Bristol wording | Done | New names and summaries in `DigestionStore.swift`, Arabic table, attribution entry now credits the scale's origin and says nothing is reproduced, 2 UI tests and 2 docs updated | Core string checks (Python mirror) | Arabic is a draft for a native speaker. Rewording lowers the risk; it is **not** a legal clearance |
| **P0-1** exercise photos | Recorded | Risk re-confirmed in `Attribution.swift` and `CONTEXT.md` | n/a | Risk unchanged; ~19 MB of images of unestablished provenance still ship |
| **P1-1** restore hardening (S-01, CWE-501/94) | Implemented | `BackupBundle.schemaObjects(of:)` compares every non-`sqlite_` object before any statement runs against the payload; foreign-open failures become `corruptBundle` | `RestoreSchemaTrustTests` (4 cases) written; existing restore tests re-read for compatibility (error wording kept: "Almanac database", "triggers") | Compile and run. A backup from a build whose migrations were edited in place without a version bump would be refused (documented) |
| **P1-2** SQLite (S-04, S-05, CWE-120) | **Partly** | FTS5 removed, `SQLITE_OMIT_LOAD_EXTENSION` added (`Package.swift`); `docs/vendored-sqlite.md` has the upgrade steps | Nothing else in the code or seed DBs used FTS5 (grep + read-only inspection) | **The version upgrade is not done**: `sqlite.org` is unreachable from this environment, and I did not hand-edit a 9 MB C file. Needs someone with access, then the SHA3 check in the doc |
| **P1-3** encrypted shared backups (S-02) | Implemented | `EncryptedBackup` (format and policy, core), `CryptoKitBackupCipher` (app: AES-256-GCM, PBKDF2-HMAC-SHA256, 600,000 rounds), share and import sheets, `BackupView` rewrite; no plaintext twin; Backups folder excluded from device backups; old `.zip` twins deleted on open | `EncryptedBackupTests` (13 cases, stand-in cipher) test the envelope; `PhoneMigrationUITests` share test | **The real cipher has no automated test.** Device check 4 and an independent review of `BackupCrypto.swift` are needed. Local backups remain unencrypted by design. The database's own file-protection class is unchanged (S-03 partly open) |
| **P1-4** privacy manifest and purpose string (S-10, S-11) | Implemented | `PrivacyInfo.xcprivacy` wired into the project; purpose strings name every type read and written | Manifest parses; project edit self-checked | Xcode archive validation. The purpose strings are English only (no `InfoPlist.xcstrings`) |
| **P1-5** privacy notice, erase, export (§7) | Implemented | `PrivacyNoticeView`, `docs/PRIVACY.md` (draft), `DataExport`, `LocalDataEraser`, `AppDataEraser`, Settings rows | `DataExportTests`, `LocalDataEraserTests`, `PrivacyUITests` (non-destructive) | Legal review of the notice; fill the bracketed publisher details; the app-side erase steps (reminders, defaults, quit) are a device check; the export is not encrypted by design and says so |
| **P1-6** email requirement | Implemented | `mayCreateBackup` removed; field kept as an optional value nothing uses; unit and UI tests rewritten | Updated tests | The field is still collected data with no purpose; removing it entirely is the cleaner option |

Findings affected: S-01, S-02, S-04, S-10, S-11 addressed; S-03 partly (device-backup
exclusion done, file-protection class not set); S-05 **not** addressed (version);
S-15 partly (licence, Bristol; photos accepted). **S-06, S-07, S-08, S-09, S-12,
S-13, S-14, S-16, S-17, S-18 and S-19 are P2/P3 and untouched.**

**Recommendation status.** Unchanged ("suitable after specified fixes") until CI
shows the changes compile and pass and the real cipher has been checked on a device.

---

## 9. Verification and Testing

### 9.1 What was actually done

| Activity | Result |
|---|---|
| Full file inventory (1,780 tracked files), size and authorship statistics | Done |
| Read in full: `Package.swift`, `ci.yml`, `opencode.json`, `.xcodebuildmcp/config.yaml`, entitlements, widget `Info.plist`, `AppGroupDatabase.swift`, `BackupZipper.swift`, `BackupService.swift`, `BackupBundle.swift`, `BackupView.swift`, `WidgetIntents.swift`, `NotificationScheduler.swift`, `ProfileStore.swift` (head), relevant parts of `PrayerViews.swift`, `HealthKitProvider.swift`, `AlmanacApp.swift`, `TrendsView.swift` | Done |
| Pattern scans of all first-party Swift: network APIs, URL literals, telemetry SDK names, dynamic execution, location/camera/mic/photos/pasteboard/biometrics, logging, storage, file protection, SQL interpolation | Done |
| Secret and PII regex scan over all tracked text **and** git history (204 commits, all refs) | Done; no secrets, found third-party emails (S-12) |
| Offline heuristics on `sqlite3.c` (source id, size, risky-API counts, URLs) and Adhan imports | Done |
| Read-only structural check of both bundled SQLite files (triggers/views/tables/meta) | Done |
| Review of Python build tools for network and exec behaviour | Done |
| Review of `.opencode/` agent skills for hidden instructions | Done |
| CVE look-up for SQLite | Partial (secondary sources only; `sqlite.org` unreachable) |
| Isolated SQL-level reproduction of S-01 (`poc/s01_schema_trust_poc.py`, SQLite 3.45.1, temp files only) | Done: gate bypass reproduced (§3.2.4) |
| Per-CWE assessment of the 14 mandatory CWEs + OWASP/CWE additions | Done, static + one reproduction (§3.2) |
| Regression test for the one Confirmed vulnerability | Written, **not compiled or run** (§3.2.5) |
| SBOM | `SBOM.cdx.json`, hand-compiled |

### 9.2 What was NOT done (and why)

| Not done | Reason | Consequence |
|---|---|---|
| Build, run or `swift test` / `xcodebuild test` | No Swift or Xcode toolchain in the environment | **No behaviour was observed.** All findings are from reading code. The test suites (1,209 `@Test`, UI tests) were not executed by me |
| Runtime and network verification (Phase 5): traffic capture, DNS, idle behaviour, permission flows | No device/simulator | "No network access" is established by absence of code, not by observation. A precompiled framework or a build-setting trick would not show up in my greps (none found in `project.pbxproj`, but binary resources were not disassembled) |
| Byte-level diff of `sqlite3.c` and `Sources/Adhan` against upstream | Egress to `sqlite.org` / `codeload.github.com` refused by network policy (HTTP 403). I did not attempt to work around that | Tamper-freedom of ~270k lines of vendored code is **unverified** |
| SCA/SAST/secret-scanner tools (OSV, Grype, Trivy, Semgrep, gitleaks, Syft) | None installed | Findings rest on manual review and regex |
| Review of every line of `Sources/AlmanacCore` (38k lines) and `Native/Almanac` (19k lines) | Scope/time; I prioritised trust boundaries and grep-able risk classes | Residual risk of logic bugs in unread code (e.g. unit conversion, lab interpretation, readiness) |
| Content audit of the 11 MB seed DBs, 30 MB of images, 800 KB exercise JSON | Binary/large data | Only structure and a PII grep were checked |
| Concurrency testing (app vs widget on one DB) | No runtime | Medium confidence |
| Legal analysis | Out of scope for a code audit | §7 is a checklist only |

### 9.3 Residual risk
Low probability of intentional malicious code in first-party sources I read; **moderate uncertainty** over the unread remainder and the unverified vendored code; **real, confirmed** privacy exposure via plaintext backups; legal exposure via missing licences. This report does not claim the code is free of vulnerabilities.

---

## 10. Final Recommendation

> **Suitable for repurposing after specified fixes.** (Confidence: **medium-high** that no intentional malicious functionality exists in what I read; **medium** on overall readiness, because nothing was run and vendored code was not diffed.)

**Evidence for.** Zero network code and zero third-party runtime dependencies in the shipped app. Parameterised SQL throughout. A restore path that has been hardened against traversal, overflow and trigger injection. Debug hooks gated by `#if DEBUG`. Explicit provenance and attribution machinery. A transparent decision log in `CONTEXT.md`.

**Evidence against / conditions.** The backup trust model (S-01, S-02), the old SQLite (S-05), the missing licence and licence gaps (S-15), the missing privacy manifest and notice (S-11, §7), and the lack of any runtime verification. The rebuild-instead options were not warranted: the weaknesses sit in a small number of well-bounded components (backup/restore, licensing, packaging), not in the architecture.

---

## Completion Summary

1. **Actually inspected:** the whole tracked tree by inventory and grep; the backup, import, widget, notification, location and HealthKit code and build/CI/config files by direct reading; git history for secrets; both seed databases structurally; `sqlite3.c` and Adhan by offline heuristics.
2. **Actually tested:** the app and its tests were never built or run. Static checks, plus one isolated SQL-level reproduction of S-01 against SQLite 3.45.1 (§3.2.4). One regression test was written for the only Confirmed vulnerability; it has **not been compiled**.
3. **Found:** no malicious functionality or telemetry; 19 findings (§3), none Critical or High; the main ones are S-01, S-02, S-05 and S-15. All 14 mandatory CWEs are assessed in §3.2: one Confirmed (CWE-501), four Potential (CWE-94, 862, 306, 120), five Tested—Not Found (CWE-78, 77, 863, 269, 89) and four Not Applicable (CWE-918, 287, 384, 79).
4. **Uncertain:** vendored-code integrity; runtime behaviour; unread first-party code; seed-data content; legal applicability of PDPL/GDPR.
5. **Repurposing advisable?** Yes, after the P0 and P1 items.
6. **Prioritised plan:** §8.
7. **Evidence needed to establish readiness for redevelopment:** (a) green CI log of `swift test` and the iOS UI suite on a pinned commit; (b) a verified diff of `sqlite3.c` (or a re-vendored copy with a checked hash) and `Sources/Adhan`; (c) a simulator or device network capture showing zero outbound connections across install, launch, idle, backup, restore and HealthKit connect; (d) regression tests for each S-01 refusal case and for backup encryption; (e) an SCA/secret scan report from OSV/gitleaks (or equivalent) on the final tree; (f) a licence decision and a clean attribution review; (g) an Xcode archive validation including the privacy manifest; (h) CI compiling and passing `RestoreSchemaTrustTests`, then the S-01 fix and removal of its `withKnownIssue` wrappers; (i) an on-device check of S-16 (intents from a locked phone); (j) a fuzz/ASan run of `BackupZipper.unzip` and `restoreBundle`.

---

## Phase 8 — Standing Protocol

This audit is complete as far as Phase 7, **including the mandatory CWE assessment (§3.2): every one of the 14 listed CWEs has an explicit status, evidence and limitations. That is completeness of *coverage*, not a claim of security.** The limitations in §3.2.6 and §9.2 still apply. **I am stopping here and will wait for your feature requirements.** For each feature you propose I will follow the protocol in your brief (behaviour, affected components and data flows, architecture, threats, privacy, compliance, complexity, tests, and how the design avoids reintroducing S-01…S-15) and present a plan for approval before editing any code. After any authorised implementation I will re-verify that the fixes still hold, that no tracker or external data flow has appeared, and that the security and privacy tests pass.
