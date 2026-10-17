# Recipe sources a commercial app can use (T04, 2026-10-16)

**Asked by the owner, 2026-10-16:** instead of TheMealDB, "look for an
open-source alternative that I can use commercially". **The owner picked the
Wikibooks Cookbook the same day; it is built** (see "Built" at the end).

**Rule applied:** a source counts only if its *own* licence or terms, read at
the source, allow commercial use. A dataset someone else uploaded with a licence
tag does not count when the recipes were scraped from a site that never granted
one: an uploader cannot license what they do not own.

## The one source confirmed today

**Wikibooks Cookbook** — <https://en.wikibooks.org/wiki/Cookbook:Table_of_Contents>

- **Licence, from the site's own footer:** "Text is available under the
  Creative Commons Attribution-ShareAlike License; additional terms may apply."
  CC BY-SA allows commercial use.
- **Obligations:** credit (title, authors via page history, link, licence), say
  what was changed, and **share-alike**: the recipe text Almanac ships, and
  changes to it, stay under CC BY-SA. The app's own code is not affected. The
  app already ships CC BY-SA exercise illustrations on these terms, and the
  Attributions page already handles them.
- **Size:** 3,830 recipe pages (MediaWiki API, `Category:Recipes`, 2026-10-16).
  33 in "Middle Eastern recipes"; one Saudi dish found by search (Shitha).
- **Shape:** written pages, not data. Ingredients are lines of prose with
  quantities in mixed units; servings are sometimes given; no nutrition. A
  2024-07-31 dump is published as a dataset (Hugging Face
  `gossminn/wikibooks-cookbook`, also CC BY-SA 4.0). Turning pages into
  ingredient rows the Kitchen matcher can use is real work, and quality varies.
- **Images:** each image has its own licence on Wikimedia Commons; not covered
  by the text licence.

## Likely usable, not confirmed today

**US government recipes**: USDA MyPlate Kitchen (with nutrition per serving)
and the NIH/NHLBI "Keep the Beat" cookbooks. Works by US federal employees are
public domain (17 U.S.C. §105), which would allow commercial use with no
share-alike. **Not confirmed**, for three reasons:

- `myplate.gov` does not resolve from the owner's iMac (DNS failure, curl and
  fetch, 2026-10-16), so its terms could not be read.
- `nih.gov`'s policy page sits behind a bot check, which this session does not
  get around.
- Public domain is not automatic here. The NHLBI cookbooks say their recipes
  were "created especially for the NHLBI" by an outside chef, and contractors'
  work can be copyrighted. MyPlate says some recipe images "may not be from the
  original source".

To confirm: the owner opens <https://www.myplate.gov/about-us> and the NIH web
policies page in his own browser, or emails the agencies.

## Ruled out

| Source | Why |
|---|---|
| Kaggle sets tagged CC0 (Food.com, AllRecipes, "Better Recipes") | Scraped from sites that grant no licence; the tag is the uploader's |
| RecipeNLG, Recipe1M+ | No licence found (TensorFlow catalog: "No known license"); Recipe1M+ is research-only |
| "Recipe Dataset (over 2M)" | CC BY-NC-SA: non-commercial |
| CJStandingwater/Cookbook (MIT) | Two items in the repository |
| TheMealDB | The owner's T04 answer: not used |

## If the owner picks Wikibooks

The work, in order: import the dump into Kitchen's existing recipe shape
(`docs/features/kitchen.md`), parse ingredient lines into catalog foods with
the ingredient table, drop recipes that do not parse rather than guess, an
Attributions entry with the CC BY-SA terms, and a note on each recipe linking
its Wikibooks page. Serving counts: ask, as `CONTEXT.md` (Kitchen, 2026-10-06)
already decided for imported recipes.

Sources read: the Wikibooks footer and MediaWiki API; the Hugging Face dataset
card; the TensorFlow Datasets catalog entry for RecipeNLG; the NHLBI cookbooks'
front matter (via search); the Kaggle listings (via search).

## Built (2026-10-16)

The owner answered "Wikibooks Cookbook". What exists:

- **`tools/recipes`** fetches every page in `Category:Recipes` (3,797) through
  the MediaWiki API into the food-data lake, and builds
  `Sources/AlmanacCore/Kitchen/Resources/wikibooks-recipes.json`: **298
  recipes**, 70 with a stated serving count. Its README has the line-by-line
  rule and the counts. Ingredient lines are matched through
  `tools/recipes/ingredients.csv` (198 ingredients) and converted to grams
  with USDA SR Legacy household measures.
- **The app** installs the file after the nutrition reference
  (`WikibooksRecipeBundle`, Migration 062). Each recipe becomes an `almanac:`
  dish with a `kitchen_recipe_source` row (title, link, revision, licence).
  Kitchen lists it with the credit line and a link to its page, and asks for a
  serving count when the page gives none. Saved meals does not list it.
- **Attributions:** the entry `wikibooks-cookbook`, CC BY-SA 4.0, with the
  changes stated.
- Decisions the owner did not make (pork and alcohol left out, no methods,
  how lines become grams…) are in `CONTEXT.md`, "Kitchen recipes from
  Wikibooks".

Not done: Arabic recipe names (the pages are English), recipe images, and the
procedure text.
