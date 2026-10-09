# TheMealDB — what the terms permit (Kitchen build-out, step 0)

**Checked 2026-10-06 and 2026-10-07 from a cloud container (could not reach the
site), then read from the primary pages on the iMac on 2026-10-08. Result:
permitted for a paid supporter, with bundling and per-recipe rights still not
granted in so many words, so the gate stays closed.** No TheMealDB data is
imported, and `tools/` has no import tool for it. §"Primary-source check,
2026-10-08" at the end has the answers and what the owner has to decide.

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

## Re-check, 2026-10-07

The primary pages are still unreachable from the cloud container: `curl` to
`www.themealdb.com/terms_of_use.php`, `/api.php`, the bare domain and the
Internet Archive all got `CONNECT tunnel failed, response 403`, and the
web-fetch tool reported `EGRESS_BLOCKED` for `www.themealdb.com` and for the
terms-tracking mirror. The proxy's status endpoint showed no per-host
exception to ask for.

A web search **restricted to `themealdb.com`** did return summaries of the
site's own FAQ, API page and terms. They are a search engine's paraphrase of
those pages, not the text, so nothing below is quoted, and none of it has a
date beyond one result's "last updated 7 January 2025" for the terms.

| Question | What TheMealDB's own pages say (paraphrased by search) | Settled? |
|---|---|---|
| Storing / copying the data | Content returned by the API may be scraped, copied and modified, provided it comes through the official endpoints; scraping the website itself is not allowed. | Likely yes, via the API |
| Bundling in a shipped app | Not addressed directly. Follows from the row above only if "copy" covers redistributing the copy to every install. | **No** |
| App Store release | An app may not be published to an app store unless its developer is a paid supporter. The free test key `1` is for development and education. | Yes: a paid key is required |
| Commercial use | A commercial app is expected to sign up on a commercial supporter tier. | Yes: a tier is required |
| Attribution wording | Nothing found. | **No** |
| Rights over each recipe's text and images | Nothing found. Many records name an outside `strSource`; the database cannot grant rights it does not hold. | **No** |

**What this means for v1.** Even read generously, an import needs a paid
supporter key (an owner's decision, with a cost), and leaves bundling,
attribution and per-recipe rights open. Two of those are the questions that
decide whether shipping is allowed. The rule from 2026-10-06 stands: could not
confirm counts as not permitted. **Kitchen's v1 recipes are the owner's own
dishes**, which already work end to end; the import (step 5) stays unbuilt.

**To reopen it.** From a machine that can reach the site (the iMac), read
`terms_of_use.php`, `api.php` and `faq.php`, record the date and the exact
wording for the four questions above, and decide on the supporter key. If it
permits bundling: an entry in `docs/attribution-requirement.md` and
`AttributionCatalog`, then step 5. The import itself also needs a network that
reaches the API, which these containers do not.

Sources consulted (search results only, not fetched):
`https://www.themealdb.com/terms_of_use.php`, `https://www.themealdb.com/faq.php`,
`https://www.themealdb.com/api.php`, `https://www.themealdb.com/docs_api_guide.php`.

## Primary-source check, 2026-10-08

Read directly from the iMac, in the browser: `terms_of_use.php` (headed "Last
updated: 01/07/2025" — the page does not say whether that is 1 July or 7
January), `api.php`, `faq.php`, and the site's own agent guide at `/AGENTS.md`.
Paraphrased, not quoted; read the pages for the exact text before relying on a
detail.

| Question | What the pages say | Settled? |
|---|---|---|
| Storing / copying the data | Content returned by the API may be scraped, copied and modified, provided the official endpoints are used; scraping the website is not allowed; copyright and trademark notices may not be removed or altered. | Yes, via the API |
| Bundling in a shipped app | Not stated. "Copy" is granted; shipping a copy inside every install is not named, and the terms separately bar reselling the API without permission. | **No** |
| Redistribution | Same gap as bundling. Nothing grants it; the reselling clause is the nearest text. | **No** |
| App Store release | The free key `1` is for development and education only; an app may not be published to an app store unless the developer is a paid subscriber. | Yes: paid |
| Commercial use | Allowed, but the FAQ expects a commercial supporter tier on Patreon. Paid use also has a rate limit; the FAQ says the API itself has no limits. | Yes: a tier is required |
| Attribution | Paid use must mention TheMealDB as the data source. The site's agent guide suggests this line: `Recipe data and imagery: TheMealDB (https://www.themealdb.com/)`. Artwork should link back to the site where appropriate. | Yes |
| Per-recipe rights | The terms bar using third-party content in the API without the owner's permission. Most artwork is user-created; each image carries a `strCreativeCommons` tag to check. Many records name an outside `strSource`. The database cannot grant rights over text or images it does not hold. | **No** |
| Record shape | Up to 20 `strIngredientN` / `strMeasureN` pairs per meal, no serving count. The free key lists at most 100 items; the paid key lists the whole database. | Yes |

**What this settles.** The 2026-10-07 table's "Attribution wording: nothing
found" and "App Store release: paid key required" are now confirmed from the
source, and the attribution line is known. **What it does not settle** is the
one thing the gate asks: whether a copy of the data may ship inside the app.
The terms neither grant nor forbid it, and could-not-confirm still counts as
not permitted.

**The owner's options**, in the order that costs least:

1. **Ask.** One email to `thedatadb@gmail.com`: may a paid-tier app ship a
   snapshot of the recipe data and the images it needs, and who owns the rights
   to recipe text and images where `strSource` names someone else. A written
   yes closes the gate; the answer should be filed here with its date.
2. **Do not ship it.** Kitchen keeps its v1 as the owner's own dishes, and the
   regional food data the owner is building remains the plan for food data.
3. **Fetch live instead of bundling.** Fits the terms best (the API is the
   permitted route) and breaks the app's local-first rule for recipes, so it is
   a product change, not a build step.

If the answer is yes: a supporter tier (an owner's cost), an entry in
`docs/attribution-requirement.md` and `AttributionCatalog` with the line above,
then step 5 through the ingredient table. None of that is started.
