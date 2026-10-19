# Food data sources: licences and attribution

Checked 2026-10-19 at the publisher, before use. The pipeline's own record of
each source is `tools/nutrition/dictionary/sources.csv`; the in-app credit is
`AttributionCatalog` (Settings → About → Attributions).

## USDA FoodData Central — Foundation Foods, SR Legacy, FNDDS

| | |
|---|---|
| Publisher | U.S. Department of Agriculture, Agricultural Research Service |
| Licence | Public domain, published under **CC0 1.0 Universal** |
| Where read | <https://fdc.nal.usda.gov/api-guide> "Licensing": "USDA FoodData Central data are in the public domain and they are not copyrighted. They are published under CC0 1.0 Universal (CC0 1.0)." |
| Attribution | Not required; requested. Suggested citation, used verbatim in the app: "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019. fdc.nal.usda.gov." USDA also asks to be told of products that use the data. |
| Commercial use | Yes. The FAQ lists "Developing commercial nutrient analysis software and applications for private sector purposes" among the intended uses. |
| Share-alike | None. |
| Licence group | A (`licence_groups.csv`), ships. |

The three data types and what Almanac takes from each, all from the full CSV
download of 2026-04-30 (`FoodData_Central_csv_2026-04-30`, already the `usda`
input of the food-data lake):

| Data type | Release in the download | Used for | Code kept |
|---|---|---|---|
| Foundation Foods | April 2026 | nutrient values, household measures | `NDB_number` |
| SR Legacy | April 2018 (final; never updated) | core nutrient values, household measures | `NDB_number` |
| FNDDS | 2021–2023 (October 2024) | food codes, portion weights, values | `food_code` |

Release dates from <https://fdc.nal.usda.gov/download-datasets>. Every food
is `usda:<fdc_id>`; the code is in `nutrition_food.source_record`.

**Not yet in the shipped bundle.** `fdc.nal.usda.gov` was not reachable from
the 2026-10-19 build session, so SR Legacy and FNDDS are canonicalised by the
pipeline but the shipped `almanac.sqlite` still holds Foundation Foods only.
Rebuild on the machine that holds the lake (`tools/nutrition/README.md`):

```sh
cd tools/nutrition
python3 -m almanac_nutrition all
python3 -m almanac_nutrition qa
python3 -m almanac_nutrition merge
cp "$ALMANAC_FOOD_DATA/build/almanac.sqlite" ../../Sources/AlmanacCore/Nutrition/Resources/almanac.sqlite
```

(`$ALMANAC_FOOD_DATA` defaults to `~/ALManac-food-data`.) If the lake's
`manifests/usda.json` does not list `sr_legacy_food.csv`,
`survey_fndds_food.csv`, `wweia_food_category.csv` or `input_food.csv`,
`extract usda` stops and names the file: re-record the manifest from the
download first.

## Duplicates across sources

One record per real food: `docs/features/food-merge-log.md`, written by
`python3 -m almanac_nutrition merge`.
