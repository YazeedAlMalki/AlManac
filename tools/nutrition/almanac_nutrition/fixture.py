"""A small synthetic bundle for AlmanacCore's tests — the cross-language contract.

`python3 -m almanac_nutrition fixture` regenerates fixtures/bundle_v1.sql by
running the real canonical writer, union and bundle stages over the rows
below, so the SQL AlmanacCore imports in its tests is exactly what the
pipeline writes. Every food here is invented and is named "Fixture …".
"""
from __future__ import annotations

import sqlite3
import tempfile
from pathlib import Path

from . import bundle
from .canonical_io import write_canonical
from .dictionary import Dictionary
from .lake import Lake
from .model import Food, FoodName, Value

FIXTURE_PATH = Path(__file__).resolve().parent.parent / "fixtures" / "bundle_v1.sql"
FIXED_META = {"built_at": "fixture", "tool_revision": "fixture", "union_manifest_sha256": "fixture"}


def _food(namespace, local_id, group_code, group_name, names, values, dictionary):
    group = dictionary.group_of(namespace)
    food = Food(namespace, local_id, group, group_code, group_name, "fixture")
    food_names = [FoodName(food.food_ref, language, name, i == 0)
                  for i, (language, name) in enumerate(names)]
    rows = [Value(food.food_ref, nutrient, basis, amount, qualifier, confidence, source_value,
                  source_id, unit, group)
            for nutrient, basis, amount, qualifier, confidence, source_value, source_id, unit in values]
    return food, food_names, rows


