"""Rebuild almanac.sqlite with native dishes, from the shipped bundle instead of the lake.

The four reference sources' canonical row sets are recovered from the shipped
bundle (which is their union), then the real pipeline runs: extract almanac,
canonicalise almanac, union, bundle.

    python3 tools/nutrition/rebuild_from_bundle.py SCRATCH_DIR [--no-dishes]

then copy SCRATCH_DIR/build/almanac.sqlite over the shipped one. With --no-dishes the
result must equal the shipped bundle row for row; check that before trusting it.

ponytail: for sessions without the lake; `all` on the lake is the real build
"""
import sqlite3, sys
from pathlib import Path
repo = Path(__file__).resolve().parents[2]
lake_root = Path(sys.argv[1])
sys.path.insert(0, str(repo / "tools/nutrition"))
from almanac_nutrition.dictionary import load as load_dictionary
from almanac_nutrition.lake import Lake
from almanac_nutrition.model import Food, FoodName, Value, Portion
from almanac_nutrition.canonical_io import write_canonical
from almanac_nutrition import bundle
from almanac_nutrition.sources import almanac

dictionary = load_dictionary()
src = sqlite3.connect(repo / "Sources/AlmanacCore/Nutrition/Resources/almanac.sqlite")
meta = dict(src.execute("select key, value from bundle_meta"))
print("bundle dictionary", meta["dictionary_sha256"][:12], "current", dictionary.sha256[:12])
lake = Lake(lake_root)
for (ns,) in src.execute("select namespace from nutrition_source where namespace <> 'almanac'"):
    foods = [Food(*r[1:]) for r in src.execute("select food_ref, namespace, local_id, licence_group, food_group_code, food_group_name, source_record from nutrition_food where namespace=?", (ns,))]
    like = ns + ":%"
    names = [FoodName(r[0], r[1], r[2], bool(r[3])) for r in src.execute("select * from nutrition_food_name where food_ref like ?", (like,))]
    values = [Value(*r[:5], r[5] or "", *r[6:]) for r in src.execute("select * from nutrition_value where food_ref like ?", (like,))]
    portions = [Portion(*r[:6], r[6] or "", *r[7:]) for r in src.execute("select * from nutrition_portion where food_ref like ?", (like,))]
    write_canonical(lake.canonical(ns), namespace=ns, foods=foods, names=names, values=values,
                    portions=portions, dictionary=dictionary, inputs=[{"recovered_from": "almanac.sqlite"}])
if "--no-dishes" not in sys.argv:
    almanac.extract(lake)
    print(almanac.canonicalise(lake, dictionary)["counts"])
bundle.union(lake, dictionary)
print(bundle.build(lake, dictionary)["counts"])
