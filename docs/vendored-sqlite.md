# Vendored SQLite — status and how to update it

`Sources/CSQLite/sqlite3.c` and `include/sqlite3.h` are the public-domain SQLite
amalgamation, vendored so the Linux core and the iOS app compile against the same
SQLite.

| | |
|---|---|
| **Version in the tree** | 3.45.1 (`SQLITE_SOURCE_ID 2024-01-30 16:01:20 e876e51a0ed5c5b3126f52e532044363a014bc594cfefa87ffb5b82257cc467a`) |
| **Upgrade status** | **Pending (audit P1-2).** The security audit (`SECURITY_PRIVACY_AUDIT.md`, S-05) recommends moving to the current stable release. It could not be done from the audit environment because `sqlite.org` is not reachable from it. |
| **Compile options** | `Package.swift`, target `CSQLite`. FTS5 was removed and `SQLITE_OMIT_LOAD_EXTENSION` added (S-01/S-04/S-05). |

## Why this matters

A restored backup is a SQLite file the app did not write. SQLite parses it, so its
own memory-safety fixes matter more here than in an app that only opens files it
created. Restore also refuses any schema the migrations do not define
(`BackupBundle.swift`, `schemaObjects(of:)`), which narrows what a hostile file can
make SQLite do, but does not replace staying current.

## Updating (do this on a machine that can reach sqlite.org)

1. Pick the current release from <https://www.sqlite.org/download.html> and download
   the **amalgamation** zip (`sqlite-amalgamation-<NNNNNNN>.zip`).
2. **Verify it.** The download page lists a SHA3-256 for each file. Check it:

   ```
   openssl dgst -sha3-256 sqlite-amalgamation-<NNNNNNN>.zip
   ```

   The two values must match exactly. Do not skip this: it is the only evidence that the
   copy is the upstream one.
3. Replace `Sources/CSQLite/sqlite3.c`, `include/sqlite3.h` and `include/sqlite3ext.h`
   with the three files from the zip, unmodified.
4. Update the version, source id and date in the table above.
5. `swift build && swift test`, then the Xcode build and UI suite (CI does both).
   Pay attention to `MigrationFixtureTests`, `BackupBundleTests` and
   `RestoreSchemaTrustTests`.
6. Commit the three files and this document together, so the hash and the files cannot
   drift apart.

## What was checked on the copy in the tree (offline, 2026-10-21)

- `SQLITE_VERSION`, `SQLITE_VERSION_NUMBER` and `SQLITE_SOURCE_ID` agree with 3.45.1.
- No `socket`, `connect`, `getaddrinfo`, `popen`, `exec*` or `curl_` calls in `sqlite3.c`.
- `dlopen` appears once, in the stock unix VFS extension loader, which
  `SQLITE_OMIT_LOAD_EXTENSION` now compiles out.

Not checked: a byte-for-byte comparison with the upstream file. That needs step 2 above.