def rows(dictionary: Dictionary) -> dict[str, tuple[list, list, list]]:
    g, ml = "per_100g", "per_100ml"
    kj = "Energy with dietary fibre, equated (kJ)"
    foods = [
        ("usda", "900001", "0800", "Cereal Grains and Pasta", [("en", "Fixture cereal, raw")], [
            ("energy_kcal", g, 379.0, "calculated_factor", "NC", "379", "2048", "KCAL"),
            ("energy_general_atwater_kcal", g, 382.0, "calculated_factor", "NC", "382", "2047", "KCAL"),
            ("protein", g, 13.2, "calculated_factor", "NC", "13.2", "1003", "G"),
            ("fat_total", g, 6.5, "measured", "A", "6.5", "1004", "G"),
            ("carbohydrate_by_difference", g, 67.7, "calculated_factor", "NC", "67.7", "1005", "G"),
            ("fibre_total_dietary", g, 10.1, "measured", "A", "10.1", "1079", "G"),
            ("alcohol", g, 0.0, "zero_reported", "A", "0.0", "1018", "G"),
        ]),
        ("cofid", "900-001", "F", "", [("en", "Fixture fruit, canned")], [
            ("energy_kcal", g, 151.0, "calculated_factor", "", "151", "KCALS", "kcal"),
            ("protein", g, 2.9, "measured", "", "2.9", "PROT", "g"),
            ("fat_total", g, 15.2, "measured", "", "15.2", "FAT", "g"),
            ("carbohydrate_available_monosaccharide", g, 0.8, "measured", "", "0.8", "CHO", "g"),
        ]),
        ("cofid", "900-002", "QE", "", [("en", "Fixture wine, red")], [
            ("energy_kcal", ml, 76.0, "calculated_factor", "", "76", "KCALS", "kcal"),
            ("protein", ml, None, "trace", "", "Tr", "PROT", "g"),
            ("fat_total", ml, 0.0, "zero_reported", "", "0", "FAT", "g"),
            ("carbohydrate_available_monosaccharide", ml, 0.2, "measured", "", "0.2", "CHO", "g"),
            ("fibre_total_dietary", ml, 0.0, "zero_reported", "", "0", "AOACFIB", "g"),
            ("alcohol", ml, 10.7, "measured", "", "10.7", "ALCO", "g"),
        ]),
        ("cofid", "900-003", "MAA", "", [("en", "Fixture meat, lean")], [
            ("energy_kcal", g, 125.0, "calculated_factor", "", "125", "KCALS", "kcal"),
            ("protein", g, 20.0, "measured", "", "20.0", "PROT", "g"),
            ("fat_total", g, 5.0, "measured", "", "5.0", "FAT", "g"),
            ("carbohydrate_available_monosaccharide", g, None, "not_analysed", "", "N", "CHO", "g"),
        ]),
        ("cofid", "900-004@row9", "DG", "", [("en", "Fixture vegetable, repeated publisher code")], [
            ("energy_kcal", g, 62.0, "calculated_factor", "", "62", "KCALS", "kcal"),
        ]),
        ("ciqual", "900001", "0701", "breads and similar", [("en", "Fixture bread, white"),
                                                           ("fr", "Pain blanc (fixture)")], [
            ("energy_kcal", g, 250.0, "calculated_factor", "D", "250", "328", "kcal"),
            ("protein", g, 9.01, "measured", "A", "9,01", "25000", "g"),
            ("fat_total", g, 0.5, "below_loq", "A", "< 0,5", "40000", "g"),
            ("carbohydrate_available", g, 50.3, "measured", "B", "50,3", "31000", "g"),
            ("fibre_total_dietary", g, 3.1, "measured", "B", "3,1", "34100", "g"),
            ("alcohol", g, None, "not_analysed", "", "-", "60000", "g"),
        ]),
        ("afcd", "F900001", "31304", "", [("en", "Fixture stock, liquid")], [
            ("energy_kcal", g, 18 / 4.184, "calculated_factor", "Recipe", "18", kj, "kJ"),
            ("protein", g, 0.2, "calculated_recipe", "Recipe", "0.2", "Protein (g)", "g"),
            ("fat_total", g, 0.2, "calculated_recipe", "Recipe", "0.2", "Fat, total (g)", "g"),
            ("carbohydrate_available", g, 0.4, "calculated_recipe", "Recipe", "0.4",
             "Available carbohydrate, with sugar alcohols (g)", "g"),
            ("fibre_total_dietary", g, 0.0, "zero_reported", "Recipe", "0", "Total dietary fibre (g)", "g"),
            ("alcohol", g, 0.0, "zero_reported", "Recipe", "0", "Alcohol (g)", "g"),
            ("energy_kcal", ml, 19 / 4.184, "calculated_factor", "Recipe", "19", kj, "kJ"),
            ("protein", ml, 0.21, "calculated_recipe", "Recipe", "0.21", "Protein (g)", "g"),
            ("fat_total", ml, 0.21, "calculated_recipe", "Recipe", "0.21", "Fat, total (g)", "g"),
            ("carbohydrate_available", ml, 0.42, "calculated_recipe", "Recipe", "0.42",
             "Available carbohydrate, with sugar alcohols (g)", "g"),
            ("fibre_total_dietary", ml, 0.0, "zero_reported", "Recipe", "0", "Total dietary fibre (g)", "g"),
            ("alcohol", ml, 0.0, "zero_reported", "Recipe", "0", "Alcohol (g)", "g"),
        ]),
        ("almanac", "fixture-dish", "native", "Almanac native", [("en", "Fixture dish"),
                                                                ("ar", "طبق تجريبي")], [
            ("protein", g, 10.0, "calculated_recipe", "", "10", "protein", "g"),
            ("fat_total", g, 8.0, "calculated_recipe", "", "8", "fat_total", "g"),
            ("carbohydrate_available", g, 20.0, "calculated_recipe", "", "20", "carbohydrate_available", "g"),
            ("fibre_total_dietary", g, 2.0, "calculated_recipe", "", "2", "fibre_total_dietary", "g"),
        ]),
    ]
    grouped: dict[str, tuple[list, list, list]] = {}
    for namespace, local_id, code, name, names, values in foods:
        food, food_names, value_rows = _food(namespace, local_id, code, name, names, values, dictionary)
        f, n, v = grouped.setdefault(namespace, ([], [], []))
        f.append(food)
        n.extend(food_names)
        v.extend(value_rows)
    return grouped


def render(dictionary: Dictionary) -> str:
    with tempfile.TemporaryDirectory() as directory:
        lake = Lake(directory)
        for namespace, (foods, names, values) in rows(dictionary).items():
            write_canonical(lake.canonical(namespace), namespace=namespace, foods=foods, names=names,
                            values=values, dictionary=dictionary, inputs=[], notes={"fixture": True})
        bundle.union(lake, dictionary)
        bundle.build(lake, dictionary)
        con = sqlite3.connect(lake.bundle)
        try:
            with con:
                con.executemany("UPDATE bundle_meta SET value = ? WHERE key = ?",
                                [(value, key) for key, value in FIXED_META.items()])
            # iterdump writes tables in name order, so nutrition_food precedes the
            # nutrition_source it references: replay with foreign keys off, as sqlite3 does.
            return "PRAGMA foreign_keys=OFF;\n" + "\n".join(con.iterdump()) + "\n"
        finally:
            con.close()


def write(dictionary: Dictionary, path: Path = FIXTURE_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render(dictionary), encoding="utf-8")
    return path
