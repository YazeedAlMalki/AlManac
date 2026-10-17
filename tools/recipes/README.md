# Almanac recipe import — Wikibooks Cookbook

Builds `Sources/AlmanacCore/Kitchen/Resources/wikibooks-recipes.json`, the
recipes Kitchen ships, from the Wikibooks Cookbook. The owner chose the source
on 2026-10-16 (T04; `docs/features/recipe-sources.md`). The app installs the
file into the person's database after the nutrition reference
(`WikibooksRecipeBundle`, Migration 062).

```sh
cd tools/recipes
python3 -m almanac_recipes fetch     # every page in Category:Recipes → the lake
python3 -m almanac_recipes review    # what each ingredient row converts to
python3 -m almanac_recipes build     # the lake → the bundled JSON
python3 -m unittest discover -s tests -t .
```

The lake is `~/ALManac-food-data` (override with `ALMANAC_FOOD_DATA`), the one
`tools/nutrition` reads. `fetch` writes `raw/wikibooks/<date>/pages.json`
there through the MediaWiki API (current wikitext and revision id of each
page, paced, backing off on HTTP 429). Fetched pages never enter the repository.
`build` also reads USDA FoodData Central's `food.csv` and `food_portion.csv` from
the lake, and the food names from the shipped `almanac.sqlite`.

## The rule

Every ingredient line must become a catalog food and a weight in grams, or be
a seasoning that can be set aside. Any other line drops the **whole recipe**:
"drop recipes that do not parse rather than guess". What that means line by line:

| Line | Result |
|---|---|
| A mass (`250 g`, `1 lb`, `8 oz`) | Converted exactly. |
| A volume (`1 ½ cups`, `2 tbsp`, `500 ml`) | Through the USDA SR Legacy household measure named in `ingredients.csv` (onion: "1 cup, chopped" = 160 g). US customary millilitres. |
| A count (`3 eggs`, `2 large onions`, `4 cloves garlic`) | Through the count measure named for the ingredient; a size word picks that size when USDA has it. A count of a different thing ("1 head garlic" when the measure is a clove) is unreadable. |
| A count with a stated weight (`1 can (400 g) tomatoes`) | The stated weight. |
| A range (`2–3 tbsp`) | Its midpoint. |
| No amount, and "to taste", "for garnish", "optional"… or a seasoning row | Set aside. |
| A pinch or a dash | Set aside. |
| A seasoning counted with no count measure (`2 bay leaves`) | Set aside. |
| Anything else with no amount (`Olive oil`, `Tomatoes`) | Unreadable. |
| An ingredient not in `ingredients.csv` | Unreadable. |

A line's own words are matched first ("egg yolks" is not "egg"), then its link
to a Cookbook ingredient page, but only when the words add nothing but
preparation ("chopped", "fresh", "large"…). Recipes with fewer than two
ingredients left are dropped. Recipes that use an ingredient marked `pork` or
`alcohol` in `ingredients.csv` are left out unless `--allow-excluded` is
given (`CONTEXT.md`, Kitchen recipes).

## `ingredients.csv`

One row per ingredient: `aliases` (`;`-separated: Cookbook page names and
what authors type), `food_ref` (the shipped nutrition food), `usda_fdc` (the
SR Legacy food whose household measures convert volumes and counts),
`volume` (that food's measure for volumes, exactly as USDA words it), `each`
(its measure for one item), `seasoning` (`y`: may be set aside when
unmeasured), `exclude` (`pork` or `alcohol`). `review` prints what each row
resolves to; `build` refuses to run while any row names a food or measure
that does not exist.

## Measured 2026-10-16

3,797 pages; 116 with no ingredient list; 3,365 with a line that could not be
read; 10 with fewer than two ingredients; 8 left out for pork or alcohol.
**298 recipes kept**, 70 of which state their servings. The biggest single
blockers: an unmeasured oil line (133 recipes), and ingredients not yet in
the table. Adding rows to `ingredients.csv` is how the count grows.

## Licence

The recipes are CC BY-SA 4.0 (the Wikibooks footer). The bundle is an
adaptation and is released under the same licence; the Attributions page
entry `wikibooks-cookbook` says what was changed, and each recipe carries its
page's title, link and revision. USDA FoodData Central is public domain.
