# Almanac Open Food Facts build

Builds `Sources/AlmanacCore/Nutrition/Resources/open-food-facts.json` (ODbL)
and `docs/features/open-food-facts-merge-log.md` from Open Food Facts' CSV
export. The licence, the scope and how share-alike is kept away from the
nutrition reference: `docs/features/open-food-facts.md`.

```sh
python3 -m almanac_off fetch   # ~1.3 GB export → $ALMANAC_FOOD_DATA/raw/off (default ~/ALManac-food-data)
python3 -m almanac_off build
python3 -m unittest discover -s tests -t .
```

Standard library only.
