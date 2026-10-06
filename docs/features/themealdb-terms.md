# TheMealDB — what the terms permit (Kitchen build-out, step 0)

**Checked 2026-10-06. Result: NOT VERIFIED, so the gate is closed.** No TheMealDB
data is imported, and `tools/` has no import tool for it.

## What was asked

The owner chose (2026-10-06) to import TheMealDB recipes into Kitchen **if its
terms permit bundling and redistribution**. Step 0 of the handoff is a gate: from
primary sources only, report what the current terms permit for

1. bundling the data in an app,
2. redistribution,
3. attribution wording,
4. commercial use,

and whether `docs/attribution-requirement.md` needs an entry. If the terms do
not permit bundling, the import (step 5) is skipped and nothing is imported.

## What happened

The session ran in a cloud container whose network policy blocks the primary
source. Every route to it was refused by the egress proxy with HTTP 403:

| Tried | Result |
|---|---|
| `https://www.themealdb.com/api.php` (curl, through the session proxy) | 403, policy denial |
| `https://themealdb.com/terms_of_use.php` (curl) | refused |
| `https://www.themealdb.com/api.php` (web-fetch tool) | "blocked by the network egress proxy" |
| Internet Archive snapshot of `terms_of_use.php` | refused |
| archive.ph | refused |

A web search found the terms' address — `https://www.themealdb.com/terms_of_use.php`
— and third-party pages that summarise or mirror it (a terms-tracking site, and
client libraries whose own code is Apache-2.0). None of those is the primary
source, and a client library's licence says nothing about the data it fetches.
They were not used to decide anything.

**So none of the four questions has an answer here, and the gate stays shut.**
"Could not check" is treated as "does not permit", because bundling recipes the
terms forbid is the one outcome that cannot be undone after it ships.

## What the next check needs to establish

Read `https://www.themealdb.com/terms_of_use.php` and `https://www.themealdb.com/api.php`
directly, note the date on the terms, and answer:

- **Bundling.** May the recipe data and images be stored in, and shipped
  inside, an app, rather than fetched live? Is a cache allowed, and for how long?
- **Redistribution.** May the data be redistributed to every install (which is
  what bundling is — `LicenceGroup.redistributable`'s reasoning)?
- **Commercial use.** Is use in an app permitted, and does it need a paid or
  supporter API key rather than the public test key?
- **Attribution.** Exact wording and placement required, if any.
- **Per-recipe rights.** TheMealDB records carry their own source and image
  fields; check whether the terms grant rights over the recipe text and images,
  or only over the database.

If the answers permit bundling: add an entry to `docs/attribution-requirement.md`
and `AttributionCatalog`, then build step 5 (`tools/` import through the
ingredient table — see `docs/features/kitchen.md`). If they do not, tell the
owner: Kitchen keeps working over his own dishes, and his own regional food data
remains the plan he chose for food data.

## Serving counts (needed by step 2)

The handoff says TheMealDB records carry no serving count. That could not be
checked against the API either, for the same reason. How an imported recipe gets
a serving count is recorded as an unconfirmed decision in `CONTEXT.md` (Kitchen,
2026-10-06), so it is settled before any import exists.
