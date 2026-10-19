# Open Food Facts — packaged products and barcodes

**Owner, 2026-10-19:** "Use Open Food Facts" (packaged products and barcodes).
This reverses the earlier rule that Open Food Facts, licence group C, never
ships (`docs/almanac-technical-spec-v1_0.md` §licence groups). It still never
enters the nutrition reference bundle; it ships beside it.

## Licence, checked 2026-10-19

Read at <https://world.openfoodfacts.org/terms-of-use> and the ODbL summary at
<https://opendatacommons.org/licenses/odbl/summary/>.

| Part | Licence | What it asks of Almanac |
|---|---|---|
| The database | Open Database License (ODbL) 1.0 | Attribute any public use, keep the licence notice, and offer any adapted database publicly used under the ODbL (share-alike); a DRM'd copy must come with an unrestricted one. Commercial use is allowed. |
| Individual contents | Database Contents License (DbCL) 1.0 | No conditions beyond the database's. |
| Product photos | CC BY-SA, plus third-party rights in packaging | **Not used.** |

Open Food Facts' own re-use terms add: name Open Food Facts with a link to
openfoodfacts.org (or the product page), mention the licence, and share
derivative works under the same conditions.

## How Almanac meets it

- **Kept apart.** The products are their own database, `Sources/AlmanacCore/
  Nutrition/Resources/open-food-facts.json`, installed into their own tables
  (`off_product`, `off_value`, `off_barcode`, Migration 067; every row group
  C). The nutrition reference (`almanac.sqlite`, groups A/B/N) is unchanged and
  its licence guard still refuses group C, so share-alike cannot reach it. No
  Open Food Facts product is merged with a reference food.
- **Released under the ODbL.** That file is the adapted database. It carries
  the notice, ships inside the app unencrypted (App Store encryption covers the
  executable, not resources), and `tools/openfoodfacts` is the method that made
  it (ODbL 4.6b).
- **Credited.** Attributions entry `off`: title, link, ODbL and DbCL, the
  notice, and what was changed. Each product keeps its product-page URL.

## What is in it

Products whose countries include Saudi Arabia, the UAE, Kuwait, Qatar, Bahrain
or Oman, with a name and energy, protein, fat and carbohydrate (export of
2026-10-18, SHA-256 in the merge log). Energy given only in kJ is converted at
4.184 kJ/kcal. Values are per 100 g, or per 100 mL when the pack or serving is
in mL. A product with an impossible value (negative, over 100 g per 100 g,
over 900 kcal) is left out, never corrected. Carbohydrate is mapped to
`carbohydrate_available` (Open Food Facts records the EU label figure, fibre
excluded); declared label values are qualifier `borrowed`, label energy
`calculated_factor`. The label's serving becomes a "serving" portion when it is
in grams.

One record per real product: see `docs/features/open-food-facts-merge-log.md`.

## Rebuild

```sh
cd tools/openfoodfacts
python3 -m almanac_off fetch    # the export → $ALMANAC_FOOD_DATA/raw/off, with SHA256SUMS
python3 -m almanac_off build    # → open-food-facts.json and the merge log
python3 -m unittest discover -s tests -t .
```
